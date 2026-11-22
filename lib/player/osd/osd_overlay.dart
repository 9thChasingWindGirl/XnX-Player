import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'osd_chrome.dart';
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
/// * input  — the window's hit-test hands Dart only the chrome band and
///   forwards every other pointer position to the video window below, where
///   the Lua side keeps handling its own pointer forwarding.
///
/// The Lua OSD stays alive as the *model* — key bindings, menus, toasts — and
/// is switched by the `osd-engine` user-data flag. While this layer owns the
/// band it paints the popup menu too, because Lua deliberately stops drawing
/// it (two panels, two hit maps, one screen). Lua pushes the rows as data
/// (`type: 'menu'` on `player-event`) and still decides what a row does: the
/// action behind a row is a Lua closure and cannot cross the boundary.
class OsdOverlay {
  OsdOverlay._(this._layer, this._player);

  final OsdLayer _layer;
  final MpvPlayer _player;

  ui.Size _size = ui.Size.zero;

  /// Seek fraction while the pointer drags the bar; the knob follows the
  /// pointer instead of the clock, and the seek lands on release.
  double? _scrubbing;

  /// Whether the pointer is inside the seek strip (wider knob).
  bool _hoverSeek = false;

  String? _toast;
  DateTime? _toastUntil;

  /// The popup menu Lua last pushed, or null when none is open.
  ///
  /// Without this the menu is not merely unpolished but unreachable: Lua's
  /// `dart_chrome` branch skips `draw_menu`, so a dropped `menu` event leaves
  /// the user pressing the menu key at a panel nobody draws. That was the
  /// state of things before this field existed.
  OsdMenu? _menu;

