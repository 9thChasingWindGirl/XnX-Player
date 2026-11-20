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
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
    required this.sources,
    required this.currentSourceId,
    required this.onPickSource,
    this.maximized = false,
  });

  final int tabIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSearch;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  /// The registered sources, for the switcher pill. Switching filters the
  /// home shelves to one source; managing them stays in the dock panel.
  final List<SourceOption> sources;
  final String? currentSourceId;
  final ValueChanged<String?> onPickSource;
  final bool maximized;

  @override
  State<TopStatusBar> createState() => _TopStatusBarState();
}

class _TopStatusBarState extends State<TopStatusBar> {
  static const List<String> _tabs = <String>[S.tabHome, S.tabLibrary, S.tabSettings];

  Timer? _clock;
  DateTime _now = DateTime.now();
  bool _pickerOpen = false;

  String _currentLabel() {
    if (widget.currentSourceId == null) {
      return S.allSources;
    }
    for (final SourceOption option in widget.sources) {
      if (option.id == widget.currentSourceId) {
        return option.label;
      }
    }
    return S.sourcesTitle;
  }

  void _pick(String? id) {
    setState(() => _pickerOpen = false);
    widget.onPickSource(id);
  }

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
          // Left: the source switcher. The pill names what the shelves
          // currently show; opening it lists every source plus "all".
          // Managing sources (add/edit/delete) stays in the dock panel.
          Positioned(
            left: PsSpace.safeX,
            top: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TvFocusable(
                  radius: PsRadius.pill,
                  showRing: false,
                  onSelect: () => setState(() => _pickerOpen = !_pickerOpen),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(PsRadius.pill),
                      color: PsColor.text.withValues(
                        alpha: _pickerOpen ? 0.18 : 0.10,
                      ),
                      border: Border.all(color: PsColor.text.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.source_rounded, size: 20, color: PsColor.text),
                        const SizedBox(width: 10),
                        Text(_currentLabel(), style: PsType.label.copyWith(fontSize: 19)),
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: _pickerOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: PsColor.text.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_pickerOpen)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xE6111420),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: PsColor.text.withValues(alpha: 0.14)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _SourceOptionRow(
                          label: S.allSources,
                          selected: widget.currentSourceId == null,
                          onPick: () => _pick(null),
                        ),
                        for (final SourceOption option in widget.sources)
                          _SourceOptionRow(
                            label: option.label,
                            selected: widget.currentSourceId == option.id,
                            onPick: () => _pick(option.id),
                          ),
                      ],
                    ),
                  ),
              ],
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


/// One selectable source in the switcher.
class SourceOption {
  const SourceOption(this.id, this.label);

  final String id;
  final String label;
}

class _SourceOptionRow extends StatelessWidget {
  const _SourceOptionRow({
    required this.label,
    required this.selected,
    required this.onPick,
  });

  final String label;
  final bool selected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: 10,
      onSelect: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: selected ? PsColor.accent : PsColor.text.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: PsType.label.copyWith(
                fontSize: 18,
                color: PsColor.text.withValues(alpha: selected ? 1 : 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
