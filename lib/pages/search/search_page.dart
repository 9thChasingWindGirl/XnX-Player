import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/store.dart';
import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_ids.dart';
import '../../ui/core/focus_navigator.dart';
import '../../ui/core/focus_zone.dart';
import '../../ui/core/motion_clock.dart';
import '../../ui/core/text_entry.dart';
import '../../ui/core/tv_focusable.dart';
import '../home/home_tile.dart';

/// Full-width search sheet.
///
/// Console behaviour, not desktop behaviour: the field takes the keyboard the
/// moment the sheet opens, `↓` hands the ring to the results grid, `Esc` closes.
/// Results come from [AppStore.search], which is local — no backend round-trip
/// while typing, so the list never flickers between keystrokes.
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({
    super.key,
    required this.onPlay,
    required this.onOpen,
    required this.onClose,
  });

  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onOpen;
  final VoidCallback onClose;

  /// Zone id so the field can hand focus to the first result.
  static const String resultZone = 'search-results';

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _field = FocusNode(debugLabel: 'search-field');

  String _query = '';
  List<MediaItem> _results = const <MediaItem>[];
  double _age = 0;
  double _last = -1;

  @override
  void initState() {
    super.initState();
    _field.onKeyEvent = _onFieldKey;
    _field.addListener(_syncKeyboardOwnership);
  }

  @override
  void dispose() {
    _field.removeListener(_syncKeyboardOwnership);
    _field.dispose();
    _controller.dispose();
    TextEntry.active.value = false;
    super.dispose();
  }

  /// The shell stops translating arrows into focus moves while a text field
  /// owns the keyboard. That has to follow the field's focus, not the sheet's
  /// existence, otherwise `↓` would never reach the results.
  void _syncKeyboardOwnership() {
    TextEntry.active.value = _field.hasFocus;
  }

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _results.isNotEmpty) {
      final bool moved = FocusNavigator.focusIn(SearchOverlay.resultZone);
      return moved ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _results = AppStore.instance.search(value);
    });
  }

  void _open(MediaItem item) {
    if (item.isPlayable) {
      widget.onPlay(item);
    } else {
      widget.onOpen(item);
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
        }
        final double enter = Ease.quintOut((_age / PsMotion.panel).clamp(0.0, 1.0).toDouble());

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GestureDetector(
              onTap: widget.onClose,
              child: ColoredBox(
                color: const Color(0xFF000000).withValues(alpha: 0.62 * enter),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Opacity(
                opacity: enter,
                child: Transform.translate(
                  offset: Offset(0, -48 * (1 - enter)),
                  child: _sheet(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sheet(BuildContext context) {
    final bool typing = _query.trim().isNotEmpty;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PsBlur.dialog, sigmaY: PsBlur.dialog),
        child: Container(
          height: 764,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xF2090A11), Color(0xE605060C)],
            ),
            border: Border(bottom: BorderSide(color: PsColor.hairline)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(PsSpace.safeX, 92, PsSpace.safeX, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text(S.search, style: PsType.eyebrow),
                    const SizedBox(width: 20),
                    Text(
                      typing ? '${_results.length} 个结果' : '按标题、剧集或频道名检索',
                      style: PsType.micro.copyWith(fontSize: 15, letterSpacing: 1.2),
                    ),
                    const Spacer(),
                    Text(
                      '${S.hintBack}   ·   ↓ 进入结果',
                      style: PsType.micro.copyWith(fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 1180,
                  child: TextField(
                    controller: _controller,
                    focusNode: _field,
                    autofocus: true,
                    cursorColor: PsColor.text,
                    cursorWidth: 3,
                    style: PsType.hero.copyWith(fontSize: 44, height: 1.2),
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) {
                      if (_results.isNotEmpty) {
                        FocusNavigator.focusIn(SearchOverlay.resultZone);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: '搜索',
                      hintStyle: PsType.hero.copyWith(
                        fontSize: 44,
                        color: PsColor.textDisabled,
                      ),
                      contentPadding: const EdgeInsets.only(bottom: 14),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: PsColor.text.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: PsColor.text, width: 3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Expanded(child: _resultsArea(typing)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultsArea(bool typing) {
    if (_results.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            typing ? S.noResults : S.emptyBody,
            style: PsType.body.copyWith(fontSize: 22, height: 1.6),
          ),
        ),
      );
    }
    return FocusZone(
      id: SearchOverlay.resultZone,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Wrap(
          spacing: PsSpace.cardGap,
          runSpacing: PsSpace.cardGap,
          children: <Widget>[
            for (final MediaItem item in _results)
              TvFocusable(
                key: ValueKey<String>('search:${item.id}'),
                focusId: FocusIds.media(item.id),
                radius: PsRadius.card,
                accent: item.accentColor,
                highlightScale: 1.08,
                onSelect: () => _open(item),
                child: PosterCard(item: item, width: PsSpace.tileSize, height: PsSpace.tileSize),
              ),
          ],
        ),
      ),
    );
  }
}
