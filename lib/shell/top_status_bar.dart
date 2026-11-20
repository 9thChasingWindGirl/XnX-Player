import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/strings.dart';
import '../design/ps_tokens.dart';
import '../ui/core/focus_zone.dart';
import '../ui/core/tv_focusable.dart';

/// Top chrome, rebuilt to the reference layout: the media-source entry on the
/// left, navigation and search centred, window controls on the right.
///
/// The source pill opens the dock's source panel — adding, editing and
/// switching all live in one place instead of a second list here. Window
/// controls are real buttons, not decorations: a desktop player that hides
/// its own close button behind a native title bar reads as unfinished.
class TopStatusBar extends StatefulWidget {
  const TopStatusBar({
    super.key,
    required this.tabIndex,
    required this.onTabSelected,
    required this.onSearch,
    required this.onOpenSources,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
    this.maximized = false,
  });

  final int tabIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSearch;
  final VoidCallback onOpenSources;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;
  final bool maximized;

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
          // Left: the media-source entry. One pill, one job.
          Positioned(
            left: PsSpace.safeX,
            top: 30,
            child: TvFocusable(
              radius: PsRadius.pill,
              showRing: false,
              onSelect: widget.onOpenSources,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(PsRadius.pill),
                  color: PsColor.text.withValues(alpha: 0.10),
                  border: Border.all(color: PsColor.text.withValues(alpha: 0.18)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.source_rounded, size: 20, color: PsColor.text),
                    const SizedBox(width: 10),
                    Text(S.sourcesTitle, style: PsType.label.copyWith(fontSize: 19)),
                  ],
                ),
              ),
            ),
          ),
          // Centre: navigation plus search, one cluster.
          Positioned(
            left: 0,
            right: 0,
            top: 30,
            child: Center(
              child: FocusZone(
                id: 'tabs',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                                fontWeight: i == widget.tabIndex
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    TvFocusable(
                      radius: PsRadius.pill,
                      showRing: false,
                      onSelect: widget.onSearch,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.search_rounded, size: 26, color: PsColor.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Right: clock, then real window controls.
          Positioned(
            right: PsSpace.safeX,
            top: 26,
            child: Row(
              children: <Widget>[
                Text(_timeLabel, style: PsType.meta.copyWith(fontSize: 26)),
                const SizedBox(width: 24),
                _WindowIcon(
                  icon: Icons.minimize_rounded,
                  label: S.minimize,
                  onSelect: widget.onMinimize,
                ),
                _WindowIcon(
                  icon: widget.maximized
                      ? Icons.filter_none_rounded
                      : Icons.crop_square_rounded,
                  label: widget.maximized ? S.restoreDown : S.maximize,
                  onSelect: widget.onToggleMaximize,
                ),
                _WindowIcon(
                  icon: Icons.close_rounded,
                  label: S.close,
                  onSelect: widget.onClose,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One window control. Square hover plate, no ring — these are chrome, and a
/// focus ring around a close button would be louder than the button itself.
class _WindowIcon extends StatelessWidget {
  const _WindowIcon({
    required this.icon,
    required this.label,
    required this.onSelect,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: 10,
      showRing: false,
      onSelect: onSelect,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22, color: PsColor.text.withValues(alpha: 0.82)),
      ),
    );
  }
}
