import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/strings.dart';
import '../data/models/media_item.dart';
import '../data/store.dart';
import '../design/ps_tokens.dart';
import '../pages/home/home_page.dart';
import '../pages/hub/hub_page.dart';
import '../pages/media/media_page.dart';
import '../pages/settings/settings_page.dart';
import '../player/player_page.dart';
import '../ui/core/focus_highlight.dart';
import '../ui/core/focus_navigator.dart';
import '../ui/core/text_entry.dart';
import '../ui/core/tv_scale.dart';
import '../ui/widgets/ps_backdrop.dart';
import 'control_center.dart';
import 'control_center_items.dart';
import 'top_status_bar.dart';

/// Root screen: the drifting backdrop, the tab pages, then chrome.
///
/// The pages live inside one [GlideFocusStage] so the highlight can travel from
/// a shelf tile up to the top bar without ever being re-created.
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  static const int _tabCount = 3;

  final GlobalKey<MediaPageState> _libraryKey = GlobalKey<MediaPageState>();
  final ValueNotifier<MediaItem?> _hero = ValueNotifier<MediaItem?>(null);

  int _tab = 0;
  final Set<int> _visited = <int>{0};
  bool _ccOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(AppStore.instance.load());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _hero.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (_ccOpen) {
        setState(() => _ccOpen = false);
        return true;
      }
      return false;
    }

    // A dialog owns the keyboard: arrows must move the caret, not the focus.
    if (TextEntry.active.value) {
      return false;
    }

    if (key == LogicalKeyboardKey.tab) {
      setState(() => _ccOpen = !_ccOpen);
      return true;
    }
    if (key == LogicalKeyboardKey.f1) {
      unawaited(_openFile());
      return true;
    }
    if (key == LogicalKeyboardKey.f11) {
      unawaited(_toggleFullScreen());
      return true;
    }

    final NavDir? direction = _directionFor(key);
    if (direction != null) {
      FocusNavigator.move(direction);
      return true;
    }
    return false;
  }

  NavDir? _directionFor(LogicalKeyboardKey key) {
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

  Future<void> _toggleFullScreen() async {
    try {
      final bool current = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!current);
    } on Object {
      // Window manager can be unavailable on some sessions; ignore.
    }
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

  void _onControlCenter(CcItem item) {
    setState(() => _ccOpen = false);
    if (item.id == 'home') {
      _selectTab(0);
    } else if (item.id == 'downloads' || item.id == 'music') {
      _selectTab(1);
    }
  }

  void _addSource() {
    setState(() {
      _tab = 1;
      _visited.add(1);
      _ccOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryKey.currentState?.openSourceDialog();
    });
  }

  Future<void> _play(MediaItem item) async {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: PsMotion.slow,
        reverseTransitionDuration: PsMotion.base,
        pageBuilder: (BuildContext context, Animation<double> animation,
                Animation<double> secondaryAnimation) =>
            PlayerPage(item: item),
        transitionsBuilder: (BuildContext context, Animation<double> animation,
            Animation<double> secondaryAnimation, Widget child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _openHub(MediaItem item) async {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: PsMotion.slow,
        reverseTransitionDuration: PsMotion.base,
        pageBuilder: (BuildContext context, Animation<double> animation,
                Animation<double> secondaryAnimation) =>
            HubPage(item: item, onPlay: (MediaItem choice) {
          Navigator.of(context).pop();
          unawaited(_play(choice));
        }),
        transitionsBuilder: (BuildContext context, Animation<double> animation,
            Animation<double> secondaryAnimation, Widget child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _openFile() async {
    try {
      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[
          const XTypeGroup(
            label: '视频',
            extensions: <String>[
              'mkv', 'mp4', 'm4v', 'ts', 'm2ts', 'avi', 'mov', 'webm', 'flv', 'wmv',
            ],
          ),
        ],
      );
      if (file == null) {
        return;
      }
      await _play(
        MediaItem(
          id: 'local::${file.path}',
          sourceKind: SourceKind.local,
          kind: MediaKind.file,
          title: _trimExtension(file.name),
          path: file.path,
        ),
      );
    } on Object {
      // Picker unavailable: the library's folder source still works.
    }
  }

  static String _trimExtension(String name) {
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Widget _page(int index) {
    if (index == 1) {
      return MediaPage(
        key: _libraryKey,
        onPlay: _play,
        onOpenItem: _openHub,
        onOpenFile: _openFile,
      );
    }
    if (index == 2) {
      return const SettingsPage();
    }
    return HomePage(
      onPlay: _play,
      onOpenItem: _openHub,
      onOpenFile: _openFile,
      onAddSource: _addSource,
      heroItem: _hero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TvScale(
      child: Scaffold(
        backgroundColor: PsColor.bgDeep,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ValueListenableBuilder<MediaItem?>(
                valueListenable: _hero,
                builder: (BuildContext context, MediaItem? item, Widget? child) {
                  return PsBackdrop(palette: item?.artwork);
                },
              ),
            ),
            Positioned.fill(
              child: GlideFocusStage(
                child: Stack(
                  children: <Widget>[
                    for (int i = 0; i < _tabCount; i++)
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
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_ccOpen,
                child: AnimatedOpacity(
                  opacity: _ccOpen ? 1 : 0,
                  duration: PsMotion.base,
                  child: GestureDetector(
                    onTap: () => setState(() => _ccOpen = false),
                    child: ColoredBox(color: const Color(0xFF000000).withValues(alpha: 0.55)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ControlCenter(open: _ccOpen, onSelect: _onControlCenter),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    '${S.hintNavigate}    ·    ${S.hintSelect}    ·    ${S.hintDock}    ·    ${S.hintBack}',
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
