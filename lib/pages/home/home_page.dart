import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/store.dart';
import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_highlight.dart';
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
  const _Row(this.title, this.items);

  final String title;
  final List<MediaItem> items;
}

class _HomePageState extends State<HomePage> {
  final Spring _rowPosition = Spring(value: 0, frequency: 11);
  final List<int> _columns = <int>[];

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.heroItem.value = _shown;
      }
    });
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_onStore);
    super.dispose();
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

  List<_Row> _computeRows() {
    final AppStore store = AppStore.instance;
    final List<_Row> rows = <_Row>[];
    if (store.continueWatching.isNotEmpty) {
      rows.add(_Row(S.continueWatching, store.continueWatching));
    }
    if (store.recent.isNotEmpty) {
      rows.add(_Row(S.recentlyAdded, store.recent));
    }
    if (store.channels.isNotEmpty) {
      rows.add(_Row(S.liveChannels, store.channels));
    }
    return rows;
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
          _rowPosition.target = _row.toDouble();
          _rowPosition.update(dt);
          _transition = (_transition + clock.scaled(dt) / PsMotion.heroCrossFade)
              .clamp(0.0, 1.0)
              .toDouble();
        }

        if (_rows.isEmpty) {
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

        return Stack(
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
            ),
            for (int i = 0; i < _rows.length; i++)
              ..._shelf(
                index: i,
                row: _rows[i],
                active: i == row,
                column: _columns.length > i ? _columns[i] : 0,
                age: _age,
              ),
          ],
        );
      },
    );
  }

  List<Widget> _shelf({
    required int index,
    required _Row row,
    required bool active,
    required int column,
    required double age,
  }) {
    final double distance = index - _rowPosition.value;
    final double presence = rowPresence(distance) * stagger(age, 3 + index, offset: 0.09);
    if (presence <= 0.012) {
      return const <Widget>[];
    }
    final double cardTop = PsSpace.shelfY + distance * PsSpace.shelfPitch;
    final double railTop =
        cardTop - (PsSpace.tileSize * PsSpace.cardGrow - PsSpace.tileSize);

    return <Widget>[
      Positioned(
        left: 0,
        top: railTop,
        width: 1920,
        height: PsSpace.tileSize * PsSpace.cardGrow + 40,
        child: Opacity(
          opacity: presence,
          child: FocusZone(
            id: 'home-row-$index',
            child: HomeRail(
              items: row.items,
              focusedIndex: active ? column.clamp(0, row.items.length - 1).toInt() : -1,
              active: active,
              onFocus: (int value) => _focusAt(index, value),
              onSelect: widget.onOpenItem,
              onLongSelect: widget.onPlay,
            ),
          ),
        ),
      ),
      Positioned(
        left: PsSpace.safeX,
        top: cardTop - 78,
        child: Opacity(
          opacity: presence,
          child: Text(
            row.title,
            style: PsType.section.copyWith(
              color: PsColor.text.withValues(alpha: active ? 0.96 : 0.6),
            ),
          ),
        ),
      ),
    ];
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
