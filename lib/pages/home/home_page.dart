import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/store.dart';
import '../../design/ps_tokens.dart';
import '../../shell/shell_page.dart' show shellSourceFilter;
import '../../ui/core/tv_focusable.dart';
import '../../ui/widgets/ps_button.dart';
import 'home_hero.dart';
import 'home_rail.dart';
import 'home_tile.dart';

/// Plex-style home screen: a wide featured banner, then dense rows of artwork.
///
/// The console stage it replaces owned the whole screen with one poster and a
/// vertical carousel. Plex's grammar is the opposite — the picture is a banner,
/// the content is rows, and the eye moves down and sideways. Everything here is
/// built from that: 64 px side margins, 2:3 posters at 8 per shelf, 16:9 stills
/// for "continue watching", and one caption per focused card.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onPlay,
    required this.onOpenItem,
    required this.onOpenFile,
    required this.onAddSource,
    required this.onOpenLibrary,
    required this.heroItem,
  });

  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onOpenItem;
  final VoidCallback onOpenFile;
  final VoidCallback onAddSource;
  final VoidCallback onOpenLibrary;

  /// Lets the shell tint its backdrop with the featured cover's palette.
  final ValueNotifier<MediaItem?> heroItem;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _Row {
  const _Row(this.id, this.title, this.items, {this.wide = false});

  /// Stable identity for the saved shelf order.
  final String id;
  final String title;
  final List<MediaItem> items;

  /// Wide shelves carry 16:9 stills (continue watching), the rest 2:3 posters.
  final bool wide;
}

class _HomePageState extends State<HomePage> {
  /// Horizontal margin of the home layout. Plex uses roughly 3 % at 1080p.
  static const double _margin = 64;

  /// Poster geometry. 192 × 288 is 2:3 — eight fill a 1920 row with Plex's
  /// 16 px gutters, which is the density its own home rows use.
  static const double _posterWidth = 192;
  static const double _posterHeight = 288;
  static const double _wideWidth = 380;
  static const double _wideHeight = 214;
  static const double _gap = 16;
  static const double _grow = 1.06;

  final ValueNotifier<String?> _sourceFilter = shellSourceFilter;
  final ScrollController _flow = ScrollController();

  List<_Row> _rows = <_Row>[];
  final List<int> _columns = <int>[];

  /// The only shelf allowed to keep a card in its focused state. Without this,
  /// every row would retain the caption of the card the user left behind.
  /// `-1` until focus actually enters a shelf, so nothing claims focus on load.
  int _activeRow = -1;
  String? _publishedId;