  /// Row under the pointer, 0-based. Local hover only — moving the mouse must
  /// not move Lua's selection, or a drifting pointer would re-run the arrow-key
  /// logic and walk the list by itself.
  int? _menuHover;

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
    if (!_layer.resize(width.round(), height.round())) {
      return;
    }
    _applySize(width, height);
    // MoveWindow can reshuffle the sibling order. Re-raise immediately so the
    // freshly sized layer stays above the mpv surface.
    _layer.raise();
    _schedulePaint();
  }

  void _applySize(double width, double height) {
    _size = ui.Size(width, height);
  }

  /// The layer's current size in device pixels — the same space [OsdChrome]
  /// paints in and the hit zones are tested against.
  ui.Size get size => _size;

  /// Brings [size] in line with the Win32 client area *right now*.
  ///
  /// The periodic poll is fine for painting, but pointer events must never be
  /// mapped with a stale rectangle: after a window resize Flutter already
  /// reports the new widget size while the layer still carried the old one.
  /// The pointer then landed on the visible seek bar but was tested against
  /// the pre-resize geometry (the two marks in the bug screenshot sit a whole
  /// chrome band apart). Reading GetClientRect is cheap enough to do on every
  /// pointer event, and the common case is one comparison.
  void syncSize() {
    final int? app = _appHwnd ?? Win32.appWindow();
    if (app == null) {
      return;
    }
    _appHwnd = app;
    final WindowBox? box = Win32.clientBox(app);
    if (box == null ||
        box.isEmpty ||
        (box.width == _size.width.round() && box.height == _size.height.round())) {
      return;
    }
    resize(box.width.toDouble(), box.height.toDouble());
  }

  /// Cached answer to "did mpv accept the chrome handoff?". Querying the
  /// property on every pointer move would add a synchronous IPC round-trip to
  /// the hot path; the flag is set once during boot and never flips back.
  bool? _ownsChrome;

  /// Whether this layer — not the Lua stage — is drawing the bottom band.
  ///
  /// Input is only claimed when it is: if the handoff failed, the Lua chrome
  /// is what the user sees, and a hidden Dart layer that still tested itself
  /// against its own (invisible) seek strip would swallow presses aimed at the
  /// visible menu row. That is exactly the "OSD acts a band away" symptom.
  bool get ownsChrome => _ownsChrome == true;

  /// Records the result of the hand-off. Called once, after the Lua replied.
  void bindHandoff(bool accepted) {
    _ownsChrome = accepted;
    if (!accepted) {
      // The Lua stage keeps the band; make sure a half-shown layer cannot sit
      // above it.
      setVisible(false);
    }
    _schedulePaint();
  }

  void setVisible(bool visible) {
    if (visible && !ownsChrome) {
      // The Lua stage still owns the band; painting here too would draw the
      // chrome twice and steal presses aimed at its menu row.
      return;
    }
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

  /// Follows the video surface's size. The poll is only a backstop for a
  /// window that changes while no pointer event arrives (fullscreen from a
  /// key, a snap/restore drag); [syncSize] from the pointer forwarder is what
  /// keeps interactive coordinates exact.
  void startSizeWatch() {
    _sizeTimer?.cancel();
    _sizeTimer = Timer.periodic(const Duration(milliseconds: 200), (_) => syncSize());
  }

  /// Whether a normalized pointer position is over the chrome band at all —
  /// the wheel's volume strip.
  bool inChromeZone(double nx, double ny) {
    if (!_visible || !ownsChrome || _size.isEmpty) {
      return false;
    }
    // The chrome occupies the bottom ~35 % of the stage in design units.
    return ny > 0.70;
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

  /// Cached media title. The Lua receives it as `user-data/player/title`; the
  /// independent chrome reads the same property once and remembers it.
  String? _title;

  String get _titleText {
    final String? cached = _title;
    if (cached != null) {
      return cached;
    }
    final String value = _player.getProperty('user-data/player/title') ?? '';
    if (value.isNotEmpty) {
      _title = value;
    }
    return value;
  }

  Future<void> _paint() async {
    final MpvViewState state = _player.state.value;
    final String? toast =
        _toastUntil != null && DateTime.now().isBefore(_toastUntil!) ? _toast : null;

    final double duration = state.duration;
    final OsdChromeModel model = OsdChromeModel(
      title: _titleText,
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
      menu: _menu,
      menuHover: _menuHover,
    );

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, _size.width, _size.height),
    );
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

  /// Format badges, refreshed once per file. Reading five mpv properties on
  /// every 30 fps paint would be a synchronous round-trip storm; the values do
  /// not change while a file plays.
  List<String> _formatBadges = const <String>[];

  void refreshFormat() {
    final int height = int.tryParse(_player.getProperty('video-params/h') ?? '') ?? 0;
    final String gamma = (_player.getProperty('video-params/gamma') ?? '').toLowerCase();
    final String primaries = (_player.getProperty('video-params/primaries') ?? '').toLowerCase();
    final String audio = _player.getProperty('audio-codec-name') ?? '';
    final String hwdec = _player.getProperty('hwdec-current') ?? '';
    final double fps = double.tryParse(_player.getProperty('container-fps') ?? '') ?? 0;
    _formatBadges = <String>[
      if (height >= 2160)
        '4K'
      else if (height > 0)
        '${height}P',
      if (primaries.contains('dolby'))
        'DOLBY VISION'
      else if (gamma == 'pq' || gamma.contains('st2084'))
        'HDR'
      else if (gamma == 'hlg')
        'HLG',
      if (audio.isNotEmpty) audio.toUpperCase(),
      if (fps > 0) '${fps.round()}FPS',
      if (hwdec.isNotEmpty && hwdec != 'no') hwdec.toUpperCase(),
    ];
    _schedulePaint();
  }

  List<String> _badges(MpvViewState state) {
    if (_formatBadges.isNotEmpty) {
      return _formatBadges;
    }
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

  /// The chrome control under a normalized pointer position, or null.
  ///
  /// `seek`, `play`, `back10`, `fwd10`, `menu:<id>` or `menurow:<index>`. The
  /// rectangles come from the same list the paint pass uses, so a drawn button
  /// is a working button — the menu rows included.
  String? actionAt(double nx, double ny) {
    if (!_visible || !ownsChrome || _size.isEmpty) {
      return null;
    }
    final ui.Offset point = ui.Offset(nx * _size.width, ny * _size.height);
    for (final OsdZone zone in OsdChrome.zones(_size, menu: _menu)) {
      if (zone.rect.contains(point)) {
        return zone.id;
      }
    }
    return null;
  }

  /// A window-normalized x mapped onto 0..1 along the painted seek line.
  ///
  /// The line is inset from the window edges, so passing the raw window
  /// fraction to [scrub] would put the knob — and the resulting seek — at a
  /// different place than the cursor.
  double seekFraction(double nx) {
    if (_size.isEmpty) {
      return nx.clamp(0.0, 1.0).toDouble();
    }
    return OsdChrome.fractionAt(_size, nx * _size.width);
  }

  /// Whether a drag is in progress, so the pointer forwarder keeps feeding it
  /// positions even after the cursor leaves the strip.
  bool get scrubbing => _scrubbing != null;

  /// Hover state for the seek strip (a slightly larger knob).
  void setSeekHover(bool hover) {
    if (_hoverSeek != hover) {
      _hoverSeek = hover;
      _schedulePaint();
    }
  }

  /// Whether a Lua popup panel is currently mirrored here. While true, the
  /// wheel over the panel must scroll rows, not change volume.
  bool get hasMenu => _menu != null;

  /// Whether a normalized pointer position lands on the drawn menu panel.
  bool inMenuZone(double nx, double ny) {
    final OsdMenu? menu = _menu;
    if (menu == null || _size.isEmpty) {
      return false;
    }
    return OsdChrome.menuPanel(
      _size,
      menu,
    ).contains(ui.Offset(nx * _size.width, ny * _size.height));
  }

  /// Local hover highlight for a menu row (0-based), or null for none.
  ///
  /// Deliberately *not* forwarded as `menu-op move`: the Lua selection must
  /// stay where the keyboard left it. A pointer drifting across the panel on
  /// its way elsewhere would otherwise rewrite Lua's selection index behind
  /// the user's back, and the next arrow press would jump to wherever the
  /// cursor last hovered. Clicks carry their own index, so hover only picks
  /// the row that gets painted bright.
  void setMenuHover(int? index) {
    if (_menuHover != index) {
      _menuHover = index;
      _schedulePaint();
    }
  }

  /// Consumes one `type: 'menu'` event pushed by the Lua OSD.
  ///
  /// Lua stays the model — it owns the row actions — and mirrors its panel
  /// here as data whenever the Dart chrome owns the bottom band, because in
  /// that mode Lua's own `draw_menu` is skipped and without this no panel
  /// would be drawn at all. `open: false` closes; a malformed packet is
  /// ignored so a half-written event cannot blank a panel that is fine.
  void handleMenuEvent(Map<Object?, Object?> payload) {
    if (payload['open'] == false) {
      if (_menu != null) {
        _menu = null;
        _menuHover = null;
        _schedulePaint();
      }
      return;
    }
    final OsdMenu? menu = OsdMenu.fromEvent(payload);
    if (menu == null) {
      return;
    }
    _menu = menu;
    _menuHover = null;
    _schedulePaint();
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
