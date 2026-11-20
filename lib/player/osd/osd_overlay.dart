import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../design/ps_tokens.dart';
import '../../playback/mpv/mpv_player.dart';
import '../../playback/mpv/mpv_window.dart';
import '../../playback/mpv/osd_layer.dart';

/// Glues the independent OSD window to mpv state.
///
/// Ownership of the chrome moves here from the Lua side:
///
/// * state  — [MpvPlayer.state] already observes time-pos, duration, pause
///   and volume as events; there is no polling.
/// * paint  — [OsdChrome] rasterizes a frame into the layered window. The
///   window is composited by DWM as 8-bit SDR, so HDR passthrough cannot
///   reach it; that is the entire reason this layer exists.
/// * input  — the window's hit-test hands Dart only the seek strip and
///   forwards every other pointer position to the video window below, where
///   the Lua side keeps handling its menus and pointer forwarding unchanged.
///
/// The Lua OSD stays alive for menus and toasts (switched by the
/// `osd-engine` user-data flag); it no longer paints the bottom chrome, so
/// the two engines never draw the same rectangle.
class OsdOverlay {
  OsdOverlay._(this._layer, this._player);

  final OsdLayer _layer;
  final MpvPlayer _player;

  ui.Size _size = ui.Size.zero;
  ui.Image? _lastFrame;

  /// Seek fraction while the pointer drags the bar; the knob follows the
  /// pointer instead of the clock, and the seek lands on release.
  double? _scrubbing;

  /// Whether the pointer is inside the seek strip (wider knob).
  bool _hoverSeek = false;

  String? _toast;
  DateTime? _toastUntil;

  bool _paintScheduled = false;
  bool _visible = false;

  /// The layer callback has no user-data slot, so the single live instance is
  /// recorded statically. One player page owns one overlay; a second player
  /// route never coexists with the first.
  static OsdOverlay? _live;

  /// Creates the overlay as the topmost child of the app window, above the
  /// mpv surface. Returns null off Windows or when window creation fails —
  /// callers keep using the Lua OSD untouched.
  static OsdOverlay? create(MpvPlayer player) {
    if (_live != null) {
      return null;
    }
    final int? app = Win32.appWindow();
    if (app == null) {
      return null;
    }
    final WindowBox? box = Win32.clientBox(app);
    if (box == null || box.isEmpty) {
      return null;
    }
    final OsdLayer? layer = OsdLayer.create(app, box.width, box.height);
    if (layer == null) {
      return null;
    }
    final OsdOverlay overlay = OsdOverlay._(layer, player);
    _live = overlay;
    overlay._applySize(box.width.toDouble(), box.height.toDouble());
    overlay._layer.hide();
    player.state.addListener(overlay._invalidate);
    return overlay;
  }

  // --- lifecycle ----------------------------------------------------------------

  /// Called when the video surface changes size; the overlay follows it so
  /// chrome coordinates stay window coordinates.
  void resize(double width, double height) {
    _applySize(width, height);
    _layer.resize(width.round(), height.round());
    _schedulePaint();
  }

  void _applySize(double width, double height) {
    _size = ui.Size(width, height);
  }

  void setVisible(bool visible) {
    if (_visible == visible) {
      return;
    }
    _visible = visible;
    if (visible) {
      _layer.raise();
      _layer.show();
      _schedulePaint();
    } else {
      _layer.hide();
    }
  }

  bool get visible => _visible;

  Timer? _idleTimer;
  Timer? _sizeTimer;
  int? _appHwnd;

