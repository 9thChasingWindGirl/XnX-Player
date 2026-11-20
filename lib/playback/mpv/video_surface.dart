import 'dart:async';
import 'dart:io';

import 'mpv_window.dart';

/// Owns the two rectangles between Flutter and mpv.
///
/// Layer 1: a container window created as a child of the Flutter runner window.
/// Layer 2: whatever mpv paints into — a child of the container, or the
/// container itself depending on how `wid` is interpreted.
///
/// Neither layer follows its parent when the app is resized or switched to
/// fullscreen, so this class polls both and re-fits them. That is the job
/// Zerk Play 2.0 gives its native `VideoHost`; doing it here keeps the Windows
/// runner template stock, which matters because CI regenerates it.
class VideoSurface {
  VideoSurface(this.parent, {this.visible = true});

  final int parent;

  int? _host;
  int? _video;
  WindowBox? _hostBox;
  WindowBox? _videoBox;
  Timer? _timer;
  bool visible;
  String _diagnostics = '未创建容器';

  /// Whether the container is currently on screen. Separate from [visible]
  /// because "the host asked for the picture" and "the picture is ready to be
  /// shown" are two different moments.
  bool _revealed = false;

  /// When [show] was called, used to give up waiting for a child window that is
  /// never going to appear (audio-only files, or a build that paints straight
  /// into the container).
  DateTime? _visibleSince;

  /// How long [sync] waits for mpv's child to exist before revealing anyway.
  static const Duration _revealGrace = Duration(milliseconds: 900);

  /// The container handle. This is what mpv gets as `wid`.
  int? get handle => _host;

  String get diagnostics => _diagnostics;

  bool get isVisible => visible;

  void start({Duration interval = const Duration(milliseconds: 400)}) {
    if (!Platform.isWindows) {
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => sync());
    sync();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Creates the container if it is missing or was destroyed by a rebuild of
  /// the native window.
  void ensureHost() {
    if (!Platform.isWindows) {
      return;
    }
    final int? current = _host;
    if (current != null && Win32.isWindow(current)) {
      return;
    }
    final WindowBox? box = Win32.clientBox(parent);
    if (box == null || box.isEmpty) {
      return;
    }
    _host = Win32.createHost(parent, box);
    _video = null;
    _hostBox = null;
    _videoBox = null;
    _diagnostics = _host == null ? '容器创建失败（parent=0x${parent.toRadixString(16)}）' : '容器已创建';
  }

  /// Re-fits both layers. Cheap enough to call on a timer.
  void sync() {
    if (!Platform.isWindows) {
      return;
    }
    ensureHost();
    final int? host = _host;
    if (host == null) {
      return;
    }

    final int? video = Win32.videoChild(host);
    if (video != _video) {
      _video = video;
      _videoBox = null;
    }

    // Sizes belong in the diagnostics: "video=none" alone did not say whether
    // the child was missing or merely 0x0, which is what the F1 panel needed.
    final WindowBox? hostClient = Win32.clientBox(host);
    final WindowBox? videoClient = video == null ? null : Win32.clientBox(video);
    final String classes =
        Win32.children(host).map((ChildWindow c) => c.className).join(',');
    String size(WindowBox? box) => box == null ? '-' : '${box.width}x${box.height}';
    final String next = 'host=0x${host.toRadixString(16)} ${size(hostClient)} '
        'video=${video == null ? 'none' : '0x${video.toRadixString(16)} ${size(videoClient)}'} '
        '子窗口=[$classes]';
    if (next != _diagnostics) {
      _diagnostics = next;
    }

    if (!visible) {
      // Nothing may be laid out while hidden: fitting calls SetWindowPos with
      // SWP_SHOWWINDOW, which would flash an opaque window over Flutter's
      // loading panel every poll.
      Win32.setVisible(host, visible: false);
      _revealed = false;
      _hostBox = null;
      _videoBox = null;
      return;
    }

    // Order matters. The container is moved first *without* being shown, then
    // mpv's child is fitted to the container's client area, and only when both
    // rectangles agree does the container become visible.
    //
    // Showing inside the move (the old behaviour) left one painted frame where
    // the container was already on screen at its new size while mpv's child
    // still had its own — a wrongly sized window containing a strip of picture
    // and the OSD at the wrong scale. That is the window that flashes on
    // startup, caught mid-resize.
    final WindowBox? outer = Win32.clientBox(parent);
    if (outer != null && !outer.isEmpty && outer != _hostBox) {
      Win32.fit(host, outer, reveal: _revealed);
      _hostBox = outer;
      _videoBox = null;
    }

    if (video != null) {
      final WindowBox? inner = Win32.clientBox(host);
      if (inner != null && !inner.isEmpty && inner != _videoBox) {
        Win32.fit(video, inner);
        _videoBox = inner;
      }
    }

    if (!_revealed) {
      final WindowBox? hostClient = Win32.clientBox(host);
      final WindowBox? videoClient = video == null ? null : Win32.clientBox(video);
      final bool aligned = hostClient != null && videoClient != null && hostClient == videoClient;
      final DateTime? since = _visibleSince;
      final bool graceOver =
          since != null && DateTime.now().difference(since) > _revealGrace;
      // No child, or one that refuses to take the container's size, would
      // otherwise leave a black screen up forever; the grace period is the
      // escape hatch. Before it expires the alignment test is what keeps a
      // half-sized window from being shown.
      if (aligned || graceOver) {
        Win32.setVisible(host, visible: true);
        _revealed = true;
      }
    }

    // Z-order does not survive a fullscreen transition or a Flutter view
    // rebuild: the container can end up under FLUTTERVIEW, which renders as a
    // perfectly black screen with a healthy mpv log behind it. Raising is free.
    Win32.raise(host);
  }

  void hide() {
    visible = false;
    _revealed = false;
    _visibleSince = null;
    final int? host = _host;
    if (host != null) {
      Win32.setVisible(host, visible: false);
    }
  }

  void show() {
    visible = true;
    _visibleSince = DateTime.now();
    _hostBox = null;
    _videoBox = null;
    sync();
    // `sync` may have to wait for mpv's child to appear before it dares reveal
    // the container; check again shortly instead of waiting for the next poll.
    if (!_revealed) {
      Timer(const Duration(milliseconds: 120), () {
        if (visible) {
          sync();
        }
      });
    }
  }

  /// Forgets the cached rectangles and re-fits immediately.
  ///
  /// Used after a fullscreen toggle: waiting for the next poll would leave the
  /// picture at the old size for up to 400ms, which reads as a stuck frame.
  void refit() {
    _hostBox = null;
    _videoBox = null;
    sync();
  }

  void dispose() {
    stop();
    final int? host = _host;
    _host = null;
    _video = null;
    if (host != null) {
      Win32.destroy(host);
    }
  }
}
