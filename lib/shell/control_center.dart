import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../design/ps_tokens.dart';
import '../ui/core/focus_zone.dart';
import '../ui/core/tv_focusable.dart';
import 'control_center_items.dart';

/// PS5 Control Center: a translucent dock that slides up over the current
/// screen instead of navigating away from it.
///
/// Activating an entry either switches tab, opens search, or — the common case —
/// raises an inline panel [panel] in place of the three highlight cards. The
/// dock stays up while a panel is open, which is the behaviour that makes a
/// control center useful: change one thing, keep watching.
class ControlCenter extends StatelessWidget {
  const ControlCenter({
    super.key,
    required this.open,
    required this.onSelect,
    required this.panel,
    required this.activeId,
  });

  final bool open;
  final ValueChanged<CcItem> onSelect;

  /// Panel content for the currently open dock entry, or null for the cards.
  final Widget? panel;

  /// Id of the entry whose panel is open, so the icon can stay lit.
  final String? activeId;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      excluding: !open,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedSlide(
          offset: open ? Offset.zero : const Offset(0, 1),
          duration: PsMotion.slow,
          curve: PsMotion.out,
          child: AnimatedOpacity(
            opacity: open ? 1 : 0,
            duration: PsMotion.base,
            curve: PsMotion.curve,
            child: _Dock(onSelect: onSelect, panel: panel, activeId: activeId),
          ),
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.onSelect, required this.panel, required this.activeId});

  final ValueChanged<CcItem> onSelect;
  final Widget? panel;
  final String? activeId;

  static const double _closedHeight = 432;
  static const double _openHeight = 596;

  /// Height the body is laid out at, whether or not the dock has finished
  /// growing. 596 - 24 - 12 - 132 - 8.
  static const double _bodyHeight = 420;

  @override
  Widget build(BuildContext context) {
    final Widget? body = panel;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        // The dock grows upwards for a panel; the icon row keeps its place so
        // the thing you just pressed does not move out from under the cursor.
        child: AnimatedContainer(
          duration: PsMotion.base,
          curve: PsMotion.out,
          height: body == null ? _closedHeight : _openHeight,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xCC0A0B10), Color(0xF207080D)],
            ),
            border: Border(top: BorderSide(color: PsColor.hairline)),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: PsSpace.lg),
              Expanded(
                // The dock grows when a panel opens. While that height is
                // animating the body is already laid out at full size, so it is
                // clipped from the top instead of overflowing: an OverflowBox
                // keeps the rows at their real size and the ClipRect hides the
                // part that has not been revealed yet.
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.bottomCenter,
                    minHeight: 0,
                    maxHeight: _bodyHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: PsSpace.safeX),
                      child: body ?? _DockCards(onSelect: onSelect),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: PsSpace.sm),
              SizedBox(
                height: 132,
                child: FocusZone(
                  id: 'dock-icons',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PsSpace.safeX),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        for (final CcItem item in kControlCenterItems)
                          _DockIcon(
                            item: item,
                            active: item.id == activeId,
                            onSelect: onSelect,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: PsSpace.xs),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three highlight cards shown when no panel is open.
///
/// Each card names the dock entry it opens; they used to all fire the same
/// item, which is the sort of placeholder that makes a UI feel dead.
class _DockCards extends StatelessWidget {
  const _DockCards({required this.onSelect});

  final ValueChanged<CcItem> onSelect;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: 216,
        child: FocusZone(
          id: 'dock-cards',
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (BuildContext context, int index) {
              return const SizedBox(width: PsSpace.md);
            },
            itemBuilder: (BuildContext context, int index) {
              return _DockCard(index: index, onSelect: onSelect);
            },
          ),
        ),
      ),
    );
  }
}

class _DockCard extends StatefulWidget {
  const _DockCard({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<CcItem> onSelect;

  @override
  State<_DockCard> createState() => _DockCardState();
}

class _DockCardState extends State<_DockCard> {
  static const List<String> _titles = <String>['继续观看', '媒体来源', '通知'];
  static const List<String> _subtitles = <String>['接着上次的进度', '接入的后端与刷新', '连接错误与运行结果'];
  static const List<String> _targets = <String>['recent', 'sources', 'notifications'];
  static const List<List<Color>> _art = <List<Color>>[
    <Color>[Color(0xFF2B3B58), Color(0xFF101724)],
    <Color>[Color(0xFF1F3A38), Color(0xFF0C1615)],
    <Color>[Color(0xFF3A2E4E), Color(0xFF171122)],
  ];

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = _art[widget.index % _art.length];
    return TvFocusable(
      radius: PsRadius.cardLarge,
      highlightScale: 1.04,
      onFocused: (bool focused) => setState(() => _focused = focused),
      onSelect: _open,
      child: Container(
        width: 384,
        height: 216,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PsRadius.cardLarge),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: art,
          ),
          border: Border.all(
            color: _focused ? const Color(0x59FFFFFF) : PsColor.hairline,
          ),
        ),
        padding: const EdgeInsets.all(PsSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text(_titles[widget.index], style: PsType.card),
            const SizedBox(height: 4),
            Text(_subtitles[widget.index], style: PsType.micro),
          ],
        ),
      ),
    );
  }

  /// Routes through the dock entry with the same id, so a card and its icon can
  /// never drift apart — one table of behaviour, not two.
  void _open() {
    final CcItem? target = ccItemById(_targets[widget.index]);
    if (target != null) {
      widget.onSelect(target);
    }
  }
}

class _DockIcon extends StatefulWidget {
  const _DockIcon({required this.item, required this.active, required this.onSelect});

  final CcItem item;
  final bool active;
  final ValueChanged<CcItem> onSelect;

  @override
  State<_DockIcon> createState() => _DockIconState();
}

class _DockIconState extends State<_DockIcon> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: PsRadius.card,
      highlightScale: 1.08,
      showShine: false,
      onFocused: (bool focused) => setState(() => _focused = focused),
      onSelect: () => widget.onSelect(widget.item),
      debugLabel: 'dock:${widget.item.id}',
      child: AnimatedContainer(
        duration: PsMotion.fast,
        width: 132,
        height: 108,
        decoration: BoxDecoration(
          color: _focused
              ? const Color(0x1FFFFFFF)
              : widget.active
              ? const Color(0x14FFFFFF)
              : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(PsRadius.card),
          border: Border.all(
            color: widget.active
                ? PsColor.text.withValues(alpha: 0.28)
                : const Color(0x00000000),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              widget.item.icon,
              size: 38,
              color: _focused || widget.active ? PsColor.text : PsColor.textDim,
            ),
            const SizedBox(height: PsSpace.xs),
            Text(
              widget.item.label,
              style: PsType.micro.copyWith(
                fontSize: 15,
                color: _focused || widget.active ? PsColor.text : PsColor.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
