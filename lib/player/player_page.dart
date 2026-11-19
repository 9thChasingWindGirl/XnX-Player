import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../design/ps_tokens.dart';
import '../playback/mpv/mpv_assets.dart';
import '../playback/mpv/mpv_options.dart';
import '../playback/mpv/mpv_player.dart';
import '../playback/mpv/mpv_window.dart';
import '../ui/core/tv_scale.dart';
import 'osd_bridge.dart';

/// Full-window playback surface.
///
/// The video itself never touches Flutter: mpv renders into a child window of
/// this top-level window, and the in-player UI is drawn by the Lua OSD on top
/// of the video. Flutter only owns the loading and error states here.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.path, required this.title});

  final String path;
  final String title;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  MpvPlayer? _player;
  OsdBridge? _bridge;
  StreamSubscription<bool>? _loadedSub;
  String? _error;
  bool _fileLoaded = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(_boot());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _loadedSub?.cancel();
    _bridge?.dispose();
    _player?.dispose();
    unawaited(_restoreWindow());
    super.dispose();
  }

  Future<void> _restoreWindow() async {
    try {
      await windowManager.setFullScreen(false);
    } catch (_) {
      // Window manager unavailable (headless/CI): nothing to restore.
    }
  }

  Future<void> _boot() async {
    try {
      final String? scriptPath = await MpvAssets.osdScriptPath();
      final int? wid = appWindowHandle();

      final MpvPlayer player = MpvPlayer();
      player.start(
        options: buildMpvOptions(
          osdScriptPath: scriptPath ?? '',
          wid: wid,
        ),
      );
      _player = player;

      _bridge = OsdBridge(player)
        ..onBack = _close
        ..onTogglePause = player.togglePause
        ..onSeekRequest = player.seekTo
        ..attach();

      _loadedSub = player.onFileLoaded.listen((bool _) {
        if (mounted) {
          setState(() => _fileLoaded = true);
        }
      });

      player.load(widget.path);
      player.setProperty('user-data/xnx/title', widget.title);

      try {
        await windowManager.setFullScreen(true);
      } catch (_) {
        // Non-fatal: the player still works windowed.
      }

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  void _close() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final MpvPlayer? player = _player;

    if (key == LogicalKeyboardKey.escape) {
      _close();
      return true;
    }
    if (player == null) {
      return false;
    }
    if (key == LogicalKeyboardKey.space) {
      player.togglePause();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      player.seekBy(10);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      player.seekBy(-10);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return TvScale(
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Stack(
          children: <Widget>[
            if (_error != null)
              Positioned.fill(child: _ErrorPanel(message: _error!))
            else if (!_fileLoaded)
              Positioned.fill(child: _LoadingPanel(title: widget.title)),
          ],
        ),
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.title});

  final String title;

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
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

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
            const SizedBox(height: PsSpace.xl),
            const Text('按 Esc 返回', style: PsType.micro),
          ],
        ),
      ),
    );
  }
}
