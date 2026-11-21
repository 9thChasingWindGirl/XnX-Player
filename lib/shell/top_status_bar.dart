import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/strings.dart';
import '../design/ps_tokens.dart';
import '../ui/core/focus_zone.dart';
import '../ui/core/tv_focusable.dart';

/// Plex-style top chrome: wordmark, library switcher, flat text tabs, and the
/// window controls on the far right.
///
/// The previous bar centred the tabs and wrapped the source in a large pill.
/// Plex anchors everything left after the logo and keeps one line of quiet
/// 18 px text, so the banner underneath stays the loudest thing on screen.
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

  /// The registered sources, for the switcher. Switching filters the home
  /// shelves to one source; managing them stays in the dock panel.
  final List<SourceOption> sources;
  final String? currentSourceId;
  final ValueChanged<String?> onPickSource;
  final bool maximized;

  @override
  State<TopStatusBar> createState() => _TopStatusBarState();
}

class _TopStatusBarState extends State<TopStatusBar> {
  static const List<String> _tabs = <String>[S.tabHome, S.tabLibrary, S.tabSettings];
  static const double _margin = 64;

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
    // Flutter does not hit-test outside a render box, so the source menu needs
    // the box itself to be tall while it is open; otherwise only the strip
    // inside the bar answers to the pointer and every row below it is dead.
    final double boxHeight = _pickerOpen ? 420 : 96;
    return SizedBox(
      height: boxHeight,
      child: Stack(
        clipBehavior: Clip.none,
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
                      const Color(0xFF000000).withValues(alpha: 0.62),
                      const Color(0x00000000),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: _margin,
            right: _margin,
            top: 24,
            child: Row(
              children: <Widget>[
                const Text(
                  'XnX',
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: PlexColor.amber,
                  ),
                ),
                const SizedBox(width: 18),
                Container(width: 1, height: 22, color: PlexColor.line),
                const SizedBox(width: 18),
                TvFocusable(
                  radius: 4,
                  showRing: false,
                  onSelect: () => setState(() => _pickerOpen = !_pickerOpen),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: _pickerOpen ? 0.14 : 0.06),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: PlexColor.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.video_library_outlined,
                          size: 16,
                          color: PlexColor.textDim,
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            _currentLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.1,
                              fontWeight: FontWeight.w500,
                              color: PlexColor.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: PlexColor.textFaint,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 34),
                FocusZone(
                  id: 'tabs',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int i = 0; i < _tabs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 28),
                          child: TvFocusable(
                            radius: 4,
                            onSelect: () => widget.onTabSelected(i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    _tabs[i],
                                    style: TextStyle(
                                      fontSize: 18,
                                      height: 1.2,
                                      fontWeight: i == widget.tabIndex
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: i == widget.tabIndex
                                          ? PlexColor.text
                                          : PlexColor.textDim,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    width: 18,
                                    height: 2,
                                    color: i == widget.tabIndex
                                        ? PlexColor.amber
                                        : const Color(0x00000000),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                TvFocusable(
                  radius: 4,
                  showRing: false,
                  onSelect: widget.onSearch,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.search_rounded, size: 22, color: PlexColor.text),
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  _timeLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: PlexColor.textDim,
                  ),
                ),
                const SizedBox(width: 18),
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
          if (_pickerOpen)
            Positioned(
              left: _margin,
              top: 68,
              child: Container(
                width: 280,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xF21C1C1F),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: PlexColor.line),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 10)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
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
    return Semantics(
      button: true,
      label: label,
      child: TvFocusable(
        radius: 4,
        showRing: false,
        onSelect: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: PlexColor.textDim),
        ),
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
      radius: 4,
      showRing: false,
      onSelect: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_rounded : Icons.circle_outlined,
              size: 16,
              color: selected ? PlexColor.amber : PlexColor.textFaint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: selected ? PlexColor.text : PlexColor.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
