import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/ps_tokens.dart';
import 'focus_shine.dart';
import 'focus_zone.dart';

/// Base focusable unit for the whole UI.
///
/// Deliberate details borrowed from the reference 10-foot client:
/// * activation happens on key **up**, so a held button never fires twice;
/// * mouse hover steals focus, so pointer and D-pad share one cursor;
/// * the focus ring is drawn by us (no Material ink), 2px white with a soft
///   outer glow and the slow diagonal shine.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onMenu,
    this.onFocused,
    this.autofocus = false,
    this.enabled = true,
    this.focusScale = 1.12,
    this.radius = PsRadius.card,
    this.showRing = true,
    this.showShine = true,
    this.debugLabel,
  });

  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onMenu;
  final ValueChanged<bool>? onFocused;
  final bool autofocus;
  final bool enabled;
  final double focusScale;
  final double radius;
  final bool showRing;
  final bool showShine;
  final String? debugLabel;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _node = FocusNode(debugLabel: widget.debugLabel);
  FocusEntry? _entry;
  bool _focused = false;
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.contextMenu) {
      if (widget.onMenu != null) {
        widget.onMenu!.call();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        widget.child,
        if (widget.showRing)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FocusRingPainter(
                  active: _focused,
                  radius: widget.radius,
                ),
              ),
            ),
          ),
        if (widget.showShine)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: FocusShine(active: _focused, radius: widget.radius),
            ),
          ),
      ],
    );

    if (widget.focusScale != 1.0) {
      content = AnimatedScale(
        scale: _focused ? widget.focusScale : 1.0,
        duration: PsMotion.base,
        curve: PsMotion.curve,
        child: content,
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
        widget.onFocused?.call(focused);
      },
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (event) {
          if (widget.enabled && !_focused) {
            _node.requestFocus();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onSelect : null,
          child: content,
        ),
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter({required this.active, required this.radius});

  final bool active;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) {
      return;
    }
    final Rect base = Rect.fromLTWH(-4, -4, size.width + 8, size.height + 8);
    final RRect ring = RRect.fromRectAndRadius(base, Radius.circular(radius + 3));

    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = PsColor.focusRing,
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = PsColor.focusGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) {
    return oldDelegate.active != active || oldDelegate.radius != radius;
  }
}
