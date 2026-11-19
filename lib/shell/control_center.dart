import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../design/ps_tokens.dart';
import '../ui/core/focus_zone.dart';
import '../ui/core/tv_focusable.dart';
import 'control_center_items.dart';

/// PS5 Control Center: a translucent dock that slides up over the current
/// screen instead of navigating away from it.
class ControlCenter extends StatelessWidget {
  const ControlCenter({
    super.key,
    required this.open,
    required this.onSelect,
  });

  final bool open;
  final ValueChanged<CcItem> onSelect;

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
            child: _Dock(onSelect: onSelect),
          ),
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.onSelect});

  final ValueChanged<CcItem> onSelect;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 432,
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
              SizedBox(
                height: 216,
                child: FocusZone(
                  id: 'dock-cards',
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: PsSpace.safeX),
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
              const Spacer(),
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
                          _DockIcon(item: item, onSelect: onSelect),
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

class _DockCard extends StatefulWidget {
  const _DockCard({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<CcItem> onSelect;

  @override
  State<_DockCard> createState() => _DockCardState();
}

class _DockCardState extends State<_DockCard> {
  static const List<String> _titles = <String>['继续观看', '最近活动', '下载与上传'];
  static const List<String> _subtitles = <String>['星际拾荒者 · S02E06', '本周 3 项', '无进行中的任务'];
  static const List<List<Color>> _art = <List<Color>>[
    <Color>[Color(0xFF2B3B58), Color(0xFF101724)],
    <Color>[Color(0xFF3A2E4E), Color(0xFF171122)],
    <Color>[Color(0xFF1F3A38), Color(0xFF0C1615)],
  ];

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = _art[widget.index % _art.length];
    return TvFocusable(
      radius: PsRadius.cardLarge,
      focusScale: 1.04,
      onFocused: (bool focused) => setState(() => _focused = focused),
      onSelect: () => widget.onSelect(kControlCenterItems.first),
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
          border: Border.all(color: _focused ? const Color(0x59FFFFFF) : PsColor.hairline),
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
}

class _DockIcon extends StatefulWidget {
  const _DockIcon({required this.item, required this.onSelect});

  final CcItem item;
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
      focusScale: 1.08,
      showShine: false,
      onFocused: (bool focused) => setState(() => _focused = focused),
      onSelect: () => widget.onSelect(widget.item),
      debugLabel: 'dock:${widget.item.id}',
      child: AnimatedContainer(
        duration: PsMotion.fast,
        width: 132,
        height: 108,
        decoration: BoxDecoration(
          color: _focused ? const Color(0x1FFFFFFF) : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(PsRadius.card),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(widget.item.icon, size: 38, color: PsColor.text),
            const SizedBox(height: PsSpace.xs),
            Text(
              widget.item.label,
              style: PsType.micro.copyWith(
                fontSize: 15,
                color: _focused ? PsColor.text : PsColor.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
