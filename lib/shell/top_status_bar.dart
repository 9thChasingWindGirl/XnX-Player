import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/strings.dart';
import '../design/ps_tokens.dart';
import '../ui/core/focus_zone.dart';
import '../ui/core/tv_focusable.dart';

/// Top chrome: hub tabs on the left, the status cluster on the right.
///
/// The tabs are focusable so the highlight can travel up from a shelf and land
/// on them — a detail that makes the whole screen feel like one surface instead
/// of a page with a static header.
class TopStatusBar extends StatefulWidget {
  const TopStatusBar({
    super.key,
    required this.tabIndex,
    required this.onTabSelected,
    required this.onSearch,
  });

  final int tabIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSearch;

  @override
  State<TopStatusBar> createState() => _TopStatusBarState();
}

class _TopStatusBarState extends State<TopStatusBar> {
  static const List<String> _tabs = <String>[S.tabHome, S.tabLibrary, S.tabSettings];

  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (Timer timer) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String get _timeLabel {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(_now.hour)}:${two(_now.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 120,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      const Color(0xFF000000).withValues(alpha: 0.55),
                      const Color(0x00000000),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: PsSpace.safeX,
            top: 30,
            child: FocusZone(
              id: 'tabs',
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < _tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 36),
                      child: TvFocusable(
                        radius: 14,
                        onSelect: () => widget.onTabSelected(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                          child: Text(
                            _tabs[i],
                            style: PsType.meta.copyWith(
                              fontSize: 26,
                              color: PsColor.text.withValues(
                                alpha: i == widget.tabIndex ? 1 : 0.55,
                              ),
                              fontWeight:
                                  i == widget.tabIndex ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: PsSpace.safeX,
            top: 26,
            child: Row(
              children: <Widget>[
                Text(_timeLabel, style: PsType.meta.copyWith(fontSize: 26)),
                const SizedBox(width: 26),
                TvFocusable(
                  radius: PsRadius.pill,
                  showRing: false,
                  onSelect: widget.onSearch,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.search_rounded, size: 26, color: PsColor.text),
                  ),
                ),
                const SizedBox(width: 12),
                TvFocusable(
                  radius: PsRadius.pill,
                  showRing: false,
                  onSelect: () => widget.onTabSelected(2),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.settings_rounded, size: 26, color: PsColor.text),
                  ),
                ),
                const SizedBox(width: 18),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PsColor.text.withValues(alpha: 0.14),
                    border: Border.all(color: PsColor.text.withValues(alpha: 0.24)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'R',
                    style: PsType.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
