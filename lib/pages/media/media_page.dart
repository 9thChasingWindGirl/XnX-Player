import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/sources/media_source.dart';
import '../../data/store.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_ids.dart';
import '../../ui/core/motion_clock.dart';
import '../../ui/core/tv_focusable.dart';
import '../../ui/core/tv_scale.dart';
import '../../ui/widgets/ps_button.dart';
import '../home/home_tile.dart';
import 'source_dialog.dart';

/// Library: backends on the left, a poster grid on the right.
///
/// One page handles every source because [MediaItem] is already normalized —
/// switching from an Emby poster wall to a WebDAV folder changes nothing but the
/// data behind the same cards.
class MediaPage extends StatefulWidget {
  const MediaPage({
    super.key,
    required this.onPlay,
    required this.onOpenItem,
    required this.onOpenFile,
  });

  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onOpenItem;
  final VoidCallback onOpenFile;

  @override
  State<MediaPage> createState() => MediaPageState();
}

class MediaPageState extends State<MediaPage> {
  /// Active genre chip, null = everything. Derived from the items' own
  /// Genres field, so local folders and Emby behave the same.
  String? _genre;
  String? _filter;
  bool _dialogOpen = false;
  double _age = 0;
  double _last = -1;

  /// Opened from the shell's empty-state CTA, so "add a source" works from the
  /// home screen without a second copy of the form.
  void openSourceDialog() {
    if (!mounted) {
      return;
    }
    setState(() => _dialogOpen = true);
  }

  /// Opens the grid filtered to one genre. The home screen's category chips
  /// land here, so "动作" means the same thing from either page.
  void openGenre(String? genre) {
    if (!mounted) {
      return;
    }
    setState(() {
      _genre = genre;
      _filter = null;
    });
  }

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_onStore);
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) {
      setState(() {});
    }
  }

  List<MediaItem> get _visible {
    final List<MediaItem> all = AppStore.instance.items
        .where((MediaItem item) => item.kind != MediaKind.season)
        .toList(growable: false);
    if (_filter == null) {
      return all;
    }
    return all.where((MediaItem item) => item.sourceId == _filter).toList(growable: false);
  }

  Future<void> _save(SourceConfig config) async {
    setState(() => _dialogOpen = false);
    await AppStore.instance.addSource(config);
  }

  @override
  Widget build(BuildContext context) {
    return MotionBuilder(
      builder: (BuildContext context, double dt) {
        final MotionClock clock = MotionScope.of(context);
        if (clock.time != _last) {
          _last = clock.time;
          _age += clock.scaled(dt);
        }
        final double entrance = (_age / 0.45).clamp(0.0, 1.0).toDouble();
        final List<MediaItem> items = _visible;
        final String? genre = _genre;
        // One filtered list, shared by the header, the grid and the chips, so
        // every count on this page answers the same question.
        final List<MediaItem> shown = genre == null
            ? items
            : items
                .where((MediaItem item) => item.genres.contains(genre))
                .toList(growable: false);
        // Seasons are children of a series, not library entries; the rail's
        // "all" badge now uses the same calibre as the header and the grid.
        final int allCount = AppStore.instance.items
            .where((MediaItem item) => item.kind != MediaKind.season)
            .length;

        // The shell scales the whole app from a 1920x1080 design canvas, but a
        // resized / non-16:9 window changes the *logical* canvas size. Derive
        // every region from it instead of hard-coding design pixels so the rail
        // and the grid keep filling the window at any aspect ratio.
        final double designW = TvScale.widthOf(context);
        final double designH = TvScale.heightOf(context);
        final double sx = designW / TvScale.designWidth;
        final double sy = designH / TvScale.designHeight;
        final double safeX = PsSpace.safeX * sx;
        final double railWidth = 400 * sx;
        final double gridLeft = safeX + railWidth + 60 * sx;
        final double gridWidth = designW - safeX - gridLeft;
        final double gridTop = 226 * sy;
        final double gridHeight = designH - gridTop - 64 * sy;

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned(
              left: safeX,
              top: (110 + 14 * (1 - entrance)) * sy,
              child: Opacity(
                opacity: entrance,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(S.tabLibrary, style: PsType.page),
                    const SizedBox(height: 8),
                    Text(
                      genre == null
                          ? '${AppStore.instance.sources.length} 个来源  ·  ${items.length} 项内容'
                          : '${AppStore.instance.sources.length} 个来源  ·  $genre ${shown.length} 项 / 共 ${items.length} 项',
                      style: PsType.micro.copyWith(fontSize: 16, letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: safeX,
              top: 236 * sy,
              width: railWidth,
              child: Opacity(
                opacity: entrance,
                child: _SourceRail(
                  width: railWidth,
                  allCount: allCount,
                  filter: _filter,
                  onFilter: (String? id) => setState(() => _filter = id),
                  onAdd: () => setState(() => _dialogOpen = true),
                  onRemove: (String id) => AppStore.instance.removeSource(id),
                  onOpenFile: widget.onOpenFile,
                ),
              ),
            ),
            Positioned(
              left: gridLeft,
              top: gridTop,
              width: gridWidth,
              height: gridHeight,
              child: items.isEmpty
                  ? _EmptyLibrary(
                      loading: AppStore.instance.loading,
                      onAdd: () => setState(() => _dialogOpen = true),
                      onOpenFile: widget.onOpenFile,
                    )
                  : _LibraryGrid(
                      items: items,
                      shown: shown,
                      pickedGenre: _genre,
                      onPickGenre: (String? value) => setState(() => _genre = value),
                      onPlay: widget.onPlay,
                      onOpen: widget.onOpenItem,
                    ),
            ),
            if (_dialogOpen)
              SourceDialog(
                onCancel: () => setState(() => _dialogOpen = false),
                onSave: _save,
              ),
          ],
        );
      },
    );
  }
}

