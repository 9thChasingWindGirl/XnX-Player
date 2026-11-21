import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/app_log.dart';
import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/sources/tmdb.dart';
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
    required this.onOpenGenre,
    required this.heroItem,
  });

  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onOpenItem;
  final VoidCallback onOpenFile;
  final VoidCallback onAddSource;
  final VoidCallback onOpenLibrary;

  /// Opens the library with a genre chip applied.
  final ValueChanged<String?> onOpenGenre;

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

  /// The banner's carousel. It rotates on its own and the hero's arrows step
  /// it; the previous build lost this when the hero became a single still.
  List<MediaItem> _heroItems = <MediaItem>[];
  int _heroIndex = 0;
  Timer? _heroTimer;

  /// TMDB portal rows. Null until the key answers, or when none is configured.
  TmdbHome? _tmdbHome;
  String _tmdbKey = '';
  bool _tmdbLoading = false;
  bool _tmdbTried = false;

  /// Genre filter applied to the portal rows, null = every category.
  String? _genre;

  @override
  void initState() {
    super.initState();
    _rows = _computeRows();
    _syncHero();
    _tmdbKey = AppStore.instance.tmdbKey;
    _fetchTmdb(_tmdbKey);
    AppStore.instance.addListener(_onStore);
    _sourceFilter.addListener(_onFilter);
    _publishFeatured();
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    AppStore.instance.removeListener(_onStore);
    _sourceFilter.removeListener(_onFilter);
    super.dispose();
  }

  void _onFilter() {
    if (!mounted) {
      return;
    }
    setState(() {
      _genre = null;
      _rows = _computeRows();
      _syncHero();
    });
    _publishFeatured();
  }

  void _onStore() {
    if (!mounted) {
      return;
    }
    final String key = AppStore.instance.tmdbKey;
    if (key != _tmdbKey) {
      _tmdbKey = key;
      _tmdbHome = null;
      _tmdbLoading = false;
      _tmdbTried = false;
      _fetchTmdb(key);
    }
    setState(() {
      _rows = _computeRows();
      _syncHero();
    });
    _publishFeatured();
  }

  /// Loads the portal rows in the background. The source library keeps
  /// rendering while this runs; a failed or missing key just leaves the home
  /// on the media-source rows.
  void _fetchTmdb(String key) {
    if (key.isEmpty) {
      _tmdbLoading = false;
      return;
    }
    if (_tmdbLoading) {
      return;
    }
    _tmdbLoading = true;
    unawaited(
      Tmdb(key).home().then((TmdbHome home) {
        if (!mounted || _tmdbKey != key) {
          return;
        }
        final bool empty = home.all.isEmpty;
        setState(() {
          _tmdbHome = empty ? null : home;
          _tmdbLoading = false;
          _tmdbTried = true;
          _rows = _computeRows();
          _syncHero();
        });
        _publishFeatured();
        if (empty) {
          AppLog.warn('TMDB 未返回任何条目，请检查 API Key 与网络');
        } else {
          AppLog.info(
              'TMDB 首页已载入：趋势 ${home.trending.length}，电影 ${home.popularMovies.length}，剧集 ${home.popularTv.length}');
        }
      }).catchError((Object error) {
        AppLog.warn('TMDB 首页加载失败：$error');
        if (mounted) {
          setState(() {
            _tmdbLoading = false;
            _tmdbTried = true;
          });
        }
      }),
    );
  }

  /// Builds the carousel from what is actually resumable/new, then starts the
  /// rotation. Called only for an index reset; the periodic timer handles the
  /// rest.
  void _syncHero() {
    final AppStore store = AppStore.instance;
    final String? filter = _sourceFilter.value;
    bool keep(MediaItem item) =>
        (filter == null || item.sourceId == filter) &&
        (_genre == null || item.genres.contains(_genre));
    final List<MediaItem> pool = <MediaItem>[
      ...store.continueWatching.where(keep),
      ...store.recent.reversed.where(keep),
      if (filter == null && _tmdbHome != null) ...Tmdb.link(_tmdbHome!.all, store.items),
      // A source view still needs a hero when nothing is resumable.
      ...store.items.where(keep),
    ];
    final List<MediaItem> next = <MediaItem>[];
    final Set<String> seen = <String>{};
    for (final MediaItem item in pool) {
      if (seen.add(item.id)) {
        next.add(item);
      }
      if (next.length >= 6) {
        break;
      }
    }
    _heroItems = next;
    if (_heroIndex >= _heroItems.length) {
      _heroIndex = 0;
    }
    _restartHeroTimer();
  }

  void _restartHeroTimer() {
    _heroTimer?.cancel();
    _heroTimer = null;
    if (_heroItems.length < 2 || AppStore.instance.prefs.reduceMotion) {
      return;
    }
    _heroTimer = Timer.periodic(const Duration(seconds: 9), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _heroIndex = (_heroIndex + 1) % _heroItems.length);
      _publishFeatured();
    });
  }

  void _stepHero(int delta) {
    if (_heroItems.length < 2) {
      return;
    }
    setState(() {
      _heroIndex = (_heroIndex + delta + _heroItems.length) % _heroItems.length;
    });
    _publishFeatured();
    _restartHeroTimer();
  }

  MediaItem? get _currentHero => _heroItems.isEmpty
      ? null
      : _heroItems[_heroIndex.clamp(0, _heroItems.length - 1).toInt()];

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
    final MediaItem? item = _currentHero ?? _featured;
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

    // A selected media source is its own home: its metadata and its files.
    // TMDB is the aggregate view and deliberately does not replace this.
    final String? sourceFilter = _sourceFilter.value;
    if (sourceFilter != null) {
      bool keep(MediaItem item) =>
          item.sourceId == sourceFilter &&
          (_genre == null || item.genres.contains(_genre));
      final List<MediaItem> own =
          store.items.where(keep).toList(growable: false);
      final List<MediaItem> resuming = store.continueWatching
          .where(keep)
          .toList(growable: false);
      final List<MediaItem> recent = store.recent.reversed
          .where(keep)
          .toList(growable: false);
      final List<MediaItem> favorites =
          own.where((MediaItem item) => item.favorite).toList(growable: false);
      final List<MediaItem> watching = own
          .where((MediaItem item) =>
              item.kind == MediaKind.series &&
              item.progress > 0.01 &&
              item.progress < 0.97)
          .toList(growable: false);
      final List<MediaItem> live =
          own.where((MediaItem item) => item.kind == MediaKind.channel).toList(growable: false);
      final List<MediaItem> all = own
          .where((MediaItem item) => item.kind != MediaKind.channel)
          .take(30)
          .toList(growable: false);
      return <_Row>[
        if (resuming.isNotEmpty)
          _Row('continue', S.continueWatching, resuming, wide: true),
        if (recent.isNotEmpty) _Row('recent', S.recentlyAdded, recent),
        if (all.isNotEmpty) _Row('all', S.allMedia, all),
        if (favorites.isNotEmpty) _Row('favorites', S.favoritesShelf, favorites),
        if (watching.isNotEmpty) _Row('watching', S.watchingShelf, watching),
        if (live.isNotEmpty) _Row('live', S.liveChannels, live, wide: true),
      ];
    }

    final TmdbHome? tmdb = _tmdbHome;
    final List<MediaItem> airing = _airing();
    final List<MediaItem> recommended = _recommended(store);

    // Portal rows. Every TMDB title is linked to a configured file when one
    // matches; unmatched ones stay in the row and report the missing source on
    // their detail page.
    final Set<String> seenTmdb = <String>{};
    List<MediaItem> portal(List<MediaItem> source) {
      final List<MediaItem> out = <MediaItem>[];
      for (final MediaItem item in Tmdb.link(source, store.items)) {
        if (seenTmdb.add(item.id)) {
          out.add(item);
        }
      }
      return out;
    }

    List<MediaItem> portalRows = const <MediaItem>[];
    List<_Row> tmdbRows = const <_Row>[];
    if (tmdb != null) {
      final List<MediaItem> nowPlaying = portal(tmdb.nowPlaying);
      final List<MediaItem> movies = portal(tmdb.popularMovies);
      final List<MediaItem> tv = portal(tmdb.popularTv);
      final List<MediaItem> air = portal(tmdb.onTheAir);
      final List<MediaItem> upcoming = portal(tmdb.upcoming);
      final List<MediaItem> trending = portal(tmdb.trending);
      portalRows = <MediaItem>[...nowPlaying, ...movies, ...tv, ...air, ...upcoming, ...trending];
      // A mix of wide (16:9) and poster (2:3) shelves: a wall of identical
      // poster rows reads as a grid, while alternating the card shape gives
      // the eye a rhythm — the grammar Plex itself uses on its home screen.
      tmdbRows = <_Row>[
        if (trending.isNotEmpty) _Row('tmdb-trending', S.trending, trending, wide: true),
        if (nowPlaying.isNotEmpty) _Row('tmdb-now', S.nowPlaying, nowPlaying),
        if (movies.isNotEmpty) _Row('tmdb-movies', S.hotMovies, movies),
        if (tv.isNotEmpty) _Row('tmdb-tv', S.hotSeries, tv),
        if (air.isNotEmpty) _Row('tmdb-air', S.airing, air, wide: true),
        if (upcoming.isNotEmpty) _Row('tmdb-upcoming', S.upcoming, upcoming),
        if (recommended.isNotEmpty) _Row('recommended', S.recommended, recommended),
      ];
    }

    final List<MediaItem> genreRow = _genre == null
        ? const <MediaItem>[]
        : portalRows.where((MediaItem item) => item.genres.contains(_genre)).toList(growable: false);

    final List<_Row> all = <_Row>[
      if (store.continueWatching.isNotEmpty)
        _Row('continue', S.continueWatching, store.continueWatching, wide: true),
      if (store.recent.isNotEmpty)
        _Row('recent', S.recentlyAdded, store.recent.reversed.toList(growable: false)),
      if (_genre != null) ...<_Row>[
        if (genreRow.isNotEmpty) _Row('genre', '${S.genre} · $_genre', genreRow),
      ]
      else if (tmdb == null) ...<_Row>[
        if (airing.isNotEmpty) _Row('airing', S.airing, airing, wide: true),
        if (recommended.isNotEmpty) _Row('recommended', S.recommended, recommended),
      ]
      else ...tmdbRows,
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

  /// Unfinished shows the server labels `Continuing`. Emby supplies the field;
  /// a source that does not (local files) simply omits the row.
  List<MediaItem> _airing() {
    final List<MediaItem> out = AppStore.instance.items
        .where((MediaItem item) =>
            item.kind == MediaKind.series &&
            (item.seriesStatus ?? '').toLowerCase() == 'continuing')
        .toList();
    out.sort((MediaItem a, MediaItem b) => (b.year ?? 0).compareTo(a.year ?? 0));
    return out;
  }

  /// "关联推荐" without an external catalogue: titles sharing a genre with what
  /// the user is already resuming or has just added. With no genres (a local
  /// folder without a scraper) the row is omitted rather than faked.
  List<MediaItem> _recommended(AppStore store) {
    final Set<String> seed = <String>{};
    for (final MediaItem item in <MediaItem>[
      ...store.continueWatching,
      ...store.recent.take(20),
    ]) {
      seed.addAll(item.genres);
    }
    if (seed.isEmpty) {
      return const <MediaItem>[];
    }
    final Set<String> resuming = store.continueWatching.map((MediaItem item) => item.id).toSet();
    final List<MediaItem> out = store.items
        .where((MediaItem item) =>
            item.isPlayable &&
            item.kind != MediaKind.channel &&
            !resuming.contains(item.id) &&
            item.genres.any(seed.contains))
        .take(24)
        .toList(growable: false);
    return out;
  }

  /// Genres present in the library, for the category quick-jump row.
  List<String> _categories(AppStore store) => _categoriesOf(store.items);

  List<String> _categoriesOf(Iterable<MediaItem> items) {
    final Set<String> genres = <String>{};
    for (final MediaItem item in items) {
      genres.addAll(item.genres);
    }
    final List<String> out = genres.toList()..sort();
    return out.take(14).toList(growable: false);
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
      final bool waitingTmdb = _tmdbKey.isNotEmpty && !_tmdbTried;
      if ((AppStore.instance.loading && AppStore.instance.errors.isEmpty) || waitingTmdb) {
        return const _Skeleton();
      }
      return _EmptyState(
        loading: AppStore.instance.loading,
        error: AppStore.instance.errors.isEmpty ? null : AppStore.instance.errors.first,
        onAddSource: widget.onAddSource,
        onOpenFile: widget.onOpenFile,
      );
    }

    final MediaItem featured = _currentHero ?? _featured ?? _rows.first.items.first;
    final String? filter = _sourceFilter.value;
    final List<String> categories = filter != null
        ? _categoriesOf(
            AppStore.instance.items.where((MediaItem item) => item.sourceId == filter))
        : (_tmdbHome != null
            ? _tmdbHome!.genres.map((TmdbGenre genre) => genre.name).toList(growable: false)
            : _categories(AppStore.instance));

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
              // A portal title with no file behind it opens its detail page,
              // which explains the missing media source.
              onPlay: () => featured.playable
                  ? widget.onPlay(featured)
                  : widget.onOpenItem(featured),
              onDetails: () => widget.onOpenItem(featured),
              onFavorite: () => AppStore.instance.toggleFavorite(featured),
              carouselIndex: _heroItems.length > 1 ? _heroIndex : null,
              carouselCount: _heroItems.length,
              onPrev: _heroItems.length > 1 ? () => _stepHero(-1) : null,
              onNext: _heroItems.length > 1 ? () => _stepHero(1) : null,
              onPickSlide: (int index) {
                setState(() => _heroIndex = index);
                _publishFeatured();
                _restartHeroTimer();
              },
            ),
            const SizedBox(height: 26),
            // A portal that returns nothing must not look like a missing
            // feature: without this the home simply reads as a local file
            // list, and "TMDB 首页不见了" is the only conclusion available.
            if (_tmdbKey.isNotEmpty && _tmdbTried && _tmdbHome == null)
              _tmdbNotice(),
            if (categories.isNotEmpty) _categoryRow(categories),
            for (int i = 0; i < _rows.length; i++) _shelfRow(i),
          ],
        ),
      ),
    );
  }

  /// TMDB is opt-in, and when it silently returns nothing the home screen just
  /// looks like a local file list. Name the two causes that actually happen —
  /// an invalid key, and a network that cannot reach api.themoviedb.org — so
  /// the difference between "broken" and "no catalogue" is visible.
  Widget _tmdbNotice() {
    return Padding(
      padding: EdgeInsets.fromLTRB(_margin, 0, _margin, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 18, color: PsColor.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'TMDB 内容未载入：API Key 可能无效，或当前网络无法访问 '
              'api.themoviedb.org。本地媒体库不受影响。',
              style: PsType.micro.copyWith(
                fontSize: 15,
                height: 1.5,
                color: PsColor.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Plex's "browse by genre" strip. It is the quickest way out of the home
  /// screen when the user already knows what they want.
  Widget _categoryRow(List<String> genres) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_margin, 0, _margin, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              TvFocusable(
                radius: 6,
                showRing: false,
                onSelect: widget.onOpenLibrary,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        S.browseByGenre,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: PlexColor.text,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 22, color: PlexColor.textDim),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _categoryChip(S.allGenres, null),
              for (final String genre in genres) _categoryChip(genre, genre),
            ],
          ),
        ],
      ),
    );
  }

  /// A portal genre filters the TMDB rows in place; without a TMDB key the
  /// same chip jumps to the library's genre filter.
  void _pickGenre(String? genre) {
    final bool sourceView = _sourceFilter.value != null;
    if (_tmdbHome == null && !sourceView) {
      // No portal and no source home to filter: the library is the only place
      // that can answer a genre query.
      widget.onOpenGenre(genre);
      return;
    }
    setState(() {
      _genre = genre;
      _rows = _computeRows();
      _syncHero();
    });
    if (_flow.hasClients) {
      _flow.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _categoryChip(String label, String? genre) {
    final bool selected = genre == null ? _genre == null : _genre == genre;
    return TvFocusable(
      radius: 999,
      showRing: false,
      onSelect: () => _pickGenre(genre),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? PlexColor.amber.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? PlexColor.amber : PlexColor.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            height: 1.1,
            fontWeight: FontWeight.w500,
            color: selected ? PlexColor.amber : PlexColor.textDim,
          ),
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
            onLongSelect: (MediaItem item) =>
                item.playable ? widget.onPlay(item) : widget.onOpenItem(item),
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
