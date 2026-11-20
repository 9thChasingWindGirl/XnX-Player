import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver;
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../core/input/input_action.dart';
import '../core/input/input_router.dart';
import '../design/ps_tokens.dart';
import '../data/models/media_item.dart';
import '../data/prefs.dart';
import '../data/store.dart';
import '../playback/mpv/capabilities.dart';
import '../playback/mpv/hw_profile.dart';
import '../playback/mpv/mpv_assets.dart';
import '../playback/mpv/mpv_options.dart';
import '../playback/mpv/mpv_player.dart';
import '../playback/mpv/mpv_window.dart';
import 'osd/osd_overlay.dart';
import '../playback/mpv/video_surface.dart';
import '../ui/core/tv_scale.dart';
import 'osd_bridge.dart';
import 'osd_keys.dart';

/// Full-window playback surface.
///
/// The video never touches Flutter: mpv runs with `wid` set to our top-level
/// window, creates its own child window there, and draws with gpu-next/D3D11.
/// [VideoSurface] keeps that child fitted to the client area, because mpv does
/// not follow the parent on resize or fullscreen switches. Flutter only owns the
/// loading, error and diagnostics states plus the keyboard bindings.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.item, this.queue = const <MediaItem>[]});

  final MediaItem item;

  /// Siblings queued behind [item], so `下一集` / `playlist-next` work without a
  /// second navigation. The episode shelf passes the whole season here.
  final List<MediaItem> queue;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  static const int _maxQueue = 30;

  MpvPlayer? _player;
  OsdBridge? _bridge;
  VideoSurface? _surface;

  /// The independent chrome layer. Null off Windows or when creation failed,
  /// in which case the Lua OSD keeps drawing everything as before.
  OsdOverlay? _osd;
  StreamSubscription<bool>? _loadedSub;
  Timer? _watchdog;
  Timer? _escFallback;
  Timer? _health;

  /// Pointer → OSD forwarding. mpv never sees the mouse in this embedding, so
  /// every hover, click, drag and wheel notch has to travel from Flutter to the
  /// Lua OSD as a `mouse` command. Moves are coalesced to one message per
  /// [_mouseInterval]: a 1000Hz mouse would otherwise produce a thousand JSON
  /// commands per second, each triggering a full OSD re-render.
  static const Duration _mouseInterval = Duration(milliseconds: 12);
  final GlobalKey _inputKey = GlobalKey(debugLabel: 'player-input');

  /// This route's place in the input stack; cancelling it on dispose is what
  /// hands the keyboard back to the shell.
  InputSubscription? _input;
  Timer? _mouseTimer;
  Offset? _pendingMouse;

  /// Which rung of the fallback ladder the video path is on. 0 means the first
  /// choice worked; every step down costs quality but saves the picture.
  int _healthStage = 0;
  int _healthTicks = 0;
  String? _healthNote;

  String? _error;
  String? _hint;
  bool _fileLoaded = false;
  bool _showDiagnostics = false;
  /// Window state on entry, so leaving the player does not quietly exit a
  /// fullscreen shell.
  bool _fullScreenAtEntry = false;

  /// Whether mpv accepted the OSD Lua. This is the whole player UI, so it is
  /// worth a line in the diagnostics panel.
  String _scriptNote = '未解析';
  String _logPath = '';

  /// One-line summary of what the runtime probe concluded (decoder, audio
  /// endpoint, HDR output).
  String _capsNote = '尚未探测';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input = InputRouter.instance.subscribe(_onIntent, name: 'player');
    unawaited(_boot());
  }

  /// A resize delivered while the pointer is idle still has to move the OSD
  /// layer and the video child. Polling eventually got there, but until it did
  /// the chrome was painted at the old size — the mismatch in the screenshot.
  @override
  void didChangeMetrics() {
    _surface?.refit();
    _osd?.syncSize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input?.cancel();
    _watchdog?.cancel();
    _escFallback?.cancel();
    _mouseTimer?.cancel();
    _health?.cancel();
    _loadedSub?.cancel();
    _bridge?.dispose();
    _osd?.dispose();
    _player?.lastError.removeListener(_onMpvError);
    // Capture the position while mpv is still alive: resume state is what makes
    // "继续观看" real instead of decorative.
    final MpvViewState? last = _player?.state.value;
    if (last != null && last.duration > 1 && last.position > 1) {
      AppStore.instance.remember(
        widget.item,
        Duration(milliseconds: (last.position * 1000).round()),
        Duration(milliseconds: (last.duration * 1000).round()),
      );
    }
    // Tear mpv down first: destroying the container it renders into while it
    // still owns the surface is asking for a native crash on exit.
    _player?.dispose();
    _surface?.dispose();
    unawaited(_restoreWindow());
    super.dispose();
  }

  Future<void> _setFullScreen(bool value) async {
    try {
      await windowManager.setFullScreen(value);
    } catch (_) {
      // Window manager unavailable (headless/CI): the player still runs.
    }
  }

  Future<void> _restoreWindow() async {
    // Restore what the app looked like on entry instead of always dropping to
    // windowed: the shell may itself be running fullscreen.
    await _setFullScreen(_fullScreenAtEntry);
  }

  /// F11 and the OSD's「全屏」row both land here.
  ///
  /// Flutter owns the real window and mpv only paints into a child of it, so
  /// "fullscreen" is a window-manager state change followed by an immediate
  /// re-fit instead of a resize mpv has to discover on its own.
  Future<void> _toggleFullScreen() async {
    try {
      final bool next = !await windowManager.isFullScreen();
      await windowManager.setFullScreen(next);
    } catch (_) {
      // Window manager unavailable: the picture keeps playing unchanged.
      return;
    }
    _surface?.refit();
    _osd?.syncSize();
    _player?.showUi();
  }

  Future<void> _boot() async {
    try {
      final PlaybackPrefs prefs = AppStore.instance.prefs;
      try {
        _fullScreenAtEntry = await windowManager.isFullScreen();
      } catch (_) {
        // No window manager (headless): leave the window as it is.
      }
      // Fullscreen is opt-in (设置 → 播放 → 进入播放时全屏). Forcing it on every
      // play stranded the user inside a native surface that has no window
      // chrome, with Esc only able to leave the player entirely.
      if (prefs.startFullscreen) {
        await _setFullScreen(true);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      final int? parent = Win32.appWindow();
      if (parent == null) {
        throw StateError('无法获取播放器窗口句柄（FLUTTER_RUNNER_WIN32_WINDOW），视频无处输出。');
      }

      // The container must exist before mpv starts: it is what we hand over as
      // `wid`, and it is the rectangle we own for the rest of the session.
      final VideoSurface surface = VideoSurface(parent, visible: false)..ensureHost();
      _surface = surface;
      final int? host = surface.handle;
      if (host == null) {
        throw StateError('无法创建视频容器窗口（parent=0x${parent.toRadixString(16)}）。');
      }

      final String? scriptPath = await MpvAssets.osdScriptPath();
      // The badge script is optional: when its assets are missing it simply
      // finds no manifest and draws nothing, so a failure here must never stop
      // playback. Both Lua files are unpacked together because the badge script
      // locates its companion through `mp.get_script_directory()`.
      final String? logoScriptPath = await MpvAssets.scriptPath(MpvAssets.logoScript);
      await MpvAssets.scriptPath(MpvAssets.logoBounds);
      final String? logoDir = await MpvAssets.formatLogoDir();
      final String sep = Platform.pathSeparator;

      // Logs belong next to the exe: %TEMP% gets cleaned by disk tools and is
      // impossible to find when someone asks for a log. Falls back to the temp
      // directory only when the install folder is read-only (Program Files).
      final String exeDir = File(Platform.resolvedExecutable).parent.path;
      String logPath = '${Directory.systemTemp.path}${sep}player_mpv.log';
      try {
        final Directory logDir = Directory('$exeDir${sep}log');
        if (!logDir.existsSync()) {
          logDir.createSync(recursive: true);
        }
        logPath = '${logDir.path}${sep}player_mpv.log';
      } catch (_) {
        // Read-only install location; keep the temp path.
      }
      _logPath = logPath;

      // Screenshots land next to the app state rather than in the working
      // directory, which is the build folder during development.
      final String appDir =
          '${Platform.environment['APPDATA'] ?? Directory.systemTemp.path}${sep}XnX Player';
      final String shotDir = '$appDir${sep}screenshots';
      try {
        Directory(shotDir).createSync(recursive: true);
      } catch (_) {
        // Read-only profile: mpv falls back to its own default.
      }

      // Backends may need a round-trip for a playable URL (AList raw link).
      final String url = await AppStore.instance.resolve(widget.item);

      // Queue the sibling episodes. A single unresolvable sibling must not take
      // the whole season down, so only the clicked item is strict.
      final List<String> queue = <String>[url];
      for (final MediaItem sibling in widget.queue) {
        if (queue.length >= _maxQueue) {
          break;
        }
        if (sibling.id == widget.item.id) {
          continue;
        }
        try {
          queue.add(await AppStore.instance.resolve(sibling));
        } catch (_) {
          // Skip it; the playlist simply loses one entry.
        }
      }

      final MpvPlayer player = MpvPlayer();
      // Passthrough/HDR start from what the last probe proved about this
      // machine: a proven bitstream-capable endpoint enables passthrough right
      // away, anything unknown stays off and is re-probed live.
      final HardwareProfile hw = AppStore.instance.hw;
      final AudioPassthrough wantedPassthrough = _settingsFor(prefs).audioPassthrough;
      player.start(
        options: buildMpvOptions(
          wid: host,
          logFile: logPath,
          screenshotDir: shotDir,
          formatLogoDir: logoDir,
          settings: _settingsFor(
            prefs,
            passthroughOverride: initialPassthrough(hw, wantedPassthrough),
            hdrOverride: initialHdrPassthrough(hw, prefs.hdrPassthrough),
          ),
        ),
        logLevel: 'info',
      );
      _player = player;
      player.lastError.addListener(_onMpvError);

      // The OSD is the player UI. `script=` before init fails silently when the
      // path is wrong — the user just gets a picture with no controls — so it
      // is loaded through the command interface and verified against
      // `script-list`. Loading it exactly once, from one code path, also avoids
      // two OSD instances fighting over the same key bindings.
      if (scriptPath == null) {
        _scriptNote = MpvAssets.lastError ?? '脚本路径解析失败';
      } else if (player.loadScript(scriptPath)) {
        _scriptNote = '已加载';
      } else {
        _scriptNote = '加载失败：$scriptPath';
        // mpv finishes setting up scripts asynchronously; look again shortly
        // before reporting a failure the user cannot act on.
        Timer(const Duration(milliseconds: 900), () {
          if (!mounted) {
            return;
          }
          final MpvPlayer? live = _player;
          if (live != null && live.scriptLoaded(MpvAssets.osdScript)) {
            setState(() => _scriptNote = '已加载');
          }
        });
      }

      // Startup format badges. Separate script, separate failure mode: it only
      // paints the light-up logo for a few seconds after each file opens.
      if (logoScriptPath != null) {
        player.loadScript(logoScriptPath);
      }

      surface.start();

      _bridge = OsdBridge(player)
        ..onBack = _close
        ..onTogglePause = player.togglePause
        ..onSeekRequest = player.seekTo
        ..onLoadSubtitle = _loadSubtitle
        ..onFullscreen = _toggleFullScreen
        // Lua answered, so the optimistic Esc handling is not needed. A block
        // body is required: `?.` on a void member cannot be used as a value.
        ..onEvent = (Map<Object?, Object?> _) {
          _escFallback?.cancel();
        }
        ..attach();

      // The chrome moves out of mpv's colour pipeline when the independent
      // layer is available: its pixels are composited by DWM as 8-bit SDR, so
      // HDR passthrough can no longer darken the OSD. The Lua OSD is told
      // which engine owns the bottom band; menus and toasts stay there.
      final OsdOverlay? osd = OsdOverlay.create(player);
      if (osd != null) {
        _osd = osd;
        player.setProperty('user-data/player/osd-engine', 'window');
      }

      _loadedSub = player.onFileLoaded.listen((bool _) {
        if (!mounted) {
          return;
        }
        setState(() => _fileLoaded = true);
        // Reveal only once mpv actually has a frame; before that its child
        // window would just cover the loading state with black.
        _surface?.show();
        _osd
          ?..poke()
          ..startSizeWatch();
        _startHealthWatch();
        _probeCapabilities();
      });

      player.setProperty('volume', '${prefs.volume}');
      if (prefs.subtitleSize > 0) {
        player.setProperty('sub-font-size', '${prefs.subtitleSize}');
      }
      // The OSD reads these before the first frame so the title and the
      // opening-skip preference are already in place at file-loaded.
      player.setProperty('user-data/player/title', widget.item.title);
      player.setProperty('user-data/player/skip-intro', prefs.skipIntro ? 'yes' : 'no');

      final Duration resume = widget.item.resumeAt ?? Duration.zero;
      player.loadQueue(queue, startAt: resume.inSeconds > 5 ? resume : Duration.zero);

      // A silent black screen used to be unactionable; after 12s with no
      // file-loaded event we surface the mpv log instead of waiting forever.
      _watchdog = Timer(const Duration(seconds: 12), () {
        if (!mounted || _fileLoaded) {
          return;
        }
        // Nothing decoded, so the surface is either hidden or black; drop it
        // anyway so the panel below cannot be covered by an opaque container.
        _surface?.hide();
        setState(() {
          _showDiagnostics = true;
          _hint = '12 秒内未收到 mpv 的 file-loaded 事件，已显示诊断信息。';
        });
      });

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _showDiagnostics = true;
        });
      }
    }
  }

  void _onMpvError() {
    final String? message = _player?.lastError.value;
    if (message == null || !mounted) {
      return;
    }
    _surface?.hide();
    setState(() {
      _error = message;
      _showDiagnostics = true;
    });
  }

  /// Watches whether mpv actually puts frames on screen, and walks down a
  /// fallback ladder if it does not.
  ///
  /// A 4K HDR10 file can log a perfectly healthy
  /// `VO: [gpu-next] 3840x2160 d3d11[p010]` and still show nothing, because the
  /// frame never reaches the screen. There are only a few ways that happens and
  /// each has a cheap, reversible fix — so instead of guessing, try them in
  /// order of least damage and stop as soon as a frame is presented:
  ///
  /// 1. `video-sync=display-resample` without a working audio output. That mode
  ///    derives its clock from the audio device; when the AO is dead the first
  ///    frame sits there forever, which looks exactly like a black screen.
  /// 2. Hardware decoding (d3d11va) failing to map a 10-bit surface.
  /// 3. gpu-next with HDR passthrough on a display that cannot take it.
  ///
  /// Anything healthy exits on the first tick, so a working file pays nothing.
  void _startHealthWatch() {
    _health?.cancel();
    _healthStage = 0;
    _healthTicks = 0;
    _healthNote = null;
    _health = Timer.periodic(const Duration(milliseconds: 1200), (Timer timer) {
      final MpvPlayer? player = _player;
      if (!mounted || player == null || _error != null) {
        timer.cancel();
        _health = null;
        return;
      }
      // Paused means "no new frames" is the expected state, not a fault.
      if (player.getPropertyFlag('paused')) {
        return;
      }
      // Audio-only files have no VO at all; the ladder would be pure noise.
      if (player.getProperty('video') == 'no') {
        timer.cancel();
        _health = null;
        return;
      }
      final String? configuredRaw = player.getProperty('vo-configured');
      final String? fpsRaw = player.getProperty('estimated-vf-fps');
      if (configuredRaw == null && fpsRaw == null) {
        // Neither probe exists in this libmpv build: escalate on nothing and we
        // would wreck a perfectly good picture. Leave it alone.
        timer.cancel();
        _health = null;
        return;
      }
      // `vo-configured` means the VO has a frame size, `estimated-vf-fps` means
      // frames are actually being presented. A configured-but-zero-fps VO is
      // precisely the black-screen case, so both must agree.
      final bool configured = configuredRaw == 'yes';
      final double fps = double.tryParse(fpsRaw ?? '') ?? 0;
      if (configured && (fpsRaw == null || fps > 0.01)) {
        timer.cancel();
        _health = null;
        // Only repaint when a rung was actually used.
        if (_healthStage > 0 && mounted) {
          setState(() {});
        }
        return;
      }

      // No audio device means display-resample can never get a clock, and that
      // check is instant, so it does not wait for the grace period.
      final String sync = player.getProperty('video-sync') ?? 'audio';
      final String? ao = player.getProperty('ao');
      final bool noAudio = ao == null || ao.isEmpty || ao == 'null';
      if (_healthStage == 0 && noAudio) {
        // A dead AO also means bitstream passthrough was refused (exclusive
        // mode), which is the only thing that can take out every audio device
        // at once. Clearing it lets mpv retry with a plain shared-mode device,
        // and this can never hurt a working setup because the AO is already
        // gone at this point.
        player.setProperty('audio-spdif', '');
        if (sync == 'display-resample') {
          player.setProperty('video-sync', 'audio');
        }
        // Remember it: the next launch should not pay the same 2s of silence
        // while the audio device refuses passthrough again.
        final PlaybackPrefs now = AppStore.instance.prefs;
        if (now.passthrough != PassthroughPref.off) {
          unawaited(AppStore.instance.updatePrefs(now.copyWith(passthrough: PassthroughPref.off)));
        }
        _healthStage = 1;
        _healthTicks = 0;
        _healthNote = '没有可用的音频输出：已关闭音频直通，同步基准改用音频时钟';
        if (mounted) {
          setState(() {});
        }
        return;
      }

      // Roughly 3.6s per rung: long enough for a 4K file to spin up.
      if (++_healthTicks < 3) {
        return;
      }
      _healthTicks = 0;

      if (_healthStage == 0) {
        player.setProperty('video-sync', 'audio');
        _healthStage = 1;
        _healthNote = '画面没有出现，已从 display-resample 切到音频时钟';
      } else if (_healthStage == 1) {
        player.setProperty('hwdec', 'no');
        // A GPU that cannot map 10-bit surfaces will fail the same way on every
        // launch, so record the answer instead of rediscovering it each time.
        final PlaybackPrefs now = AppStore.instance.prefs;
        if (now.hardwareDecoding) {
          unawaited(AppStore.instance.updatePrefs(now.copyWith(hardwareDecoding: false)));
        }
        _healthStage = 2;
        _healthNote = '画面仍未出现，已关闭硬件解码，改用软件解码';
      } else if (_healthStage == 2) {
        // Last rung: the HDR path is the remaining suspect, so turn both the
        // hint and the VO down to the most compatible combination. Dolby Vision
        // is the exception: plain `gpu` cannot apply the RPU and renders it as
        // green/purple, which is worse than whatever we are fixing.
        player.setProperty('target-colorspace-hint', 'no');
        final bool dolbyVision =
            dolbyVisionNeedsGpuNext(player.getProperty('video-params/primaries'));
        if (!dolbyVision) {
          player.setProperty('vo', 'gpu');
        }
        _healthStage = 3;
        _healthNote = dolbyVision
            ? '画面仍未出现，已关闭 HDR 直通（杜比视界片源保留 gpu-next）'
            : '画面仍未出现，已关闭 HDR 直通并退回 gpu VO';
      } else {
        timer.cancel();
        _health = null;
        if (mounted) {
          setState(() {
            _showDiagnostics = true;
            _hint = '三级回退都没有出画面。按 F1 打开诊断，点「复制日志」把内容发我。';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// One line for the diagnostics panel: which rung we are on and why.
  String get _healthText {
    if (_healthStage == 0) {
      return _healthNote ?? '首选项（gpu-next · 硬解 · HDR 直通）';
    }
    return '第 $_healthStage 级回退 · ${_healthNote ?? ''}';
  }

  /// Asks the live player what it actually settled on, instead of trusting what
  /// we asked for.
  ///
  /// Every one of these can silently end up as something else: hardware
  /// decoding falls back to software, HDR gets tone mapped into SDR, bitstream
  /// passthrough gets refused. Reading the result back is the only way to tell
  /// the user (or ourselves) the truth, and it is what makes the defaults safe
  /// to keep neutral.
  void _probeCapabilities() {
    final MpvPlayer? player = _player;
    if (player == null) {
      return;
    }
    final String hwdec = describeHwdec(
      player.getProperty('hwdec-current'),
      player.getProperty('hwdec'),
    );
    final String? outPrim = player.getProperty('video-out-params/primaries');
    final String? outGamma = player.getProperty('video-out-params/gamma');
    final String? srcPrim = player.getProperty('video-params/primaries');
    final String? srcGamma = player.getProperty('video-params/gamma');
    final bool dolbyVision = dolbyVisionNeedsGpuNext(srcPrim);
    final bool hdrSource = isHdrSource(srcGamma) || dolbyVision;
    final bool hdrOutput = isHdrOutput(outPrim, outGamma);

    final StringBuffer caps = StringBuffer();
    caps.write(hwdec);
    if (hdrSource) {
      caps.write(dolbyVision ? ' · 杜比视界片源' : ' · HDR 片源');
      caps.write(hdrOutput ? ' → HDR 直通' : ' → 映射到 SDR');
    } else {
      caps.write(' · SDR');
    }
    final String? audioFormat = player.getProperty('audio-out-params/format');
    if (audioFormat != null) {
      caps.write(' · 音频 $audioFormat');
    }
    _capsNote = caps.toString();

    // Passthrough is opt-in, and even when asked for it is only kept if the
    // endpoint accepted the bitstream. Checking after the fact is the only
    // honest test: a device that refuses takes the whole audio output with it.
    final AudioPassthrough wanted = _settingsFor(AppStore.instance.prefs).audioPassthrough;
    final String? deviceName = player.getProperty('audio-device-name');
    if (wanted == AudioPassthrough.off) {
      // Nothing to verify live, but the endpoints are still worth recording so
      // the next start can decide from facts instead of probing blind again.
      _saveHwProfile(deviceName, passthroughRequested: false, passthroughLive: false, hdrOutput: hdrOutput);
      return;
    }
    // mpv is up now, so the endpoint is knowable: only request passthrough on
    // devices that look like they can take a bitstream (HDMI/SPDIF into an
    // AVR). Starting blind is what made WASAPI exclusive mode fail and drag
    // the whole audio chain down on ordinary speaker endpoints.
    if (!deviceSupportsBitstream(deviceName)) {
      player.setProperty('audio-spdif', '');
      _saveHwProfile(deviceName, passthroughRequested: false, passthroughLive: false, hdrOutput: hdrOutput);
      setState(() {
        _capsNote = '$_capsNote · 音频端点非 HDMI/SPDIF 类，未启用直通';
      });
      return;
    }
    player.setProperty('audio-spdif', audioSpdifValue(wanted));
    Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      final MpvPlayer? live = _player;
      if (live == null) {
        return;
      }
      final String? format = live.getProperty('audio-out-params/format');
      final String? ao = live.getProperty('ao');
      final bool passthroughLive = isBitstreamFormat(format);
      // The format read-back is ground truth: persist what this endpoint
      // actually did so the next start starts from evidence.
      _saveHwProfile(deviceName, passthroughRequested: true, passthroughLive: passthroughLive, hdrOutput: hdrOutput);
      if (ao == null || ao.isEmpty || ao == 'null' || !passthroughLive) {
        live.setProperty('audio-spdif', '');
        setState(() {
          _capsNote = '$_capsNote · 直通被设备拒绝，已回退解码';
        });
      } else {
        setState(() {
          _capsNote = '$_capsNote · 直通生效';
        });
      }
    });
  }

  /// Persists the capability probe's answer about this machine.
  void _saveHwProfile(String? deviceName, {required bool passthroughRequested, required bool passthroughLive, required bool hdrOutput}) {
    unawaited(
      AppStore.instance.updateHwProfile(
        profileFromProbe(
          audioDeviceName: deviceName,
          passthroughRequested: passthroughRequested,
          passthroughLive: passthroughLive,
          hdrOutput: hdrOutput,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  /// Opens a file dialog for an external subtitle and hands it to mpv.
  ///
  /// The OSD lives inside mpv and cannot show a dialog, so it asks Flutter to
  /// do it (`{"type":"subtitle"}`); the picked file goes straight to `sub-add`.
  Future<void> _loadSubtitle() async {
    final MpvPlayer? player = _player;
    if (player == null) {
      return;
    }
    try {
      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[
          const XTypeGroup(
            label: '字幕',
            extensions: <String>['srt', 'ass', 'ssa', 'vtt', 'sub', 'sup', 'idx', 'smi'],
          ),
        ],
      );
      if (file == null) {
        return;
      }
      player.command(<String>['sub-add', file.path, 'select']);
      player.showUi();
    } catch (_) {
      // Dialog unavailable (headless): keep playing.
    }
  }

  void _close() {
    _escFallback?.cancel();
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  /// Maps the persisted preferences onto mpv options.
  ///
  /// `passthroughOverride` exists because bitstream passthrough must never be
  /// part of the initial option table unless the hardware profile proves the
  /// endpoint accepts a bitstream: at that point mpv has no audio device yet,
  /// so requesting it is a blind bet that WASAPI exclusive mode succeeds.
  /// `hdrOverride` works the same way for displays the probe saw as SDR-only.
  MpvSettings _settingsFor(PlaybackPrefs prefs, {AudioPassthrough? passthroughOverride, bool? hdrOverride}) {
    return MpvSettings(
      quality: switch (prefs.quality) {
        QualityPref.fast => VideoQuality.fast,
        QualityPref.balanced => VideoQuality.balanced,
        QualityPref.high => VideoQuality.high,
      },
      hwdec: prefs.hardwareDecoding ? 'auto-safe' : 'no',
      hdrPassthrough: hdrOverride ?? prefs.hdrPassthrough,
      smoothMotion: prefs.smoothMotion,
      audioPassthrough: passthroughOverride ?? switch (prefs.passthrough) {
        PassthroughPref.all => AudioPassthrough.all,
        PassthroughPref.dolby => AudioPassthrough.dolby,
        PassthroughPref.dts => AudioPassthrough.dts,
        PassthroughPref.off => AudioPassthrough.off,
      },
      deband: prefs.deband,
      volume: prefs.volume,
    );
  }

  /// A route on top of the shell sees every intent first.
  ///
  /// Keyboard events keep their original identity: the OSD has a far larger
  /// keymap than our action vocabulary (`[`, `]`, digits, `alt+n`), so mapping
  /// keys to actions and back would silently drop most of it. A pad has no keys
  /// at all, which is what the other branch is for.
  bool _onIntent(InputIntent intent) {
    final KeyEvent? event = intent.key;
    if (event != null) {
      return _onKeyEvent(event);
    }
    return _onPadIntent(intent);
  }

  /// The direction keys repeat because the OS repeats them; nothing is
  /// synthesized here. Only seek and volume keys are in the list — holding `s`
  /// must not spool a hundred screenshots.
  static final Set<int> _repeatingKeys = <int>{
    LogicalKeyboardKey.arrowLeft.keyId,
    LogicalKeyboardKey.arrowRight.keyId,
    LogicalKeyboardKey.arrowUp.keyId,
    LogicalKeyboardKey.arrowDown.keyId,
  };

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) {
      return false;
    }
    final bool repeat = event is KeyRepeatEvent;
    final LogicalKeyboardKey key = event.logicalKey;

    if (repeat && !_repeatingKeys.contains(key.keyId)) {
      return false;
    }

    if (key == LogicalKeyboardKey.f1 && !repeat) {
      final bool open = !_showDiagnostics;
      setState(() => _showDiagnostics = open);
      // The video container is a native child window: it always paints above
      // the Flutter layer. Leaving it up would hide the panel behind opaque
      // video, which is exactly how "F1 does nothing" looks to the user.
      if (open) {
        _surface?.hide();
      } else if (_fileLoaded) {
        _surface?.show();
      }
      return true;
    }

    final MpvPlayer? player = _player;
    if (player == null || _error != null) {
      // Nothing to forward to: keep the player escapable.
      if (key == LogicalKeyboardKey.escape) {
        _close();
        return true;
      }
      return false;
    }

    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    // Ctrl combinations belong to the app shell (Ctrl+F, Ctrl+O...).
    if (keyboard.isControlPressed) {
      return false;
    }

    final String? composed = OsdKeys.compose(
      key,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
    );
    if (composed == null) {
      return false;
    }

    if (key == LogicalKeyboardKey.escape) {
      _armEscFallback();
    }

    player.sendKey(composed);
    return true;
  }

  /// If the OSD never answers, the user must not be trapped in a fullscreen
  /// native surface with no way back.
  void _armEscFallback() {
    _escFallback?.cancel();
    _escFallback = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        _close();
      }
    });
  }

  /// A pad produces actions, not keys. Only the overlap between the two
  /// vocabularies can be served, and [OsdKeys.nameForAction] owns that table.
  bool _onPadIntent(InputIntent intent) {
    final InputAction? action = intent.action;
    if (action == null) {
      return false;
    }
    final MpvPlayer? player = _player;
    if (player == null || _error != null) {
      // Nothing to forward to: keep the route escapable.
      if (action == InputAction.back) {
        _close();
        return true;
      }
      return false;
    }
    final String? name = OsdKeys.nameForAction(action);
    if (name == null) {
      return false;
    }
    if (action == InputAction.back) {
      _armEscFallback();
    }
    // Any control activity brings the chrome up, whichever engine is drawing.
    _osd?.poke();
    player.sendKey(name);
    return true;
  }

  // ---- Pointer forwarding -------------------------------------------------
  //
  // The OSD draws its own controls, but mpv cannot receive a single mouse event
  // here: the picture is a native child window and Windows delivers the
  // messages to the Flutter view. So Flutter is the only place that knows where
  // the pointer is, and it sends normalized coordinates to the Lua side.

  /// Win32's MK_RBUTTON bit. Spelled out so the file does not depend on which
  /// gesture constants the UI package re-exports.
  static const int _secondaryButton = 0x02;

  /// Which button started the current press. Needed on release: by then
  /// `PointerUpEvent.buttons` is already 0 and the button is unrecoverable.
  String? _pressedButton;

  /// Normalized (0..1) pointer position inside the player, or null when the
  /// widget has not been laid out yet.
  ///
  /// `BuildContext.size` rather than a `RenderBox` cast: the page might be
  /// driven by a different Material package than the one this file imports, and
  /// naming the render type would tie the two together for no benefit.
  Offset? _normalized(Offset local) {
    // Test the pointer against the layer's *current* rectangle. A resize can
    // land between Flutter's layout and the next size poll; syncing here makes
    // the hit test and the painted chrome agree at the moment of the event.
    _osd?.syncSize();
    final Size? size = _inputKey.currentContext?.size;
    if (size == null || size.isEmpty) {
      return null;
    }
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0).toDouble(),
      (local.dy / size.height).clamp(0.0, 1.0).toDouble(),
    );
  }

  /// Queues a move, coalescing bursts into one message per [_mouseInterval].
  void _queueMove(Offset local) {
    final Offset? unit = _normalized(local);
    if (unit == null) {
      return;
    }
    _pendingMouse = unit;
    if (_mouseTimer?.isActive ?? false) {
      return;
    }
    _flushMove();
    _mouseTimer = Timer(_mouseInterval, _flushMove);
  }

  void _flushMove() {
    final Offset? unit = _pendingMouse;
    _pendingMouse = null;
    if (unit == null) {
      return;
    }
    InputRouter.instance.notePointer();
    final OsdOverlay? osd = _osd;
    if (osd != null) {
      osd
        ..poke()
        ..setSeekHover(osd.inSeekZone(unit.dx, unit.dy));
    }
    _player?.sendMouse(ev: 'move', nx: unit.dx, ny: unit.dy);
  }

  /// Press or release. The move goes first: the OSD resolves the click against
  /// the pointer position it has stored, so a click somewhere new would
  /// otherwise be judged against wherever the pointer was last seen.
  void _forwardButton(PointerEvent event, {required bool down}) {
    final Offset? unit = _normalized(event.localPosition);
    final MpvPlayer? player = _player;
    if (unit == null || player == null) {
      return;
    }
    InputRouter.instance.notePointer();
    final OsdOverlay? osd = _osd;
    if (osd != null && osd.inSeekZone(unit.dx, unit.dy)) {
      // The chrome owns this press: scrub locally, seek once on release, and
      // never let the Lua side act on a pointer the bar has already claimed.
      if (down) {
        osd
          ..poke()
          ..scrub(unit.dx);
      } else {
        osd.endScrub();
      }
      _pendingMouse = null;
      return;
    }
    _pendingMouse = null;
    player.sendMouse(ev: 'move', nx: unit.dx, ny: unit.dy);
    player.sendMouse(
      ev: down ? 'down' : 'up',
      nx: unit.dx,
      ny: unit.dy,
      button: _pressedButton ?? 'left',
    );
  }

  void _forwardScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final Offset? unit = _normalized(event.localPosition);
    final double dy = event.scrollDelta.dy;
    if (unit == null || dy == 0) {
      return;
    }
    final OsdOverlay? osd = _osd;
    if (osd != null && osd.inChromeZone(unit.dx, unit.dy)) {
      // Over the chrome band the wheel is the volume, handled locally.
      osd
        ..poke()
        ..adjustVolume(dy < 0 ? 5 : -5);
      return;
    }
    // One notch per message regardless of the platform's scroll step; the Lua
    // side decides whether a notch means ±5% volume or a menu row.
    _player?.sendMouse(ev: 'wheel', nx: unit.dx, ny: unit.dy, delta: dy < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final MpvPlayer? player = _player;
    final bool showVideoState = _error != null || !_fileLoaded;

    // The listener sits *outside* TvScale on purpose: its localPosition is
    // then in the window's real logical space, which maps proportionally onto
    // the Win32 client area the independent OSD layer paints in. Inside
    // TvScale the coordinates were design-space units whose scale changed on
    // every resize, so a resized window mapped the pointer onto stale chrome.
    return Listener(
      key: _inputKey,
      // Opaque: the picture is a native window underneath, so Flutter only
      // receives pointer events because this subtree claims them. A
      // transparent listener would let every click fall through to nothing.
      behavior: HitTestBehavior.opaque,
      onPointerHover: (PointerHoverEvent event) => _queueMove(event.localPosition),
      onPointerMove: (PointerMoveEvent event) => _queueMove(event.localPosition),
      onPointerDown: (PointerDownEvent event) {
        _pressedButton =
            (event.buttons & _secondaryButton) != 0 ? 'right' : 'left';
        _forwardButton(event, down: true);
      },
      onPointerUp: (PointerUpEvent event) {
        _forwardButton(event, down: false);
        _pressedButton = null;
      },
      onPointerCancel: (PointerCancelEvent event) {
        _forwardButton(event, down: false);
        _pressedButton = null;
      },
      onPointerSignal: _forwardScroll,
      child: TvScale(
        child: Scaffold(
          backgroundColor: const Color(0xFF000000),
          body: MouseRegion(
            // mpv is told not to touch the cursor (`cursor-autohide=no`,
            // `input-cursor=no`); the pointer the user sees is this one.
            cursor: SystemMouseCursors.basic,
            child: Stack(
              children: <Widget>[
                if (_error != null)
                  Positioned.fill(child: _ErrorPanel(message: _error!, hint: _hint, onBack: _close))
                else if (showVideoState)
                  Positioned.fill(child: _LoadingPanel(title: widget.item.title, hint: _hint)),
                if (_showDiagnostics && player != null)
                  Positioned(
                    left: PsSpace.safeX,
                    right: PsSpace.safeX,
                    bottom: PsSpace.lg,
                    child: _DiagnosticsPanel(
                      logPath: _logPath,
                      lines: player.logs,
                      surfaceInfo: _surface?.diagnostics ?? '未枚举到子窗口',
                      health: _healthText,
                      scriptNote: _scriptNote,
                      capsNote: _capsNote,
                      facts: <String>[
                        'vo=${player.getProperty('vo') ?? '—'}'
                            ' 已配置=${player.getProperty('vo-configured') ?? '—'}'
                            ' 实测帧率=${player.getProperty('estimated-vf-fps') ?? '—'}',
                        '解码=${player.getProperty('hwdec-current') ?? '—'}'
                            ' 同步=${player.getProperty('video-sync') ?? '—'}'
                            ' 音频=${player.getProperty('ao') ?? '无'}',
                        '画质=${player.getProperty('video-params/pixelformat') ?? '—'}'
                            ' 色域=${player.getProperty('video-params/primaries') ?? '—'}'
                            ' 峰值=${player.getProperty('target-peak') ?? '—'}',
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(PsColor.text),
              ),
            ),
            const SizedBox(height: PsSpace.lg),
            Text(title, style: PsType.card, textAlign: TextAlign.center),
            const SizedBox(height: PsSpace.xs),
            const Text('正在打开媒体…', style: PsType.micro),
            if (hint != null) ...<Widget>[
              const SizedBox(height: PsSpace.md),
              Text(hint!, style: PsType.micro.copyWith(color: PsColor.danger), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onBack, this.hint});

  final String message;
  final String? hint;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 240),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, size: 56, color: PsColor.danger),
            const SizedBox(height: PsSpace.lg),
            const Text('无法播放', style: PsType.page),
            const SizedBox(height: PsSpace.md),
            Text(message, style: PsType.body),
            if (hint != null) ...<Widget>[
              const SizedBox(height: PsSpace.sm),
              Text(hint!, style: PsType.micro),
            ],
            const SizedBox(height: PsSpace.xl),
            GestureDetector(
              onTap: onBack,
              child: const Text('按 Esc 返回', style: PsType.micro),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet style dump of the mpv log and window discovery result.
///
/// This exists because a native child window cannot be inspected from Flutter:
/// when video does not appear, the only truth is mpv's own log. The copy button
/// exists because that log is long, lives in %TEMP%, and every black-screen
/// report so far needed its tail verbatim.
class _DiagnosticsPanel extends StatefulWidget {
  const _DiagnosticsPanel({
    required this.logPath,
    required this.lines,
    required this.surfaceInfo,
    required this.health,
    required this.scriptNote,
    required this.capsNote,
    required this.facts,
  });

  final String logPath;
  final List<String> lines;
  final String surfaceInfo;
  final String health;
  final String scriptNote;
  final String capsNote;
  final List<String> facts;

  @override
  State<_DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends State<_DiagnosticsPanel> {
  bool _copied = false;

  Future<void> _copy() async {
    // The in-memory ring buffer is the fallback: it is always populated, while
    // the file only exists when mpv managed to open its log.
    String text = widget.lines.join('\n');
    try {
      final File file = File(widget.logPath);
      if (file.existsSync()) {
        final String full = await file.readAsString();
        if (full.trim().isNotEmpty) {
          text = full;
        }
      }
    } catch (_) {
      // Keep the ring buffer version.
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> tail =
        widget.lines.length > 14 ? widget.lines.sublist(widget.lines.length - 14) : widget.lines;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE60E1018),
        borderRadius: BorderRadius.circular(PsRadius.card),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(PsSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '诊断信息 · F1 开关',
                    style: PsType.micro.copyWith(letterSpacing: 1.2, color: PsColor.text),
                  ),
                ),
                GestureDetector(
                  onTap: _copy,
                  child: Text(
                    _copied ? '已复制' : '复制日志',
                    style: PsType.micro.copyWith(color: PsColor.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: PsSpace.xs),
            Text('画面：${widget.health}', style: _mono.copyWith(color: PsColor.text)),
            Text('控件：${widget.scriptNote}', style: _mono.copyWith(color: PsColor.text)),
            Text('能力：${widget.capsNote}', style: _mono.copyWith(color: PsColor.textDim)),
            Text('子窗口：${widget.surfaceInfo}', style: _mono.copyWith(color: PsColor.textDim)),
            for (final String fact in widget.facts)
              Text(fact, style: _mono.copyWith(color: PsColor.textDim)),
            Text('日志：${widget.logPath}', style: _mono.copyWith(color: PsColor.textDim)),
            const SizedBox(height: PsSpace.xs),
            if (tail.isEmpty)
              Text('（mpv 尚未输出日志）', style: _mono.copyWith(color: PsColor.textDim))
            else
              for (final String line in tail)
                Text(line, style: _mono, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  static final TextStyle _mono = PsType.micro.copyWith(
    fontFamily: 'Consolas',
    fontSize: 14,
    height: 1.5,
    color: PsColor.textDim,
  );
}
