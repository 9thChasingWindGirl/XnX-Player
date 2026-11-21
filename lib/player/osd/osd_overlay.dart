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
    _sizeTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      syncSize();
      // The VO settles after file-loaded: `video-out-params` / audio format can
      // arrive a beat late, which would leave every badge dim forever. Watch
      // the two properties that decide "lit" and re-resolve only on change —
      // two cheap reads per poll, no full FFI sweep.
      final String outGamma = (_player.getProperty('video-out-params/gamma') ?? '').trim();
      final String audioFormat =
          (_player.getProperty('audio-out-params/format') ?? '').trim();
      if (outGamma != _lastOutGamma || audioFormat != _lastAudioFormat) {
        _lastOutGamma = outGamma;
        _lastAudioFormat = audioFormat;
        refreshFormat();
      }
      // How far mpv has demuxed, in seconds. A stream reports a real lead; a
      // local file reports nothing useful, and the paint drops the lead-in
      // when it is not ahead of the playhead.
      final double cache =
          double.tryParse((_player.getProperty('demuxer-cache-time') ?? '').trim()) ?? 0;
      if (cache != _buffered) {
        _buffered = cache;
        if (_visible) {
          _schedulePaint();
        }
      }
    });
  }

  String _lastOutGamma = '';
  String _lastAudioFormat = '';

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
    _volumeTimer?.cancel();
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
    // Volume is the one state tick the chrome has to answer for itself: it is
    // not a position change, and if the band is hidden there is nothing else on
    // screen to say the level moved.
    final MpvViewState now = _player.state.value;
    final double effective = now.muted ? 0 : now.volume;
    if (_lastVolumeSeen >= 0 && (effective - _lastVolumeSeen).abs() >= 0.5) {
      _showVolume();
    }
    _lastVolumeSeen = effective;

    if (!_visible) {
      return;
    }
    // Pause holds the chrome; resuming restarts the countdown, so the band
    // does not linger over playback the user has already stepped away from.
    if (now.paused) {
      _idleTimer?.cancel();
    } else if (_idleTimer == null || !_idleTimer!.isActive) {
      _armIdleTimer();
    }
    _schedulePaint();
  }

  /// Brings the band up just long enough to show the volume bar.
  void _showVolume() {
    _volumeUntil = DateTime.now().add(const Duration(milliseconds: 1600));
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 1700), () {
      _volumeUntil = null;
      _schedulePaint();
    });
    poke();
  }

  /// Last volume the chrome drew, so the first tick after boot does not flash a
  /// bar for a level the user did not change.
  double _lastVolumeSeen = -1;
  DateTime? _volumeUntil;
  Timer? _volumeTimer;

  /// Seconds mpv has demuxed ahead. 0 for a local file that reports nothing.
  double _buffered = 0;

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
      badgeStyles: _badgeStyles,
      accent: PsColor.accent,
      scrubbing: _scrubbing,
      hoverSeek: _hoverSeek,
      toast: toast,
      volumeHint: _volumeUntil != null && DateTime.now().isBefore(_volumeUntil!)
          ? (state.muted ? 0.0 : (state.volume / 100).clamp(0.0, 1.0).toDouble())
          : null,
      buffered: _buffered,
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

  /// Accent + truthfulness for each badge, keyed by the same label used in
  /// [_formatBadges]. Kept separate from the labels so the plain-string model
  /// contract (and its tests) stay intact.
  Map<String, OsdBadge> _badgeStyles = const <String, OsdBadge>{};

  /// Resolves the format pills from what the *output chain* is really doing.
  ///
  /// The source (`video-params`) says what the file contains; the output
  /// (`video-out-params`, `audio-out-params/format`) says what mpv actually
  /// delivers. A HDR10 file tone-mapped onto SDR, or DTS-HD MA decoded to PCM,
  /// must not light up as if it were passed through — that was the whole point
  /// of the Lua stage's lit/dim split, and the independent layer has to match.
  void refreshFormat() {
    String prop(String name) => (_player.getProperty(name) ?? '').trim();
    int intProp(String name) => int.tryParse(prop(name)) ?? 0;

    final int width = intProp('video-params/w');
    final int height = intProp('video-params/h');
    final int depth = intProp('video-params/plane-depth');
    final String codec = prop('video-format').toUpperCase();
    final String gamma = prop('video-params/gamma').toLowerCase();
    final String primaries = prop('video-params/primaries').toLowerCase();
    final double fps = double.tryParse(prop('container-fps')) ?? 0;
    final String hwdec = prop('hwdec-current');

    // Output-side truth. Empty values mean mpv did not report one — fall back
    // to the source only for the *presence* of the format, never for "lit".
    final String outGamma = prop('video-out-params/gamma').toLowerCase();
    final String outPrimaries = prop('video-out-params/primaries').toLowerCase();
    final bool outHdr = (outPrimaries.contains('2020')) &&
        (outGamma == 'pq' || outGamma == 'hlg' || outGamma.contains('st2084'));

    final String audioFormat = prop('audio-out-params/format').toLowerCase();
    final String audioCodec = prop('audio-codec-name');
    final bool audioPassthrough = audioFormat.isNotEmpty &&
        !audioFormat.contains('float') &&
        !RegExp(r'^[su]\d\d').hasMatch(audioFormat);

    final List<String> badges = <String>[];
    final Map<String, OsdBadge> styles = <String, OsdBadge>{};

    void add(String label, ui.Color color, OsdBadgeTier tier) {
      badges.add(label);
      styles[label] = OsdBadge(label, color, tier);
    }

    if (width >= 3800 || height >= 2100) {
      add('8K', OsdBadge.plainWhite, OsdBadgeTier.fact);
    } else if (width >= 3400 || height >= 2000) {
      add('4K', OsdBadge.plainWhite, OsdBadgeTier.fact);
    } else if (width >= 2400 || height >= 1400) {
      add('1440p', OsdBadge.plainWhite, OsdBadgeTier.fact);
    } else if (height >= 1000) {
      add('1080p', OsdBadge.plainWhite, OsdBadgeTier.fact);
    } else if (height >= 700) {
      add('720p', OsdBadge.plainWhite, OsdBadgeTier.fact);
    } else if (width > 0 && height > 0) {
      add('$width×$height', OsdBadge.plainWhite, OsdBadgeTier.fact);
    }

    if (codec.isNotEmpty) {
      add('$codec${depth >= 10 ? ' 10BIT' : ''}', OsdBadge.plainWhite, OsdBadgeTier.fact);
    }

    final bool sourceDv = primaries.contains('dolby');
    final bool sourceHlg = gamma == 'hlg';
    final bool sourcePq = gamma == 'pq' || gamma.contains('st2084');
    if (sourceDv) {
      // A DV source plays its HDR10 base layer through the PQ output; mpv's
      // video-out-params reports bt.2020/pq, not a "dolby" primaries value.
      // Lighting it needs the same bt.2020+HDR test the Lua stage uses.
      add('DOLBY VISION', OsdBadge.dvPurple,
          outHdr ? OsdBadgeTier.lit : OsdBadgeTier.dim);
    } else if (sourceHlg) {
      add('HLG', OsdBadge.hlgCyan, outHdr ? OsdBadgeTier.lit : OsdBadgeTier.dim);
    } else if (sourcePq) {
      final String label = (intProp('video-params/sig-peak') >= 900) ? 'HDR10' : 'HDR';
      add(label, OsdBadge.hdrGold, outHdr ? OsdBadgeTier.lit : OsdBadgeTier.dim);
    }

    final String audioLabel = _audioBadgeLabel(audioCodec, audioFormat);
    if (audioLabel.isNotEmpty) {
      final ui.Color audioColor = audioLabel.contains('DTS') ? OsdBadge.dtsAmber : OsdBadge.dolbyBlue;
      add(audioLabel, audioColor,
          audioPassthrough ? OsdBadgeTier.lit : OsdBadgeTier.dim);
    }

    if (fps > 0) add('${fps.toStringAsFixed(fps % 1 == 0 ? 0 : 2)}FPS', OsdBadge.plainWhite, OsdBadgeTier.fact);
    if (hwdec.isNotEmpty && hwdec != 'no') {
      add(hwdec.toUpperCase(), OsdBadge.plainWhite, OsdBadgeTier.fact);
    }

    _formatBadges = List<String>.unmodifiable(badges);
    _badgeStyles = Map<String, OsdBadge>.unmodifiable(styles);
    _schedulePaint();
  }

  /// Mirrors the Lua stage's audio badge naming, including channel suffix.
  String _audioBadgeLabel(String codec, String outFormat) {
    if (codec.isEmpty) return '';
    final String c = codec.toLowerCase();
    final int channels =
        int.tryParse(_player.getProperty('audio-params/channel-count') ?? '') ?? 0;
    final String suffix = switch (channels) { 8 => ' 7.1', 6 => ' 5.1', 2 => ' 2.0', _ => '' };
    if (c.contains('truehd') || c.contains('mlp')) {
      return '${c.contains('atmos') ? 'ATMOS' : 'TRUEHD'}$suffix'.toUpperCase();
    }
    if (c.contains('dts')) {
      final String label = c.contains('x') ? 'DTS:X' : 'DTS';
      return '$label$suffix'.toUpperCase();
    }
    if (c.contains('eac3') || c.contains('dd+')) {
      return '${c.contains('atmos') ? 'DD+ ATMOS' : 'DD+'}$suffix'.toUpperCase();
    }
    if (c.contains('ac3')) return 'DD$suffix';
    return codec.toUpperCase();
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
  /// `seek`, `play`, `back10`, `fwd10` or `menu:<id>`. The rectangles come from
  /// the same list the paint pass uses, so a drawn button is a working button.
  String? actionAt(double nx, double ny) {
    if (!_visible || !ownsChrome || _size.isEmpty) {
      return null;
    }
    final ui.Offset point = ui.Offset(nx * _size.width, ny * _size.height);
    for (final OsdZone zone in OsdChrome.zones(_size)) {
      if (zone.rect.contains(point)) {
        return zone.id;
      }
    }
    return null;
  }

  /// Whether a normalized pointer position lands on the seek strip.
  bool inSeekZone(double nx, double ny) => actionAt(nx, ny) == 'seek';

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