  @override
  void initState() {
    super.initState();
    _rows = _computeRows();
    AppStore.instance.addListener(_onStore);
    _sourceFilter.addListener(_onFilter);
    _publishFeatured();
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_onStore);
    _sourceFilter.removeListener(_onFilter);
    super.dispose();
  }

  void _onFilter() {
    if (!mounted) {
      return;
    }
    setState(() => _rows = _computeRows());
    _publishFeatured();
  }

  void _onStore() {
    if (!mounted) {
      return;
    }
    setState(() => _rows = _computeRows());
    _publishFeatured();
  }

  /// The top row's first item is what the banner shows, the way Plex features
  /// the newest thing you can resume.
  MediaItem? get _featured {
    for (final _Row row in _rows) {
      if (row.items.isNotEmpty) {
        return row.items.first;
      }
    }
    return null;
  }

  void _publishFeatured() {
    final MediaItem? item = _featured;
    if (item == null || item.id == _publishedId) {
      return;
    }
    _publishedId = item.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.heroItem.value = item;
      }
    });
  }

  /// The shelves, in the order the user arranged them. Unknown ids (a source
  /// went away) sort last; missing ids (a new shelf) are appended — both so
  /// the saved order stays valid without a migration.
  List<_Row> _computeRows() {
    final AppStore store = AppStore.instance;
    final List<_Row> all = <_Row>[
      if (store.continueWatching.isNotEmpty)
        _Row('continue', S.continueWatching, store.continueWatching, wide: true),
      if (store.recent.isNotEmpty)
        _Row('recent', S.recentlyAdded, store.recent.reversed.toList(growable: false)),
      if (store.items.any((MediaItem item) => item.favorite))
        _Row('favorites', S.favoritesShelf,
            store.items.where((MediaItem item) => item.favorite).toList(growable: false)),
      if (_seriesInFlight().isNotEmpty)
        _Row('watching', S.watchingShelf, _seriesInFlight()),
      if (store.channels.isNotEmpty)
        _Row('live', S.liveChannels, store.channels, wide: true),
    ];
    final String? filter = _sourceFilter.value;
    List<_Row> rows = filter == null
        ? all
        : all
            .map((_Row row) => _Row(
                  row.id,
                  row.title,
                  row.items
                      .where((MediaItem item) => item.sourceId == filter)
                      .toList(growable: false),
                  wide: row.wide,
                ))
            .where((_Row row) => row.items.isNotEmpty)
            .toList(growable: false);
    final List<String> order = store.prefs.shelfOrder;
    if (order.isEmpty) {
      return rows;
    }
    bool known(_Row row) => order.contains(row.id);
    int rank(_Row row) => known(row) ? order.indexOf(row.id) : order.length;
    return rows.toList()..sort((_Row a, _Row b) => rank(a).compareTo(rank(b)));
  }

  /// Series with any progress are "正在追剧"; a finished or untouched series
  /// belongs to the library, not to this shelf.
  List<MediaItem> _seriesInFlight() {
    return AppStore.instance.items
        .where((MediaItem item) =>
            item.kind == MediaKind.series && item.progress > 0.01 && item.progress < 0.97)
        .toList(growable: false);
  }

  void _focusAt(int row, int column) {
    while (_columns.length < row + 1) {
      _columns.add(0);
    }
    if (_columns[row] == column && _activeRow == row) {
      return;
    }
    setState(() {
      _columns[row] = column;
      _activeRow = row;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) {
      if (AppStore.instance.loading && AppStore.instance.errors.isEmpty) {
        return const _Skeleton();
      }
      return _EmptyState(
        loading: AppStore.instance.loading,
        error: AppStore.instance.errors.isEmpty ? null : AppStore.instance.errors.first,
        onAddSource: widget.onAddSource,
        onOpenFile: widget.onOpenFile,
      );
    }

    final MediaItem featured = _featured ?? _rows.first.items.first;

    return ColoredBox(
      color: PlexColor.bg,
      child: SingleChildScrollView(
        controller: _flow,
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PlexHero(
              item: featured,
              onPlay: () => widget.onPlay(featured),
              onDetails: () => widget.onOpenItem(featured),
              onFavorite: () => AppStore.instance.toggleFavorite(featured),
            ),
            const SizedBox(height: 22),
            for (int i = 0; i < _rows.length; i++) _shelfRow(i),
          ],
        ),
      ),
    );
  }

  Widget _shelfRow(int index) {
    final _Row row = _rows[index];
    final int column =
        (_columns.length > index ? _columns[index] : 0).clamp(0, row.items.length - 1).toInt();
    final double cardHeight = row.wide ? _wideHeight : _posterHeight;
    // Posters are 2:3, not squares: the rail's resting width and height are
    // separate so the focused card grows along both axes.
    final double cardWidth = row.wide ? _wideWidth : _posterWidth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(_margin, index == 0 ? 4 : 30, _margin, 14),
          child: Row(
            children: <Widget>[
              Text(
                row.title,
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: PlexColor.text,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${row.items.length}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: PlexColor.textFaint,
                ),
              ),
              const Spacer(),
              TvFocusable(
                radius: 4,
                onSelect: widget.onOpenLibrary,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '查看全部',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: PlexColor.textDim,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded, size: 20, color: PlexColor.textDim),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight * _grow + 16,
          child: HomeRail(
            items: row.items,
            focusedIndex: index == _activeRow ? column : -1,
            active: true,
            cardSize: cardHeight,
            cardWidth: cardWidth,
            grow: _grow,
            gap: _gap,
            paddingLeft: _margin,
            cornerRadius: PlexCard.radius,
            startIndex: row.wide ? 1 : 2,
            cardBuilder: (MediaItem item, double width, double height, bool focused) =>
                PlexCard(
              item: item,
              width: width,
              height: height,
              focused: focused,
              wide: row.wide,
            ),
            onFocus: (int value) => _focusAt(index, value),
            onSelect: widget.onOpenItem,
            onLongSelect: widget.onPlay,
          ),
        ),
      ],
    );
  }
}

/// Loading placeholder with the page's silhouette: one banner and two shelves.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final Color block = Colors.white.withValues(alpha: 0.05);
    final Color soft = Colors.white.withValues(alpha: 0.035);

    Widget posterRow(double top) {
      return Positioned(
        left: _HomePageState._margin,
        top: top,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < 8; i++)
              Padding(
                padding: const EdgeInsets.only(right: _HomePageState._gap),
                child: Container(
                  width: _HomePageState._posterWidth,
                  height: _HomePageState._posterHeight,
                  decoration: BoxDecoration(
                    color: block,
                    borderRadius: BorderRadius.circular(PlexCard.radius),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: PlexColor.bg,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: PlexHero.height,
            child: ColoredBox(color: PlexColor.surface),
          ),
          Positioned(
            left: _HomePageState._margin,
            bottom: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(width: 120, height: 16, color: soft),
                const SizedBox(height: 14),
                Container(width: 520, height: 54, color: block),
                const SizedBox(height: 12),
                Container(width: 360, height: 18, color: soft),
                const SizedBox(height: 20),
                Container(width: 150, height: 46, color: block),
              ],
            ),
          ),
          posterRow(PlexHero.height + 80),
          posterRow(PlexHero.height + 80 + _HomePageState._posterHeight * 1.06 + 64),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.loading,
    required this.error,
    required this.onAddSource,
    required this.onOpenFile,
  });

  final bool loading;
  final String? error;
  final VoidCallback onAddSource;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PlexColor.bg,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            left: 96,
            top: 260,
            width: 1000,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'XnX',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: PlexColor.amber,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  loading ? S.loading : S.emptyTitle,
                  style: const TextStyle(
                    fontSize: 48,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: PlexColor.text,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  error ?? S.emptyBody,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.6,
                    color: error == null ? PlexColor.textDim : PsColor.danger,
                  ),
                ),
                const SizedBox(height: 36),
                Row(
                  children: <Widget>[
                    PsButton(
                      label: S.addSource,
                      icon: Icons.add_rounded,
                      primary: true,
                      width: 220,
                      onSelect: onAddSource,
                    ),
                    const SizedBox(width: 14),
                    PsButton(
                      label: S.openFile,
                      icon: Icons.folder_open_rounded,
                      width: 220,
                      onSelect: onOpenFile,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
