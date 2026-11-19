import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/strings.dart';
import '../design/ps_tokens.dart';
import '../ui/core/focus_zone.dart';
import '../ui/core/tv_focusable.dart';

/// Top chrome: the two hub tabs on the left, the status cluster on the right
/// (search / settings / account / clock), exactly the four PS5 keeps up there.
class TopStatusBar extends StatelessWidget {
  const TopStatusBar({
    super.key,
    required this.tabIndex,
    required this.onTabSelected,
  });

  final int tabIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PsSpace.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PsSpace.safeX),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            FocusZone(
              id: 'tabs',
              child: Row(
                children: <Widget>[
                  _Tab(
                    label: S.tabGames,
                    selected: tabIndex == 0,
                    autofocus: false,
                    onSelect: () => onTabSelected(0),
                  ),
                  const SizedBox(width: PsSpace.xl),
                  _Tab(
                    label: S.tabMedia,
                    selected: tabIndex == 1,
                    onSelect: () => onTabSelected(1),
                  ),
                ],
              ),
            ),
            const Spacer(),
            const _StatusIcon(icon: Icons.search_rounded, label: '搜索'),
            const SizedBox(width: PsSpace.md),
            const _StatusIcon(icon: Icons.settings_outlined, label: '设置'),
            const SizedBox(width: PsSpace.md),
            const _Avatar(label: 'X'),
            const SizedBox(width: PsSpace.lg),
            const _Clock(),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bool lit = widget.selected || _focused;
    return TvFocusable(
      autofocus: widget.autofocus,
      focusScale: 1.0,
      showRing: false,
      showShine: false,
      radius: PsRadius.pill,
      onFocused: (bool focused) => setState(() => _focused = focused),
      onSelect: widget.onSelect,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedDefaultTextStyle(
            duration: PsMotion.base,
            curve: PsMotion.curve,
            style: PsType.section.copyWith(
              fontWeight: widget.selected ? FontWeight.w500 : FontWeight.w300,
              color: lit ? PsColor.text : PsColor.textDim,
              letterSpacing: 0.6,
            ),
            child: Text(widget.label),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: PsMotion.base,
            curve: PsMotion.curve,
            height: 2,
            width: widget.selected ? 34 : (_focused ? 18 : 0),
            decoration: BoxDecoration(
              color: PsColor.text,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatefulWidget {
  const _StatusIcon({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  State<_StatusIcon> createState() => _StatusIconState();
}

class _StatusIconState extends State<_StatusIcon> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: PsRadius.pill,
      focusScale: 1.08,
      showRing: false,
      showShine: false,
      debugLabel: widget.label,
      onFocused: (bool focused) => setState(() => _focused = focused),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _focused ? const Color(0x24FFFFFF) : const Color(0x00FFFFFF),
        ),
        child: Icon(widget.icon, size: 26, color: PsColor.text),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF3E5C8A), Color(0xFF1B2740)],
        ),
      ),
      child: Text(label, style: PsType.label.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String hh = _now.hour.toString().padLeft(2, '0');
    final String mm = _now.minute.toString().padLeft(2, '0');
    return Text('$hh:$mm', style: PsType.label.copyWith(letterSpacing: 0.6));
  }
}
