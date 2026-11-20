import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../core/input/input_action.dart';
import '../core/input/input_router.dart';
import '../core/strings.dart';
import '../data/models/media_item.dart';
import '../data/prefs.dart';
import '../data/store.dart';
import '../design/ps_tokens.dart';
import '../pages/home/home_page.dart';
import '../pages/hub/hub_page.dart';
import '../pages/media/media_page.dart';
import '../pages/search/search_page.dart';
import '../pages/settings/settings_page.dart';
import '../player/player_page.dart';
import '../ui/core/focus_highlight.dart';
import '../ui/core/focus_navigator.dart';
import '../ui/core/tv_scale.dart';
import '../ui/widgets/ps_backdrop.dart';
import 'cc_panels.dart';
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
  bool _searchOpen = false;

  /// Which dock panel is raised, if any. Kept separate from [_ccOpen] because
  /// the dock stays up while a panel is open — that is the whole point.
  CcPanelId? _ccPanel;

  /// Mirrors the window state so the power panel can label its toggle.
  bool _fullscreen = false;

  /// Number of pushed routes (hub, player) above the shell. While any is open
  /// the shell must stay out of the keyboard: its handlers are registered
  /// first, so otherwise it would eat F1/Space/arrows that belong to the
  /// player's own bindings.
  int _routes = 0;

  /// This screen's place in the input stack. Cancelled on dispose, which is
  /// what makes 'the last route pushed wins' true without any ordering luck.
  InputSubscription? _input;

  @override
  void initState() {
    super.initState();
    _input = InputRouter.instance.subscribe(_onIntent, name: 'shell');
    unawaited(AppStore.instance.load());
    unawaited(_syncFullscreen());
  }

  /// The power panel labels its toggle, so it needs the real window state
  /// rather than the assumption that the app starts windowed.
  Future<void> _syncFullscreen() async {
    try {
      final bool value = await windowManager.isFullScreen();
      if (mounted) {
        setState(() => _fullscreen = value);
      }
    } on Object {
      // Window manager can be unavailable on some sessions; ignore.
    }
  }

  @override
  void dispose() {
    _input?.cancel();
    _hero.dispose();
    super.dispose();
  }

  /// One handler per screen, fed by [InputRouter]. The shell only sees intents
  /// that no route above it claimed.
  bool _onIntent(InputIntent intent) {
    // Navigation and activation are generic: they act on whatever holds focus,
    // which is the topmost route when one is open. Moving focus is not "shell
    // chrome", so a pushed route does not disable it — otherwise a gamepad
    // could open the hub and never move inside it.
    switch (intent.action) {
      case InputAction.navigateUp:
        return FocusNavigator.move(NavDir.up);
      case InputAction.navigateDown:
        return FocusNavigator.move(NavDir.down);
      case InputAction.navigateLeft:
        return FocusNavigator.move(NavDir.left);
      case InputAction.navigateRight:
        return FocusNavigator.move(NavDir.right);
      case InputAction.confirm:
        // A keyboard presses through the focused widget and a pointer through
        // its tap handler, so both have already happened by the time this runs.
        // A gamepad has no key event at all — this is that path.
        return FocusNavigator.activate();
      case InputAction.contextMenu:
        return FocusNavigator.menu();
      default:
        break;
    }

    // Everything else belongs to the shell, and a pushed route covers it: the
    // player must not inherit Ctrl+F, Tab or F1 from the screen underneath.
    if (_routes > 0) {
      return false;
    }

    switch (intent.action) {
      case InputAction.back:
        return _onBack();
      case InputAction.search:
        _openSearch();
        return true;
      case InputAction.toggleDock:
        _setDock(!_ccOpen);
        return true;
      case InputAction.openFile:
        unawaited(_openFile());
        return true;
      case InputAction.fullscreen:
        unawaited(_toggleFullScreen());
        return true;
      default:
        return false;
    }
  }

  /// Every transient layer the shell owns, bottom first.
  ///
  /// Back pops exactly one rung, so "close the panel, then the dock" is a
  /// property of this list instead of a ladder of nested ifs that every new
  /// overlay has to be taught separately.
  List<String> get _overlays => <String>[
    if (_ccOpen) 'dock',
    if (_ccPanel != null) 'panel',
    if (_searchOpen) 'search',
  ];

  bool _onBack() {
    final List<String> stack = _overlays;
    if (stack.isEmpty) {
      return false;
    }
    final String top = stack.last;
    setState(() {
      switch (top) {
        case 'search':
          _searchOpen = false;
        case 'panel':
          _ccPanel = null;
        case 'dock':
          _ccPanel = null;
          _ccOpen = false;
      }
    });
    if (top == 'search') {
      FocusNavigator.focusFirst();
    } else if (top == 'panel') {
      // Focus was inside the panel that just went away.
      _focusZone('dock-icons');
    }
    return true;
  }

  /// Opens or closes the dock, landing on its icon row when it appears rather
  /// than wherever focus happened to be.
  void _setDock(bool open) {
    setState(() {
      _ccOpen = open;
      if (!open) {
        _ccPanel = null;
      }
    });
    if (open) {
      _focusZone('dock-icons');
    }
  }

  Future<void> _toggleFullScreen() async {
    try {
      final bool current = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!current);
      if (mounted) {
        setState(() => _fullscreen = !current);
      }
    } on Object {
      // Window manager can be unavailable on some sessions; ignore.
    }
  }

  /// Moves focus into [zoneId] once the frame that contains it has laid out.
  void _focusZone(String zoneId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusNavigator.focusIn(zoneId);
      }
    });
  }

  void _selectTab(int index, {bool fromDock = false}) {
    final bool changed = index != _tab;
    setState(() {
      if (changed) {
        _tab = index;
        _visited.add(index);
      }
      _ccOpen = false;
      _ccPanel = null;
    });
    if (!fromDock) {
      return;
    }
    // The dock is about to stop being focusable, so the arrow keys would go
    // nowhere. Hand them back to the page that just became visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusNavigator.focusFirst();
      }
    });
  }

  void _onControlCenter(CcItem item) {
    switch (item.kind) {
      case CcKind.tab:
        _selectTab(item.tabIndex, fromDock: true);
      case CcKind.search:
        _openSearch();
      case CcKind.panel:
        _togglePanel(item.panel!);
    }
  }

  /// Second press on the same icon closes its panel, the way the console does.
  void _togglePanel(CcPanelId id) {
    final bool closing = _ccPanel == id;
    setState(() => _ccPanel = closing ? null : id);
    _focusZone(closing ? 'dock-icons' : 'cc-panel');
  }

  /// Item id whose panel is up, so the dock icon can stay lit.
  String? get _activeDockId {
    final CcPanelId? id = _ccPanel;
    if (id == null) {
      return null;
    }
    for (final CcItem item in kControlCenterItems) {
      if (item.panel == id) {
        return item.id;
      }
    }
    return null;
  }

  /// One exhaustive switch over [CcPanelId]: adding a dock panel without
  /// implementing it is a compile error, not a dead button.
  Widget _panelFor(CcPanelId id) {
    final AppStore store = AppStore.instance;
    final PlaybackPrefs prefs = store.prefs;
    switch (id) {
      case CcPanelId.recent:
        return CcRecentPanel(items: _recentItems(), onPlay: _playFromDock);
      case CcPanelId.notifications:
        return CcNotificationsPanel(
          errors: store.errors,
          loading: store.loading,
          sourceCount: store.sources.length,
          onRefresh: () => unawaited(store.refresh()),
          onClear: store.clearErrors,
        );
      case CcPanelId.sources:
        return CcSourcesPanel(
          sources: store.sources,
          onRefresh: () => unawaited(store.refresh()),
          onAdd: _addSource,
        );
      case CcPanelId.sound:
        return CcSoundPanel(prefs: prefs, onChanged: _applyPrefs, hw: store.hw);
      case CcPanelId.subtitle:
        return CcSubtitlePanel(prefs: prefs, onChanged: _applyPrefs);
      case CcPanelId.picture:
        return CcPicturePanel(prefs: prefs, onChanged: _applyPrefs);
      case CcPanelId.profile:
        return CcProfilePanel(
          version: S.appVersion,
          sources: store.sources.length,
          media: store.items.length,
          favorites: store.items.where((MediaItem item) => item.favorite).length,
          onOpenSettings: () => _selectTab(2, fromDock: true),
        );
      case CcPanelId.power:
        return CcPowerPanel(
          fullscreen: _fullscreen,
          onToggleFullscreen: () => unawaited(_toggleFullScreen()),
          onMinimize: () => unawaited(_minimize()),
          onQuit: () => unawaited(_quitApp()),
        );
    }
  }

  /// Panel host, rebuilt from the store so a slider or toggle repaints the row
  /// immediately instead of waiting for the next shell rebuild.
  Widget? _panelHost() {
    final CcPanelId? id = _ccPanel;
    if (id == null) {
      return null;
    }
    return AnimatedBuilder(
      animation: AppStore.instance,
      builder: (BuildContext context, Widget? child) => _panelFor(id),
    );
  }

  void _applyPrefs(PlaybackPrefs value) {
    unawaited(AppStore.instance.updatePrefs(value));
  }

  /// Resumable items first, then the rest of the catalogue: "最近" is about
  /// what you were watching, not what was added last.
  List<MediaItem> _recentItems() {
    final AppStore store = AppStore.instance;
    final List<MediaItem> out = <MediaItem>[];
    final Set<String> seen = <String>{};
    for (final MediaItem item in <MediaItem>[
      ...store.continueWatching,
      ...store.recent.reversed,
    ]) {
      if (seen.add(item.id)) {
        out.add(item);
      }
      if (out.length >= 10) {
        break;
      }
    }
    return out;
  }

  void _playFromDock(MediaItem item) {
    setState(() {
      _ccOpen = false;
      _ccPanel = null;
    });
    unawaited(_play(item));
  }

  Future<void> _minimize() async {
    try {
      await windowManager.minimize();
    } on Object {
      // Window manager can be unavailable on some sessions; ignore.
    }
  }

  Future<void> _quitApp() async {
    try {
      await windowManager.destroy();
    } on Object {
      // Window manager can be unavailable on some sessions; ignore.
    }
  }

  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _ccOpen = false;
      _ccPanel = null;
    });
  }

  void _closeSearch() {
    setState(() => _searchOpen = false);
    FocusNavigator.focusFirst();
  }

  void _addSource() {
    setState(() {
      _tab = 1;
      _visited.add(1);
      _ccOpen = false;
      _ccPanel = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryKey.currentState?.openSourceDialog();
    });
  }

  Future<void> _push(Route<void> route) async {
    _routes++;
    try {
      await Navigator.of(context).push<void>(route);
    } finally {
      _routes--;
    }
  }

  Future<void> _play(MediaItem item) => _playQueue(item, const <MediaItem>[]);

  Future<void> _playQueue(MediaItem item, List<MediaItem> queue) {
    return _push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: PsMotion.slow,
        reverseTransitionDuration: PsMotion.base,
        pageBuilder: (BuildContext context, Animation<double> animation,
                Animation<double> secondaryAnimation) =>
            PlayerPage(item: item, queue: queue),
        transitionsBuilder: (BuildContext context, Animation<double> animation,
            Animation<double> secondaryAnimation, Widget child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _openHub(MediaItem item) {
    return _push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: PsMotion.slow,
        reverseTransitionDuration: PsMotion.base,
        pageBuilder: (BuildContext context, Animation<double> animation,
                Animation<double> secondaryAnimation) =>
            HubPage(item: item, onPlay: (MediaItem choice, List<MediaItem> queue) {
          Navigator.of(context).pop();
          unawaited(_playQueue(choice, queue));
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
                      child: TopStatusBar(
                        tabIndex: _tab,
                        onTabSelected: _selectTab,
                        onSearch: _openSearch,
                      ),
                    ),
                    if (_searchOpen)
                      Positioned.fill(
                        child: SearchOverlay(
                          onPlay: (MediaItem item) {
                            setState(() => _searchOpen = false);
                            unawaited(_play(item));
                          },
                          onOpen: (MediaItem item) {
                            setState(() => _searchOpen = false);
                            unawaited(_openHub(item));
                          },
                          onClose: _closeSearch,
                        ),
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
                    onTap: () => setState(() {
                      _ccOpen = false;
                      _ccPanel = null;
                    }),
                    child: ColoredBox(color: const Color(0xFF000000).withValues(alpha: 0.55)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ControlCenter(
                open: _ccOpen,
                onSelect: _onControlCenter,
                activeId: _activeDockId,
                panel: _panelHost(),
              ),
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