class _GridCard extends StatefulWidget {
  const _GridCard({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onOpen,
  });

  final MediaItem item;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onOpen;

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  /// The card fills its grid cell exactly, so focus grows the artwork instead
  /// of the box. `highlightScale` must carry the same factor or the ring ends
  /// up floating outside the resting card — which is what "the ring is a bit
  /// away from the tile" was. 6 % is `CardLook::focus_scale` (`card.h:77`);
  /// anything larger starts eating the 26 px gutter between tiles.

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final MediaItem item = widget.item;
    final bool channel = item.kind == MediaKind.channel;
    // `double.infinity` resolves to the grid cell's tight constraints: the
    // artwork, the focus ring and the cell now share one rectangle at every
    // window size. A fixed `PsSpace.tileSize` here used to park a 196x196 card
    // in the top-left of a ~211x293 cell, which is the visible "misalignment"
    // that appeared after hovering or switching a genre.

    return TvFocusable(
      focusId: FocusIds.media(item.id),
      radius: PsRadius.card,
      focusedRadius: channel ? PsRadius.card : PsRadius.cardFocused,
      accent: item.accentColor,
      // A live-channel tile keeps its size (its logo is laid out to the box),
      // so its ring must hug the resting edge.
      highlightScale: channel ? 1.0 : PsCard.focusScale,
      pressScale: PsCard.pressScale,
      onFocused: (bool focused) {
        if (mounted && focused != _focused) {
          setState(() => _focused = focused);
        }
      },
      onSelect: () => item.isPlayable && item.kind != MediaKind.series
          ? widget.onPlay(item)
          : widget.onOpen(item),
      onLongSelect: () => widget.onPlay(item),
      child: channel
          ? ChannelCard(item: item, width: double.infinity, height: double.infinity)
          : PosterCard(
              item: item,
              width: double.infinity,
              height: double.infinity,
              focused: _focused,
            ),
    );
  }
}

class _SourceRail extends StatelessWidget {
  const _SourceRail({
    required this.width,
    required this.allCount,
    required this.filter,
    required this.onFilter,
    required this.onAdd,
    required this.onRemove,
    required this.onOpenFile,
  });

  /// Design-space width of the rail region, derived from the live canvas by
  /// the page so the rows and buttons grow with a resized window.
  final double width;

  /// Same calibre as the header: every non-season item, across all sources.
  final int allCount;
  final String? filter;
  final ValueChanged<String?> onFilter;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    // TMDB is configured in the same dialog but has no files, so it must not
    // appear as a library filter.
    final List<SourceConfig> sources = AppStore.instance.sources
        .where((SourceConfig config) => config.kind != SourceKind.tmdb)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          S.sources,
          style: PsType.micro.copyWith(fontSize: 15, letterSpacing: 2.4, color: PsColor.textFaint),
        ),
        const SizedBox(height: 14),
        _RailRow(
          width: width,
          label: '全部',
          selected: filter == null,
          onSelect: () => onFilter(null),
          badge: '$allCount',
        ),
        for (final SourceConfig config in sources)
          _RailRow(
            width: width,
            label: config.label,
            selected: filter == config.id,
            onSelect: () => onFilter(config.id),
            badge: _kindLabel(config.kind),
            onLongSelect: () => onRemove(config.id),
          ),
        const SizedBox(height: 18),
        PsButton(
          label: S.addSource,
          icon: Icons.add_rounded,
          width: width,
          onSelect: onAdd,
        ),
        const SizedBox(height: 10),
        PsButton(
          label: S.openFile,
          icon: Icons.folder_open_rounded,
          width: width,
          onSelect: onOpenFile,
        ),
        if (AppStore.instance.errors.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          Text(
            AppStore.instance.errors.first,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: PsType.micro.copyWith(fontSize: 14, color: PsColor.danger),
          ),
        ],
      ],
    );
  }

  static String _kindLabel(SourceKind kind) => switch (kind) {
        SourceKind.emby => 'EMBY',
        SourceKind.jellyfin => 'JELLYFIN',
        SourceKind.iptv => 'M3U',
        SourceKind.openlist => 'ALIST',
        SourceKind.webdav => 'DAV',
        SourceKind.local => '本地',
        SourceKind.directUrl => 'URL',
        SourceKind.tmdb => 'TMDB',
      };
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.width,
    required this.label,
    required this.selected,
    required this.onSelect,
    this.badge,
    this.onLongSelect,
  });

  final double width;
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final String? badge;
  final VoidCallback? onLongSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvFocusable(
        radius: 12,
        onSelect: onSelect,
        onLongSelect: onLongSelect,
        child: Container(
          width: width,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected
                ? PsColor.text.withValues(alpha: 0.14)
                : PsColor.text.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PsType.label.copyWith(
                    color: selected ? PsColor.text : PsColor.textDim,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (badge != null)
                Text(
                  badge!,
                  style: PsType.micro.copyWith(fontSize: 12, letterSpacing: 1.4),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.loading, required this.onAdd, required this.onOpenFile});

  final bool loading;
  final VoidCallback onAdd;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(loading ? S.loading : S.emptyTitle, style: PsType.section.copyWith(fontSize: 32)),
        const SizedBox(height: 14),
        Text(S.emptyBody, style: PsType.body.copyWith(fontSize: 22)),
        const SizedBox(height: 30),
        Row(
          children: <Widget>[
            PsButton(
              label: S.addSource,
              icon: Icons.add_rounded,
              primary: true,
              width: 220,
              onSelect: onAdd,
            ),
            const SizedBox(width: 16),
            PsButton(
              label: S.openFile,
              icon: Icons.folder_open_rounded,
              width: 220,
              onSelect: onOpenFile,
            ),
          ],
        ),
      ],
    );
  }
}


