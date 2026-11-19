import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../design/ps_tokens.dart';
import '../data/models/media_item.dart';
import '../data/prefs.dart';
import '../data/store.dart';
import '../playback/mpv/mpv_assets.dart';
import '../playback/mpv/mpv_options.dart';
import '../playback/mpv/mpv_player.dart';
import '../playback/mpv/mpv_window.dart';
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

class _PlayerPageState extends State<PlayerPage> {
  static const int _maxQueue = 30;

  MpvPlayer? _player;
  OsdBridge? _bridge;
  VideoSurface? _surface;
  StreamSubscription<bool>? _loadedSub;
  Timer? _watchdog;
  Timer? _escFallback;

  String? _error;
  String? _hint;
  bool _fileLoaded = false;
  bool _showDiagnostics = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(_boot());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _watchdog?.cancel();
    _escFallback?.cancel();
    _loadedSub?.cancel();
    _bridge?.dispose();
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
    await _setFullScreen(false);
  }

  Future<void> _boot() async {
    try {
      // Fullscreen must happen *before* mpv creates its window: mpv sizes the
      // child from the parent's client rect once, at creation time. Going
      // fullscreen afterwards leaves the video stuck at the windowed size,
      // which reads as "black screen with a small picture" or just black.
      await _setFullScreen(true);
      await Future<void>.delayed(const Duration(milliseconds: 200));

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
      final String sep = Platform.pathSeparator;
      final String logPath = '${Directory.systemTemp.path}${sep}xnx_player_mpv.log';

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

      final PlaybackPrefs prefs = AppStore.instance.prefs;

      final MpvPlayer player = MpvPlayer();
      player.start(
        options: buildMpvOptions(
          osdScriptPath: scriptPath ?? '',
          wid: host,
          logFile: logPath,
          screenshotDir: shotDir,
          settings: _settingsFor(prefs),
        ),
        logLevel: 'info',
      );
      _player = player;
      player.lastError.addListener(_onMpvError);

      surface.start();

      _bridge = OsdBridge(player)
        ..onBack = _close
        ..onTogglePause = player.togglePause
        ..onSeekRequest = player.seekTo
        ..onLoadSubtitle = _loadSubtitle
        ..onEvent = (Map<Object?, Object?> _) => _escFallback?.cancel()
        ..attach();

      _loadedSub = player.onFileLoaded.listen((bool _) {
        if (!mounted) {
          return;
        }
        setState(() => _fileLoaded = true);
        // Reveal only once mpv actually has a frame; before that its child
        // window would just cover the loading state with black.
        _surface?.show();
      });

      player.setProperty('volume', '${prefs.volume}');
      if (prefs.subtitleSize > 0) {
        player.setProperty('sub-font-size', '${prefs.subtitleSize}');
      }
      // The OSD reads these before the first frame so the title and the
      // opening-skip preference are already in place at file-loaded.
      player.setProperty('user-data/xnx/title', widget.item.title);
      player.setProperty('user-data/xnx/skip-intro', prefs.skipIntro ? 'yes' : 'no');

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
  MpvSettings _settingsFor(PlaybackPrefs prefs) {
    return MpvSettings(
      quality: switch (prefs.quality) {
        QualityPref.fast => VideoQuality.fast,
        QualityPref.balanced => VideoQuality.balanced,
        QualityPref.high => VideoQuality.high,
      },
      hwdec: prefs.hardwareDecoding ? 'auto-safe' : 'no',
      hdrPassthrough: prefs.hdrPassthrough,
      smoothMotion: prefs.smoothMotion,
      audioPassthrough: switch (prefs.passthrough) {
        PassthroughPref.all => AudioPassthrough.all,
        PassthroughPref.dolby => AudioPassthrough.dolby,
        PassthroughPref.dts => AudioPassthrough.dts,
        PassthroughPref.off => AudioPassthrough.off,
      },
      deband: prefs.deband,
      volume: prefs.volume,
    );
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.f1) {
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

    // Escape has a fallback: if the OSD never answers, the user must not be
    // trapped in a fullscreen native surface.
    if (key == LogicalKeyboardKey.escape) {
      _escFallback?.cancel();
      _escFallback = Timer(const Duration(milliseconds: 450), () {
        if (mounted) {
          _close();
        }
      });
    }

    player.sendKey(composed);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final MpvPlayer? player = _player;
    final bool showVideoState = _error != null || !_fileLoaded;

    return TvScale(
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Stack(
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
                  logPath: '${Directory.systemTemp.path}${Platform.pathSeparator}xnx_player_mpv.log',
                  lines: player.logs,
                  surfaceInfo: _surface?.diagnostics ?? '未枚举到子窗口',
                ),
              ),
          ],
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
/// when video does not appear, the only truth is mpv's own log.
class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({
    required this.logPath,
    required this.lines,
    required this.surfaceInfo,
  });

  final String logPath;
  final List<String> lines;
  final String surfaceInfo;

  @override
  Widget build(BuildContext context) {
    final List<String> tail = lines.length > 14 ? lines.sublist(lines.length - 14) : lines;
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
            Text(
              '诊断信息 · F1 开关',
              style: PsType.micro.copyWith(letterSpacing: 1.2, color: PsColor.text),
            ),
            const SizedBox(height: PsSpace.xs),
            Text('子窗口：$surfaceInfo', style: _mono.copyWith(color: PsColor.textDim)),
            Text('日志：$logPath', style: _mono.copyWith(color: PsColor.textDim)),
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
