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
  VideoSurface(this.parent, {bool visible = true}) : _visible = visible;

  final int parent;

  int? _host;
  int? _video;
  WindowBox? _hostBox;
  WindowBox? _videoBox;
  Timer? _timer;
  bool _visible;
  String _diagnostics = '未创建容器';

  /// The container handle. This is what mpv gets as `wid`.
  int? get handle => _host;

  String get diagnostics => _diagnostics;

  bool get isVisible => _visible;

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
      final String classes = Win32.children(host).map((ChildWindow c) => c.className).join(',');
      _diagnostics =
          'host=0x${host.toRadixString(16)} video=${video == null ? 'none' : '0x${video.toRadixString(16)}'} 子窗口=[$classes]';
    }

    if (!_visible) {
      // Nothing may be laid out while hidden: fitting calls SetWindowPos with
      // SWP_SHOWWINDOW (`MoveWindow` repaints too), which would flash an opaque
      // window over Flutter's loading panel every poll.
      Win32.setVisible(host, visible: false);
      _hostBox = null;
      _videoBox = null;
      return;
    }

    final WindowBox? outer = Win32.clientBox(parent);
    if (outer != null && !outer.isEmpty && outer != _hostBox) {
      Win32.fit(host, outer);
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
  }

  void hide() {
    _visible = false;
    final int? host = _host;
    if (host != null) {
      Win32.setVisible(host, visible: false);
    }
  }

  void show() {
    _visible = true;
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
