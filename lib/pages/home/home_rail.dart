import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../data/models/media_item.dart';
import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_ids.dart';
import '../../ui/core/motion_clock.dart';
import '../../ui/core/tv_focusable.dart';
import 'home_tile.dart';

/// One shelf of covers.
///
/// Geometry is the reference's: 196 px cards, 26 px gaps, the focused card
/// grows to 1.2 with its bottom-left corner pinned so the row keeps its
/// baseline, and the cards to its right slide over to make room. Scrolling is a
/// spring chasing a target column, so held D-pad movement blends instead of
/// stepping.
class HomeRail extends StatefulWidget {
  const HomeRail({
    super.key,
    required this.items,
    required this.focusedIndex,
    required this.active,
    required this.onFocus,
    required this.onSelect,
    this.onLongSelect,
    this.cardSize = PsSpace.tileSize,
    this.startIndex = 2,
  });

  final List<MediaItem> items;
  final int focusedIndex;

  /// Only the row the player is actually on is allowed to scroll; the others
  /// keep their position so returning to them feels like coming back.
  final bool active;

  final ValueChanged<int> onFocus;
  final ValueChanged<MediaItem> onSelect;
  final ValueChanged<MediaItem>? onLongSelect;
  final double cardSize;

  /// Which slot the focused card is pulled toward.
  final int startIndex;

  @override
  State<HomeRail> createState() => _HomeRailState();
}

class _HomeRailState extends State<HomeRail> {
  final Spring _scroll = Spring(value: 0, frequency: 12);
  final Map<String, Spring> _grow = <String, Spring>{};

  double _last = -1;

  static const double _designWidth = 1920;

  double get _pitch => widget.cardSize + PsSpace.cardGap;

  @override
  void didUpdateWidget(HomeRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) {
      _grow.removeWhere((String key, Spring _) =>
          !widget.items.any((MediaItem item) => item.id == key));
    }
  }

  Spring _growthFor(String id) =>
      _grow.putIfAbsent(id, () => Spring(value: 1, frequency: 20));

  double get _focusedGrow {
    final int index = widget.focusedIndex;
    if (index < 0 || index >= widget.items.length) {
      return 1;
    }
    return _growthFor(widget.items[index].id).value;
  }

  double _restLeft(int index) {
    final double baseline = PsSpace.safeX + index * _pitch;
    if (widget.focusedIndex >= 0 && index > widget.focusedIndex) {
      return baseline + widget.cardSize * (_focusedGrow - 1);
    }
    return baseline;
  }

  void _sync(double dt) {
    for (int i = 0; i < widget.items.length; i++) {
      _growthFor(widget.items[i].id).target =
          i == widget.focusedIndex ? PsSpace.cardGrow : 1;
    }

    if (widget.active && widget.focusedIndex >= 0) {
      final double pitch = _pitch;
      final double anchor = PsSpace.safeX + pitch * widget.startIndex;
      final double focusedLeft = PsSpace.safeX + widget.focusedIndex * pitch;
      final double contentRight = PsSpace.safeX + widget.items.length * pitch;
      final double maxScroll =
          math.max(0.0, contentRight + PsSpace.safeX - _designWidth);
      _scroll.target = (focusedLeft - anchor).clamp(0.0, maxScroll).toDouble();
    }

    if (dt <= 0) {
      return;
    }
    _scroll.update(dt);
    for (final Spring spring in _grow.values) {
      spring.update(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }
    final double height = widget.cardSize * PsSpace.cardGrow;

    return SizedBox(
      width: _designWidth,
      height: height,
      child: MotionBuilder(
        builder: (BuildContext context, double dt) {
          final MotionClock clock = MotionScope.of(context);
          if (clock.time != _last) {
            _last = clock.time;
            _sync(dt);
          }

          final List<Widget> cards = <Widget>[];
          for (int i = 0; i < widget.items.length; i++) {
            final MediaItem item = widget.items[i];
            final double grow = _growthFor(item.id).value;
            final double size = widget.cardSize * grow;
            final double left = _restLeft(i) - _scroll.value;
            // Cull off-screen cards: a 400-item folder should not build 400
            // image widgets every frame.
            if (left > _designWidth + 40 || left + size < -40) {
              continue;
            }
            cards.add(
              Positioned(
                left: left,
                top: height - size,
                width: size,
                height: size,
                child: TvFocusable(
                  key: ValueKey<String>(item.id),
                  focusId: FocusIds.media(item.id),
                  radius: PsRadius.card,
                  focusedRadius: PsRadius.cardFocused,
                  accent: item.accentColor,
                  onSelect: () => widget.onSelect(item),
                  onLongSelect:
                      widget.onLongSelect == null ? null : () => widget.onLongSelect!(item),
                  onFocused: (bool focused) {
                    if (focused) {
                      widget.onFocus(i);
                    }
                  },
                  child: PosterCard(
                    item: item,
                    width: size,
                    height: size,
                    focused: i == widget.focusedIndex,
                  ),
                ),
              ),
            );
          }

          return Stack(clipBehavior: Clip.hardEdge, children: cards);
        },
      ),
    );
  }
}
