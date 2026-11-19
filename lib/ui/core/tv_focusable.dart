import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/ps_tokens.dart';
import 'focus_highlight.dart';
import 'focus_shine.dart';
import 'focus_zone.dart';
import 'motion_clock.dart';

/// Base focusable unit for the whole UI.
///
/// Deliberate details:
/// * activation happens on key **up**, so a held button never fires twice;
/// * mouse hover steals focus, so pointer and D-pad share one cursor;
/// * the item does **not** paint its own border. It publishes its rectangle to
///   the stage's single gliding highlight, which is what makes the focus read
///   as one object travelling between cards;
/// * while focused it re-publishes every frame, because the shelf under it is
///   itself spring-animated and the ring must stay welded to the artwork.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onMenu,
    this.onLongSelect,
    this.onAdjust,
    this.onFocused,
    this.autofocus = false,
    this.enabled = true,
    this.highlightScale = 1.0,
    this.highlightAlignment = Alignment.center,
    this.radius = PsRadius.card,
    this.accent,
    this.reportHighlight = true,
    this.showRing = false,
    this.showShine = false,
    this.debugLabel,
  });

  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onMenu;
  final VoidCallback? onLongSelect;

  /// When set, left/right are consumed by this item instead of moving focus:
  /// that is what makes a slider or a stepper adjustable with a D-pad.
  final ValueChanged<int>? onAdjust;

  final ValueChanged<bool>? onFocused;
  final bool autofocus;
  final bool enabled;

  /// How much the artwork grows when focused. Used only to grow the highlight
  /// rectangle: the card animates its own size, so the ring and the art can
  /// use independent spring stiffness.
  final double highlightScale;

  /// Anchor used when growing the highlight rectangle, so it tracks artwork
  /// that grows from its bottom-left corner instead of its centre.
  final Alignment highlightAlignment;

  final double radius;
  final Color? accent;
  final bool reportHighlight;

  /// Legacy per-item ring, kept for the rare surface outside a [GlideFocusStage].
  final bool showRing;
  final bool showShine;
  final String? debugLabel;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _node = FocusNode(debugLabel: widget.debugLabel);
  FocusEntry? _entry;
  FocusHighlightScope? _highlight;
  bool _focused = false;
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _highlight = FocusHighlightScope.maybeOf(context);
    _syncEntry();
  }

  void _syncEntry() {
    final FocusEntry? entry = _entry;
    if (entry != null) {
      FocusRegistry.instance.unregister(entry);
    }
    _entry = FocusEntry(
      node: _node,
      context: context,
      zoneId: FocusZone.idOf(context),
      order: FocusRegistry.instance.nextOrder(),
    );
    FocusRegistry.instance.register(_entry!);
  }

  @override
  void dispose() {
    final FocusEntry? entry = _entry;
    if (entry != null) {
      FocusRegistry.instance.unregister(entry);
    }
    _node.dispose();
    super.dispose();
  }

  void _publish() {
    final FocusHighlightScope? scope = _highlight;
    if (scope == null || !widget.reportHighlight || !mounted) {
      return;
    }
    final Rect? rest = rectInStage(scope.stageKey, context.findRenderObject());
    if (rest == null) {
      return;
    }
    scope.report(
      this,
      grownRect(rest, widget.highlightScale, alignment: widget.highlightAlignment),
      widget.radius,
      widget.accent ?? PsColor.focusRing,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled) {
      return KeyEventResult.ignored;
    }

    final bool activate = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.space;

    if (activate) {
      if (event is KeyDownEvent) {
        _pressed = true;
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        final bool fire = _pressed;
        _pressed = false;
        if (fire) {
          widget.onSelect?.call();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent && widget.onAdjust != null) {
      final LogicalKeyboardKey key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft) {
        widget.onAdjust!(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        widget.onAdjust!(1);
        return KeyEventResult.handled;
      }
    }

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.contextMenu) {
      if (widget.onMenu != null) {
        widget.onMenu!.call();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    Widget content = widget.child;

    if (widget.showShine && _focused) {
      content = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.radius),
                child: FocusShine(active: _focused, radius: widget.radius),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.showRing) {
      content = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LocalRingPainter(active: _focused, radius: widget.radius),
              ),
            ),
          ),
        ],
      );
    }

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onKeyEvent: _handleKey,
      onFocusChange: (bool focused) {
        if (!mounted || focused == _focused) {
          return;
        }
        setState(() => _focused = focused);
        if (focused) {
          _publish();
        } else if (widget.reportHighlight) {
          _highlight?.report(this, null, widget.radius, widget.accent ?? PsColor.focusRing);
        }
        widget.onFocused?.call(focused);
      },
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (PointerEnterEvent event) {
          if (widget.enabled && !_focused) {
            _node.requestFocus();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onSelect : null,
          onLongPress: widget.enabled ? widget.onLongSelect : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              content,
              // Only the focused item pays for a per-frame tick: it keeps the
              // gliding ring welded to artwork that is itself still moving.
              if (_focused && widget.reportHighlight)
                Positioned.fill(
                  child: IgnorePointer(
                    child: MotionBuilder(
                      builder: (BuildContext context, double dt) {
                        _publish();
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalRingPainter extends CustomPainter {
  const _LocalRingPainter({required this.active, required this.radius});

  final bool active;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) {
      return;
    }
    final RRect ring = RRect.fromRectAndRadius(
      Rect.fromLTWH(-4, -4, size.width + 8, size.height + 8),
      Radius.circular(radius + 4),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = PsColor.focusRing,
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = PsColor.focusGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(_LocalRingPainter oldDelegate) =>
      oldDelegate.active != active || oldDelegate.radius != radius;
}
