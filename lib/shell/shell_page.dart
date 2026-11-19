import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';
import '../data/models/media_item.dart';
import '../design/ps_tokens.dart';
import '../player/player_page.dart';
import '../ui/core/focus_navigator.dart';
import '../ui/core/tv_scale.dart';
import 'control_center.dart';
import 'control_center_items.dart';
import 'top_status_bar.dart';
import '../pages/home/home_page.dart';
import '../pages/media/media_page.dart';

/// Root screen: pages behind, chrome on top, Control Center as an overlay.
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _tab = 0;
  final Set<int> _visited = <int>{0};
  bool _ccOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.tab) {
      setState(() => _ccOpen = !_ccOpen);
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_ccOpen) {
        setState(() => _ccOpen = false);
        return true;
      }
      return false;
    }
    if (key == LogicalKeyboardKey.f1) {
      _openFile();
      return true;
    }

    final NavDir? dir = _dirFor(key);
    if (dir != null) {
      FocusNavigator.move(dir);
      return true;
    }
    return false;
  }

  NavDir? _dirFor(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) {
      return NavDir.up;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return NavDir.down;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return NavDir.left;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return NavDir.right;
    }
    return null;
  }

  void _selectTab(int index) {
    if (index == _tab) {
      return;
    }
    setState(() {
      _tab = index;
      _visited.add(index);
      _ccOpen = false;
    });
  }

  void _onCcSelect(CcItem item) {
    switch (item.id) {
      case 'home':
        setState(() {
          _ccOpen = false;
          _tab = 0;
          _visited.add(0);
        });
        break;
      default:
        setState(() => _ccOpen = false);
        break;
    }
  }

  Future<void> _play(MediaItem item) async {
    if (item.path == null || item.path == 'open' || item.path == 'demo') {
      await _openFile();
      return;
    }
    await _pushPlayer(item.path!, item.title);
  }

  Future<void> _openFile() async {
    try {
      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[
          const XTypeGroup(
            label: '视频',
            extensions: <String>['mkv', 'mp4', 'ts', 'm2ts', 'avi', 'mov', 'webm', 'flv', 'm4v'],
          ),
        ],
      );
      if (file == null) {
        return;
      }
      await _pushPlayer(file.path, file.name);
    } catch (_) {
      // Picker unavailable: ignore rather than crash the hub.
    }
  }

  Future<void> _pushPlayer(String path, String title) async {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: PsMotion.slow,
        reverseTransitionDuration: PsMotion.base,
        pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary) {
          return PlayerPage(path: path, title: title);
        },
        transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Widget _page(int index) {
    if (index == 1) {
      return const MediaPage();
    }
    return HomePage(
      onPlay: _play,
      onOpenFile: _openFile,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TvScale(
      child: Scaffold(
        backgroundColor: PsColor.bgDeep,
        body: Stack(
          children: <Widget>[
            for (int i = 0; i < 2; i++)
              if (_visited.contains(i))
                Positioned.fill(
                  child: Offstage(
                    offstage: _tab != i,
                    child: TickerMode(
                      enabled: _tab == i,
                      child: ExcludeFocus(
                        excluding: _tab != i,
                        child: _page(i),
                      ),
                    ),
                  ),
                ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: TopStatusBar(tabIndex: _tab, onTabSelected: _selectTab),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_ccOpen,
                child: AnimatedOpacity(
                  opacity: _ccOpen ? 1 : 0,
                  duration: PsMotion.base,
                  child: GestureDetector(
                    onTap: () => setState(() => _ccOpen = false),
                    child: const ColoredBox(color: Color(0x73000000)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ControlCenter(open: _ccOpen, onSelect: _onCcSelect),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    '${S.hintNavigate}   ·   ${S.hintSelect}   ·   ${S.hintDock}   ·   ${S.hintBack}',
                    style: PsType.micro.copyWith(fontSize: 14, color: PsColor.textFaint),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
