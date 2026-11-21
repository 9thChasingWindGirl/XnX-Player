import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/store.dart';
import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';
import '../../shell/shell_page.dart' show shellSourceFilter;
import '../../ui/core/focus_highlight.dart';
import '../../ui/core/tv_scale.dart';
import '../../ui/core/tv_focusable.dart';
import '../../ui/core/focus_zone.dart';
import '../../ui/core/motion_clock.dart';
import '../../ui/widgets/ps_button.dart';
import 'home_hero.dart';
import 'home_rail.dart';

/// The console home screen: one hero panel, a stack of shelves that slide
/// vertically, and a single gliding focus highlight shared by all of them.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onPlay,
    required this.onOpenItem,
    required this.onOpenFile,
    required this.onAddSource,
    required this.heroItem,
  });

  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onOpenItem;
  final VoidCallback onOpenFile;
  final VoidCallback onAddSource;

  /// Lets the shell tint its backdrop with the focused cover's palette.
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
  final List<int> _columns = <int>[];

  /// Which source the shelves show, or null for everything. The top bar's
  /// source pill writes here; this page only reads.
  final ValueNotifier<String?> _sourceFilter = shellSourceFilter;

  final ScrollController _flow = ScrollController();

  List<_Row> _rows = <_Row>[];
  int _row = 0;

  MediaItem? _shown;
  MediaItem? _previous;
  double _transition = 1;
  double _age = 0;
  double _last = -1;
  String? _publishedId;

  @override
  void initState() {
    super.initState();
    _rows = _computeRows();
    _shown = _firstItem();
    _publishedId = _shown?.id;
    AppStore.instance.addListener(_onStore);
    _sourceFilter.addListener(_onFilter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.heroItem.value = _shown;
      }
    });
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_onStore);
    _sourceFilter.removeListener(_onFilter);
    super.dispose();
  }

  /// A source pill change re-filters the shelves without touching the hero.
  void _onFilter() {
    if (!mounted) {
      return;
    }
    setState(() {
      _rows = _computeRows();
      if (_row >= _rows.length) {
        _row = math.max(0, _rows.length - 1);
      }
    });
  }

  void _onStore() {
    if (!mounted) {
      return;
    }
    setState(() {
      _rows = _computeRows();
      if (_row >= _rows.length) {
        _row = math.max(0, _rows.length - 1);
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
      if (_seriesInFlight().isNotEmpty)
        _Row('watching', S.watchingShelf, _seriesInFlight()),
      if (store.items.any((MediaItem item) => item.favorite))
        _Row('favorites', S.favoritesShelf,
            store.items.where((MediaItem item) => item.favorite).toList(growable: false)),
      if (store.recent.isNotEmpty)
        _Row('history', S.historyShelf, store.recent.reversed.toList(growable: false)),
      if (store.channels.isNotEmpty)
        _Row('live', S.liveChannels, store.channels),
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

  MediaItem? _firstItem() {
    if (_rows.isEmpty || _rows.first.items.isEmpty) {
      return null;
    }
    return _rows.first.items.first;
  }

  void _focusAt(int row, int column) {
    if (row < 0 || row >= _rows.length) {
      return;
    }
    if (_row == row && column < _columns.length && _columns[row] == column) {
      return;
    }
    _row = row;
    while (_columns.length < _rows.length) {
      _columns.add(0);
    }
    _columns[row] = column;
  }

  void _beginCrossFade(MediaItem next) {
    if (_shown?.id == next.id) {
      // Same title, new instance (progress or favourite changed): adopt it
      // without restarting the cross-fade.
      _shown = next;
      return;
    }
    _previous = _shown;
    _shown = next;
    _transition = 0;
    if (_publishedId != next.id) {
      _publishedId = next.id;
      // Deferred: the shell's backdrop listens to this notifier, and marking a
      // widget dirty during build is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.heroItem.value = next;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MotionBuilder(
      builder: (BuildContext context, double dt) {
        final MotionClock clock = MotionScope.of(context);
        if (clock.time != _last) {
          _last = clock.time;
          _age += clock.scaled(dt);
          _transition = (_transition + clock.scaled(dt) / PsMotion.heroCrossFade)
              .clamp(0.0, 1.0)
              .toDouble();
        }

        if (_rows.isEmpty) {
          // A network source can take seconds to enumerate. A skeleton keeps
          // the page's shape visible during that wait — a blank stage with one
          // line of text reads as "nothing here", which is a different claim.
          if (AppStore.instance.loading && AppStore.instance.errors.isEmpty) {
            return _Skeleton(time: clock.time, entrance: clamp01(_age / PsMotion.entrance));
          }
          return _EmptyState(
            loading: AppStore.instance.loading,
            error: AppStore.instance.errors.isEmpty ? null : AppStore.instance.errors.first,
            entrance: clamp01(_age / PsMotion.entrance),
            onAddSource: widget.onAddSource,
            onOpenFile: widget.onOpenFile,
          );
        }

        final int row = _row.clamp(0, _rows.length - 1).toInt();
        final List<MediaItem> items = _rows[row].items;
        final int column =
            (_columns.length > row ? _columns[row] : 0).clamp(0, items.length - 1).toInt();
        final MediaItem focused = items[column];
        _beginCrossFade(focused);

        final double t = _transition;
        final double arrive = ((t - 0.25) / 0.75).clamp(0.0, 1.0).toDouble();
        final double leave =
            (1 - Ease.smoothstep((t * 2.2).clamp(0.0, 1.0).toDouble())).clamp(0.0, 1.0).toDouble();
        final double band = _heroBand();

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            // The hero owns a fixed top band. Its backdrop bleeds a little
            // below the band so the flow arrives on the picture's own shadow.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: band + 90,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: <Widget>[
                  if (_previous != null && t < 1)
                    HeroPanel(
                      item: _previous!,
                      opacity: leave,
                      slide: -36 * Ease.cubicIn(t),
                      time: clock.time,
                    ),
                  HeroPanel(
                    item: _shown ?? focused,
                    opacity: Ease.smoothstep(arrive),
                    slide: 44 * (1 - Ease.quintOut(arrive)),
                    time: clock.time,
                    onPlay: () => widget.onPlay(_shown ?? focused),
                    onFavorite: () => AppStore.instance.toggleFavorite(_shown ?? focused),
                    onDetails: () => widget.onOpenItem(_shown ?? focused),
                    carousel: HeroCarousel(
                      items: items,
                      activeId: (_shown ?? focused).id,
                      onPick: (MediaItem picked) {
                        final int index = items.indexOf(picked);
                        if (index >= 0) {
                          _focusAt(row, index);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            // The shelf flow, Plex style: rows of normal-brightness posters
            // scrolling under a fixed hero, the row you focus gliding into
            // view. Replaces the console dim-and-swap shelves, which fought
            // the flow layout and left the bottom of tall windows empty.
            Positioned(
              left: 0,
              right: 0,
              top: band,
              bottom: 0,
              child: SingleChildScrollView(
                controller: _flow,
                padding: const EdgeInsets.only(top: 64, bottom: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int i = 0; i < _rows.length; i++) _shelfRow(i),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The vertical band the hero owns, derived from the stage's design height:
  /// 16:9 stages get the tuned constant, taller stages give the hero a little
  /// more room so the shelves still start on clean ground.
  /// The vertical band the hero owns, derived from the stage's design height.
  /// 16:9 stages get the tuned constant; taller stages give the hero a little
  /// more room so the copy never crowds the band edge.
  double _heroBand() {
    final double height = TvScale.heightOf(context);
    return (height * 0.62).clamp(640.0, 780.0).toDouble();
  }

  /// One row of the flow. Every row is a normal-brightness shelf — focus
  /// grows its card, the rail scrolls to keep the focused card in the anchor
  /// slot, and the flow scrolls the row into view. That is the Plex grammar;
  /// the console's dim-and-swap shelves fought it at every step.
  Widget _shelfRow(int index) {
    final _Row row = _rows[index];
    final bool active = index == _row;
    final int column =
        (_columns.length > index ? _columns[index] : 0).clamp(0, row.items.length - 1).toInt();
    final double cardHeight = row.wide ? 180.0 : PsSpace.tileSize;
    final double? cardWidth = row.wide ? 320.0 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: PsSpace.safeX, bottom: 16),
          child: Row(
            children: <Widget>[
              Text(
                row.title,
                style: PsType.section.copyWith(
                  color: PsColor.text.withValues(alpha: active ? 0.96 : 0.62),
                ),
              ),
              const SizedBox(width: 16),
              // Order controls, quiet until wanted.
              TvFocusable(
                radius: 10,
                showRing: false,
                onSelect: () => _moveShelf(index, -1),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 20,
                  color: index == 0
                      ? PsColor.text.withValues(alpha: 0.16)
                      : PsColor.text.withValues(alpha: 0.42),
                ),
              ),
              const SizedBox(width: 6),
              TvFocusable(
                radius: 10,
                showRing: false,
                onSelect: () => _moveShelf(index, 1),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  size: 20,
                  color: index == _rows.length - 1
                      ? PsColor.text.withValues(alpha: 0.16)
                      : PsColor.text.withValues(alpha: 0.42),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight * PsSpace.cardGrow + 30,
          child: HomeRail(
            items: row.items,
            focusedIndex: active ? column : -1,
            active: true,
            cardSize: cardHeight,
            cardWidth: cardWidth,
            onFocus: (int value) {
              _focusAt(index, value);
              _ensureRowVisible(index);
            },
            onSelect: widget.onOpenItem,
            onLongSelect: widget.onPlay,
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  /// Scrolls the flow so row [index] is fully on screen. Row geometry is
  /// fixed and known — title block, grown card, gap — so the offset is
  /// computed, not measured: no need to keep per-row contexts alive.
  void _ensureRowVisible(int index) {
    if (!_flow.hasClients) {
      return;
    }
    double top = 64; // flow padding
    for (int i = 0; i < index; i++) {
      final double card = _rows[i].wide ? 180.0 : PsSpace.tileSize;
      top += 44 + card * PsSpace.cardGrow + 30 + 30;
    }
    final double card = _rows[index].wide ? 180.0 : PsSpace.tileSize;
    final double bottom = top + 44 + card * PsSpace.cardGrow + 30;
    final double viewport = _flow.position.viewportDimension;
    double target = _flow.offset;
    if (top - 48 < target) {
      target = top - 48;
    }
    if (bottom + 48 > target + viewport) {
      target = bottom + 48 - viewport;
    }
    _flow.animateTo(
      target.clamp(0.0, _flow.position.maxScrollExtent).toDouble(),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  /// Moves shelf [index] by [delta] rows and persists the new order.
  void _moveShelf(int index, int delta) {
    final int target = index + delta;
    if (target < 0 || target >= _rows.length || index == target) {
      return;
    }
    final List<_Row> next = _rows.toList();
    final _Row moved = next.removeAt(index);
    next.insert(target, moved);
    setState(() => _rows = next);
    unawaited(AppStore.instance.updatePrefs(
      AppStore.instance.prefs.copyWith(
        shelfOrder: next.map((_Row row) => row.id).toList(growable: false),
      ),
    ));
  }
}

/// Loading placeholder: the page's own silhouette, breathing.
///
/// Every block sits where real content will sit — hero copy, three shelves —
/// so arrival is a fill-in rather than a relayout. Opacity breathes slowly;
/// nothing here justifies the cost of shimmer shaders.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.time, required this.entrance});

  final double time;
  final double entrance;

  @override
  Widget build(BuildContext context) {
    final double pulse = 0.5 + 0.5 * breathe(time, speed: 1.1);
    final Color block = PsColor.text.withValues(alpha: 0.055 + 0.045 * pulse);
    final Color soft = PsColor.text.withValues(alpha: 0.04 + 0.03 * pulse);

    Widget shelf(double top, {required double cardSize, required int count}) {
      return Positioned(
        left: PsSpace.safeX,
        top: top,
        child: Opacity(
          opacity: entrance,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < count; i++)
                Padding(
                  padding: const EdgeInsets.only(right: PsSpace.cardGap),
                  child: Container(
                    width: cardSize,
                    height: cardSize,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: BorderRadius.circular(PsRadius.card),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Hero copy blocks, top-left.
        Positioned(
          left: PsSpace.safeX,
          top: 240,
          child: Opacity(
            opacity: entrance,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(width: 520, height: 64, color: block),
                const SizedBox(height: 22),
                Container(width: 760, height: 26, color: soft),
                const SizedBox(height: 14),
                Container(width: 660, height: 26, color: soft),
                const SizedBox(height: 44),
                Row(
                  children: <Widget>[
                    Container(
                      width: 220,
                      height: 64,
                      decoration: BoxDecoration(
                        color: block,
                        borderRadius: BorderRadius.circular(PsRadius.pill),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: soft,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Three shelves of resting cards.
        shelf(PsSpace.shelfY - 40, cardSize: PsSpace.tileSize, count: 6),
        shelf(PsSpace.shelfY + PsSpace.shelfPitch - 40,
            cardSize: PsSpace.tileSize, count: 6),
        shelf(PsSpace.shelfY + PsSpace.shelfPitch * 2 - 40,
            cardSize: PsSpace.tileSize, count: 6),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.loading,
    required this.error,
    required this.entrance,
    required this.onAddSource,
    required this.onOpenFile,
  });

  final bool loading;
  final String? error;
  final double entrance;
  final VoidCallback onAddSource;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    final double rise = 24 * (1 - entrance);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          left: PsSpace.safeX,
          top: 300 + rise,
          width: 1100,
          child: Opacity(
            opacity: entrance,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(loading ? S.loading : S.emptyTitle, style: PsType.page),
                const SizedBox(height: 20),
                Text(
                  error ?? S.emptyBody,
                  style: PsType.body.copyWith(
                    height: 1.55,
                    color: error == null ? PsColor.textDim : PsColor.danger,
                  ),
                ),
                const SizedBox(height: 44),
                Row(
                  children: <Widget>[
                    PsButton(
                      label: S.addSource,
                      icon: Icons.add_rounded,
                      primary: true,
                      width: 240,
                      onSelect: onAddSource,
                    ),
                    const SizedBox(width: 20),
                    PsButton(
                      label: S.openFile,
                      icon: Icons.folder_open_rounded,
                      width: 240,
                      onSelect: onOpenFile,
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                const Row(
                  children: <Widget>[
                    _Capability(label: 'EMBY / JELLYFIN', value: '海报墙 · 续播'),
                    SizedBox(width: 28),
                    _Capability(label: 'IPTV', value: 'm3u · EPG'),
                    SizedBox(width: 28),
                    _Capability(label: 'OPENLIST / WEBDAV', value: '网盘直链'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: PsType.micro.copyWith(letterSpacing: 2, fontSize: 14)),
        const SizedBox(height: 6),
        Text(value, style: PsType.label.copyWith(color: PsColor.text.withValues(alpha: 0.8))),
      ],
    );
  }
}