/// The library grid, Plex-style: a genre bar on top, then a lazy grid.
///
/// The eager `Wrap` built one card per title on every rebuild — a 2000-title
/// library paid for all of them whether they were on screen or not.
/// `GridView.builder` builds what is visible; the genre bar narrows the list
/// before that even happens.
class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.items,
    required this.shown,
    required this.pickedGenre,
    required this.onPickGenre,
    required this.onPlay,
    required this.onOpen,
  });

  /// Source-filtered but *genre-unfiltered* items. Chip counts are derived
  /// from this list, so they never depend on which genre happens to be picked.
  final List<MediaItem> items;

  /// The same list after the genre filter. Counts and the grid agree because
  /// both are handed down from the page rather than recomputed here.
  final List<MediaItem> shown;
  final String? pickedGenre;
  final ValueChanged<String?> onPickGenre;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final Map<String, int> counts = <String, int>{};
    for (final MediaItem item in items) {
      for (final String genre in item.genres) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    final List<String> genres = counts.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (genres.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _GenreChip(
                  key: const ValueKey<String>('全部'),
                  label: '全部',
                  count: items.length,
                  selected: pickedGenre == null,
                  onPick: () => onPickGenre(null),
                ),
                for (final String genre in genres)
                  _GenreChip(
                    key: ValueKey<String>(genre),
                    label: genre,
                    count: counts[genre] ?? 0,
                    selected: pickedGenre == genre,
                    onPick: () => onPickGenre(genre),
                  ),
              ],
            ),
          ),
        if (genres.isNotEmpty) const SizedBox(height: 14),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(bottom: 60, right: 20),
            // A cell is a square of at most tileSize + gap; the card fills it
            // (see _GridCard), so artwork, ring and cell share one rectangle.
            // The old 0.72 ratio made a ~211x293 cell hold a 196x196 card
            // parked in its top-left corner — the "hover misalignment" that
            // showed up after a resize or a genre switch.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: PsSpace.tileSize + PsSpace.cardGap,
              mainAxisSpacing: PsSpace.cardGap,
              crossAxisSpacing: PsSpace.cardGap,
              childAspectRatio: 1.0,
            ),
            itemCount: shown.length,
            itemBuilder: (BuildContext context, int index) => _GridCard(
              // Key by media id so a filter rebuild keeps each card's identity
              // and its TvFocusable focusId instead of handing a recycled slot
              // to a different title.
              key: ValueKey<String>(shown[index].id),
              item: shown[index],
              onPlay: onPlay,
              onOpen: onOpen,
            ),
          ),
        ),
      ],
    );
  }
}

/// One category chip. A count next to the name keeps the bar honest about
/// how much each filter actually holds.
class _GenreChip extends StatelessWidget {
  const _GenreChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onPick,
  });

  final String label;

  /// How many of the source-filtered items carry this genre. Shown next to
  /// the name so the chip states what the filter will actually yield.
  final int count;
  final bool selected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: TvFocusable(
        radius: PsRadius.pill,
        onSelect: onPick,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PsRadius.pill),
            color: selected
                ? PsColor.accent.withValues(alpha: 0.24)
                : PsColor.text.withValues(alpha: 0.07),
            border: Border.all(
              color: selected ? PsColor.accent : PsColor.text.withValues(alpha: 0.14),
            ),
          ),
          child: Text(
            '$label  $count',
            style: PsType.label.copyWith(
              fontSize: 17,
              color: PsColor.text.withValues(alpha: selected ? 1 : 0.72),
            ),
          ),
        ),
      ),
    );
  }
}