  /// Call on any user activity (pointer move, press, key): shows the chrome
  /// and restarts the hide countdown. Paused playback keeps the chrome up —
  /// the same rule the Lua side applies in [schedule_hide].
  void poke() {
    setVisible(true);
    _idleTimer?.cancel();
    _armIdleTimer();
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 3), () {
      // A pause pressed inside the window keeps the chrome up.
      if (!_player.state.value.paused) {
        setVisible(false);
      }
    });
  }

  /// Follows the video surface's size. A 400 ms poll mirrors [VideoSurface]'s
  /// own re-fit rhythm instead of hooking Win32 size events the runner owns.
  void startSizeWatch() {
    _sizeTimer?.cancel();
    _sizeTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final int? app = _appHwnd ??= Win32.appWindow();
      if (app == null) {
        return;
      }
      final WindowBox? box = Win32.clientBox(app);
      if (box == null ||
          box.isEmpty ||
          (box.width == _size.width.round() && box.height == _size.height.round())) {
        return;
      }
      resize(box.width.toDouble(), box.height.toDouble());
    });
  }

  /// Whether a normalized pointer position is over the chrome band at all —
  /// the wheel's volume strip.
  bool inChromeZone(double nx, double ny) {
    if (!_visible || _size.isEmpty) {
      return false;
    }
    return ny * _size.height > _size.height - OsdChrome.bandHeight;
  }

  void dispose() {
    _idleTimer?.cancel();
    _sizeTimer?.cancel();
    _player.state.removeListener(_invalidate);
    _layer.destroy();
    if (_live == this) {
      _live = null;
    }
  }

  // --- state ----------------------------------------------------------------------

  /// Pushes a transient toast onto the chrome for messages the Dart layer
  /// originates. Lua keeps its own menu toasts.
  void toast(String message, {Duration duration = const Duration(seconds: 2)}) {
    _toast = message;
    _toastUntil = DateTime.now().add(duration);
    _schedulePaint();
  }

  void _invalidate() {
    if (!_visible) {
      return;
    }
    // Pause holds the chrome; resuming restarts the countdown, so the band
    // does not linger over playback the user has already stepped away from.
    if (_player.state.value.paused) {
      _idleTimer?.cancel();
    } else if (_idleTimer == null || !_idleTimer!.isActive) {
      _armIdleTimer();
    }
    _schedulePaint();
  }

  void _schedulePaint() {
    if (_paintScheduled || _size.isEmpty) {
      return;
    }
    _paintScheduled = true;
    // ~30 fps cap: a raster round-trip per state tick is pointless when
    // nothing visible changed between ticks.
    Timer(const Duration(milliseconds: 33), () {
      _paintScheduled = false;
      if (_visible) {
        unawaited(_paint());
      }
    });
  }

  Future<void> _paint() async {
    final MpvViewState state = _player.state.value;
    final String? toast =
        _toastUntil != null && DateTime.now().isBefore(_toastUntil!) ? _toast : null;

    final double duration = state.duration;
    final OsdChromeModel model = OsdChromeModel(
      position: _scrubbing != null ? _scrubbing! * duration : state.position,
      duration: duration,
      paused: state.paused,
      volume: state.volume,
      muted: state.muted,
      badges: _badges(state),
      accent: PsColor.accent,
      scrubbing: _scrubbing,
      hoverSeek: _hoverSeek,
      toast: toast,
    );

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder, _size);
    OsdChrome.paint(canvas, _size, model);
    final ui.Image image = await recorder.endRecording().toImage(
          _size.width.round(),
          _size.height.round(),
        );
    final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null || !_visible) {
      image.dispose();
      return;
    }
    _layer.present(bytes.buffer.asUint8List());
    image.dispose();
  }

  List<String> _badges(MpvViewState state) {
    return <String>[
      if ((state.videoCodec ?? '').isNotEmpty) state.videoCodec!.toUpperCase(),
      if ((state.hwdec ?? '').isNotEmpty && state.hwdec != 'no') state.hwdec!.toUpperCase(),
      if (state.containerFps != null && state.containerFps! > 0)
        '${state.containerFps!.round()}FPS',
    ];
  }

  // --- input --------------------------------------------------------------------
  //
  // The layer itself is see-through: Windows delivers mouse messages to the
  // Flutter view, which is where the chrome's interactions live. The forwarder
  // in player_page.dart asks these three questions before handing a pointer
  // event to the Lua side, so a press on the seek bar never reaches mpv.

  /// Whether a normalized pointer position lands on a chrome control.
  bool inSeekZone(double nx, double ny) {
    if (!_visible || _size.isEmpty) {
      return false;
    }
    return OsdChrome.hotZones(_size).first.contains(ui.Offset(
          nx * _size.width,
          ny * _size.height,
        ));
  }

  /// Hover state for the seek strip (a slightly larger knob).
  void setSeekHover(bool hover) {
    if (_hoverSeek != hover) {
      _hoverSeek = hover;
      _schedulePaint();
    }
  }

  /// Starts or continues a seek drag at normalized fraction [t] (0..1). The
  /// knob follows the pointer; nothing is sent to mpv until [endScrub].
  void scrub(double t) {
    _scrubbing = t.clamp(0.0, 1.0).toDouble();
    _schedulePaint();
  }

  /// Lands the drag: seeks mpv once, then hands the knob back to the clock.
  void endScrub() {
    final double? t = _scrubbing;
    _scrubbing = null;
    if (t == null) {
      return;
    }
    final double duration = _player.state.value.duration;
    if (duration > 0) {
      _player.setProperty('time-pos', (t * duration).toStringAsFixed(3));
    }
    _schedulePaint();
  }

  /// Wheel over the chrome changes volume directly.
  void adjustVolume(double delta) {
    final double volume = _player.state.value.volume + delta;
    _player.setProperty('volume', volume.clamp(0, 130).toStringAsFixed(0));
  }
}
