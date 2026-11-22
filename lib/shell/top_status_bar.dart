import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/notice_center.dart';
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
    this.onNotifications,
    this.notificationPanelOpen = false,
  });

  final int tabIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSearch;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  /// Opens the notification panel in the dock. Null while the shell has not
  /// wired it up yet, in which case the bell is simply not drawn.
  final VoidCallback? onNotifications;
  final bool notificationPanelOpen;

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
                _NotificationBell(
                  onSelect: widget.onNotifications,
                  open: widget.notificationPanelOpen,
                ),
                const SizedBox(width: 6),
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

/// Bell in the top chrome.
///
/// Present only when there is something to say — an unread result or a running
/// activity — so the bar stays quiet on a fresh install. A running activity
/// shows a dot (nothing to acknowledge yet); unread results show a count.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.onSelect, required this.open});

  final VoidCallback? onSelect;
  final bool open;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NoticeCenter.instance,
      builder: (BuildContext context, Widget? _) {
        final NoticeCenter center = NoticeCenter.instance;
        if (!center.hasAttention && !open) {
          return const SizedBox.shrink();
        }
        final bool busy = center.activeCount > 0;
        final int unread = center.unread;
        return Semantics(
          button: true,
          label: '通知',
          child: TvFocusable(
            radius: 4,
            showRing: false,
            onSelect: onSelect ?? () {},
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Icon(
                    open
                        ? Icons.notifications_rounded
                        : Icons.notifications_none_rounded,
                    size: 22,
                    color: busy ? PlexColor.amber : PlexColor.text,
                  ),
                  if (busy)
                    Positioned(
                      right: -2,
                      top: -1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: PlexColor.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  else if (unread > 0)
                    Positioned(
                      right: -7,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: PlexColor.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(
                            fontSize: 9,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF141416),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One window control. Square hover plate, no ring — these are chrome, and a
/// focus ring around a close button would be louder than the button itself.
class _WindowIcon extends StatelessWidget {  const _WindowIcon({
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

/// 铃铛下的简要通知浮层：最近几条的标题与相对时间，外加「查看全部」
/// 跳进控制中心-通知面板。只瞥一眼，不标已读——已读仍由完整面板处理。
class NoticeBriefPopup extends StatelessWidget {
  const NoticeBriefPopup({
    super.key,
    required this.notices,
    required this.onViewAll,
  });

  final List<Notice> notices;
  final VoidCallback onViewAll;

  static const int _maxRows = 5;

  String _timeOf(Notice notice) {
    final Duration age = DateTime.now().difference(notice.createdAt);
    if (age.inMinutes < 1) {
      return '刚刚';
    }
    if (age.inMinutes < 60) {
      return '${age.inMinutes} 分钟前';
    }
    if (age.inHours < 24) {
      return '${age.inHours} 小时前';
    }
    return '${notice.createdAt.month} 月 ${notice.createdAt.day} 日';
  }

  Color _kindColor(NoticeKind kind) {
    switch (kind) {
      case NoticeKind.success:
        return const Color(0xFF67C23A);
      case NoticeKind.warning:
        return PlexColor.amber;
      case NoticeKind.error:
        return const Color(0xFFF56C6C);
      case NoticeKind.info:
        return PlexColor.textDim;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Notice> rows = notices.take(_maxRows).toList(growable: false);
    return Container(
      width: 480,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF21C1C1F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PlexColor.line),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 22),
              child: Text(
                '暂无通知',
                style: TextStyle(fontSize: 15, color: PlexColor.textDim),
              ),
            )
          else
            for (final Notice notice in rows)
              TvFocusable(
                key: ValueKey<String>('${notice.id}-${notice.createdAt.millisecondsSinceEpoch}'),
                radius: 6,
                showRing: false,
                // 任何一条的落点都是完整面板：浮层是预览，不是操作面。
                onSelect: onViewAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: notice.active
                              ? PlexColor.amber
                              : _kindColor(notice.kind),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              notice.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: notice.read
                                    ? PlexColor.textDim
                                    : PlexColor.text,
                              ),
                            ),
                            if (notice.body.isNotEmpty)
                              Text(
                                notice.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: PlexColor.textDim,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _timeOf(notice),
                        style: const TextStyle(
                          fontSize: 12,
                          color: PlexColor.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (notices.length > _maxRows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Text(
                '还有 ${notices.length - _maxRows} 条…',
                style: const TextStyle(
                  fontSize: 12,
                  color: PlexColor.textDim,
                ),
              ),
            ),
          TvFocusable(
            radius: 6,
            showRing: false,
            onSelect: onViewAll,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: <Widget>[
                  Text(
                    '查看全部',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: PlexColor.text,
                    ),
                  ),
                  Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: PlexColor.textDim,
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
