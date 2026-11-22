import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/input/input_action.dart';
import '../../core/input/input_router.dart';
import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';

/// Full-screen reader for copy that does not fit where it is being shown.
///
/// The detail screen draws four lines of plot with an ellipsis, which is the
/// right call for scanning a grid of titles — but it swallows the rest silently,
/// and a viewer who wants the ending has no way to ask for it. The reference
/// build solves this with a generic text viewer: the plot block is a button,
/// and pressing it opens the whole text, scrollable, with a close button. This
/// is that window.
///
/// It is deliberately format-agnostic — a title, an eyebrow, a body — because
/// it is the same control for a plot, a file description or an error report.
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.title,
    required this.text,
    this.eyebrow,
  });

  /// Heading, usually the film or show name.
  final String title;

  /// The body. Long copy is expected; nothing is truncated here.
  final String text;

  /// Small label above the title, e.g. `剧情简介`.
  final String? eyebrow;

  /// Opens the reader over the current route.
  ///
  /// Not `opaque`, so the page behind stays faintly visible through the scrim
  /// and the reader reads as a layer rather than a navigation.
  static Future<void> open(
    BuildContext context, {
    required String title,
    required String text,
    String? eyebrow,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: PsColor.scrim,
        transitionDuration: PsMotion.reveal,
        reverseTransitionDuration: PsMotion.base,
        pageBuilder: (BuildContext context, Animation<double> animation,
            Animation<double> secondary) {
          return ReaderPage(title: title, text: text, eyebrow: eyebrow);
        },
        transitionsBuilder: (BuildContext context, Animation<double> animation,
            Animation<double> secondary, Widget child) {
          final Animation<double> eased =
              CurvedAnimation(parent: animation, curve: PsMotion.out);
          return FadeTransition(
            opacity: eased,
            child: SlideTransition(
              // A 2% rise: enough to read as "coming forward", small enough
              // that the text does not swim while it fades in.
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(eased),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final ScrollController _scroll = ScrollController();
  InputSubscription? _input;

  @override
  void initState() {
    super.initState();
    // Subscribed last, so the reader gets first refusal on every key while it
    // is up — the page underneath must not page sideways behind it.
    _input = InputRouter.instance.subscribe(_onIntent, name: 'reader');
  }

  @override
  void dispose() {
    _input?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _close() {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      unawaited(navigator.maybePop());
    }
  }

  /// Scrolls by a fraction of the viewport. Arrow keys nudge, PageUp/PageDown
  /// take most of a screen — the same split the detail page uses.
  void _scrollBy(double screens) {
    if (!_scroll.hasClients) {
      return;
    }
    final ScrollPosition position = _scroll.position;
    final double delta = position.viewportDimension * screens;
    final double target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target == position.pixels) {
      return;
    }
    _scroll.animateTo(
      target,
      duration: PsMotion.base,
      curve: PsMotion.out,
    );
  }

  bool _onIntent(InputIntent intent) {
    if (intent.action == InputAction.back) {
      _close();
      return true;
    }
    if (intent.action == InputAction.navigateUp) {
      _scrollBy(-0.28);
      return true;
    }
    if (intent.action == InputAction.navigateDown) {
      _scrollBy(0.28);
      return true;
    }
    if (intent.action == InputAction.pagePrev) {
      _scrollBy(-0.85);
      return true;
    }
    if (intent.action == InputAction.pageNext) {
      _scrollBy(0.85);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: math.min(screen.width * 0.08, 72),
          vertical: 48,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _header(),
                const SizedBox(height: 20),
                ConstrainedBox(
                  // Short copy keeps the dialog tight; long copy scrolls
                  // instead of pushing the header off screen.
                  constraints: BoxConstraints(maxHeight: screen.height * 0.62),
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.only(right: 20),
                      child: Text(
                        widget.text,
                        style: PsType.body.copyWith(
                          fontSize: 23,
                          height: 1.85,
                          color: PsColor.text.withValues(alpha: 0.88),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  '↑↓ 滚动 · PageUp/PageDown 翻页 · Esc 关闭',
                  style: PsType.micro.copyWith(
                    color: PsColor.textDisabled,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final String? eyebrow = widget.eyebrow;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (eyebrow != null && eyebrow.isNotEmpty) ...<Widget>[
                Text(
                  eyebrow,
                  style: PsType.eyebrow.copyWith(
                    color: PsColor.textFaint,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PsType.section.copyWith(
                  fontSize: 30,
                  height: 1.25,
                  color: PsColor.text,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        _CloseButton(onTap: _close),
      ],
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PsMotion.fast,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _hover ? PsColor.surfaceHigh : PsColor.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: _hover ? PsColor.hairline : Colors.transparent,
            ),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 20,
            color: _hover ? PsColor.text : PsColor.textDim,
          ),
        ),
      ),
    );
  }
}
