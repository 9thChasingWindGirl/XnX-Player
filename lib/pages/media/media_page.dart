import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/sources/media_source.dart';
import '../../data/store.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_ids.dart';
import '../../ui/core/motion_clock.dart';
import '../../ui/core/tv_focusable.dart';
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

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned(
              left: PsSpace.safeX,
              top: 110 + 14 * (1 - entrance),
              child: Opacity(
                opacity: entrance,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(S.tabLibrary, style: PsType.page),
                    const SizedBox(height: 8),
                    Text(
                      '${AppStore.instance.sources.length} 个来源  ·  ${items.length} 项内容',
                      style: PsType.micro.copyWith(fontSize: 16, letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: PsSpace.safeX,
              top: 236,
              width: 400,
              child: Opacity(
                opacity: entrance,
                child: _SourceRail(
                  filter: _filter,
                  onFilter: (String? id) => setState(() => _filter = id),
                  onAdd: () => setState(() => _dialogOpen = true),
                  onRemove: (String id) => AppStore.instance.removeSource(id),
                  onOpenFile: widget.onOpenFile,
                ),
              ),
            ),
            Positioned(
              left: 556,
              top: 226,
              width: 1268,
              height: 790,
              child: items.isEmpty
                  ? _EmptyLibrary(
                      loading: AppStore.instance.loading,
                      onAdd: () => setState(() => _dialogOpen = true),
                      onOpenFile: widget.onOpenFile,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 60, right: 20),
                      child: Wrap(
                        spacing: PsSpace.cardGap,
                        runSpacing: PsSpace.cardGap,
                        children: <Widget>[
                          for (final MediaItem item in items)
                            _GridCard(
                              item: item,
                              onPlay: widget.onPlay,
                              onOpen: widget.onOpenItem,
                            ),
                        ],
                      ),
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

class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.item,
    required this.onPlay,
    required this.onOpen,
  });

  final MediaItem item;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final bool channel = item.kind == MediaKind.channel;
    final double width = channel ? 300 : PsSpace.tileSize;
    final double height = channel ? 170 : PsSpace.tileSize;

    return TvFocusable(
      focusId: FocusIds.media(item.id),
      radius: PsRadius.card,
      accent: item.accentColor,
      highlightScale: 1.08,
      onSelect: () => item.isPlayable && item.kind != MediaKind.series
          ? onPlay(item)
          : onOpen(item),
      onLongSelect: () => onPlay(item),
      child: channel
          ? ChannelCard(item: item, width: width, height: height)
          : PosterCard(item: item, width: width, height: height),
    );
  }
}

class _SourceRail extends StatelessWidget {
  const _SourceRail({
    required this.filter,
    required this.onFilter,
    required this.onAdd,
    required this.onRemove,
    required this.onOpenFile,
  });

  final String? filter;
  final ValueChanged<String?> onFilter;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    final List<SourceConfig> sources = AppStore.instance.sources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          S.sources,
          style: PsType.micro.copyWith(fontSize: 15, letterSpacing: 2.4, color: PsColor.textFaint),
        ),
        const SizedBox(height: 14),
        _RailRow(
          label: '全部',
          selected: filter == null,
          onSelect: () => onFilter(null),
          badge: '${AppStore.instance.items.length}',
        ),
        for (final SourceConfig config in sources)
          _RailRow(
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
          width: 300,
          onSelect: onAdd,
        ),
        const SizedBox(height: 10),
        PsButton(
          label: S.openFile,
          icon: Icons.folder_open_rounded,
          width: 300,
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
      };
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.badge,
    this.onLongSelect,
  });

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
          width: 360,
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
