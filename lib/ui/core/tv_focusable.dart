import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/input/input_action.dart';
import '../../core/input/input_router.dart';
import '../../core/sound/sound_cue.dart';
import '../../core/sound/sound_manager.dart';
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
    this.pressScale = 1.0,
    this.highlightAlignment = Alignment.center,
    this.radius = PsRadius.card,
    this.focusedRadius,
    this.accent,
    this.reportHighlight = true,
    this.showRing = false,
    this.showShine = false,
    this.debugLabel,
    this.focusId,
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

  /// How far the item shrinks while held. `CardLook::press_scale` is 0.04 and
  /// `QuickActionStyle::press_scale` 0.06 (`card.h:78`, `quick_action.hpp:44`):
  /// a press has to be felt before the action fires, otherwise a controller's
  /// delay reads as a dropped input.
  ///
  /// This is the *fraction taken off*, so 0.04 means "scale to 0.96". It is
  /// applied on top of [highlightScale] and only while the item is actually
  /// being held, so a card that is focused but untouched stays grown.
  final double pressScale;

  /// Anchor used when growing the highlight rectangle, so it tracks artwork
  /// that grows from its bottom-left corner instead of its centre.
  final Alignment highlightAlignment;

  final double radius;

  /// Corner radius while focused. Null keeps the resting [radius], which is
  /// what every fixed-size control wants: a pill chip or a 6 px button must
  /// not suddenly be ringed at a card's 22 px corner.
  ///
  /// A card that is drawn larger at 22 still looks pinched; the reference rings
  /// the grown cover at 30 where the resting one is 22 (`aurora.cpp:503`), so
  /// anything that resizes itself should say so here.
  final double? focusedRadius;

  final Color? accent;
  final bool reportHighlight;

  /// Legacy per-item ring, kept for the rare surface outside a [GlideFocusStage].
  final bool showRing;
  final bool showShine;
  final String? debugLabel;

  /// Stable address, so focus can be returned to this exact item later
  /// (`FocusNavigator.focusById`). Built from [FocusIds] rather than typed by
  /// hand, and optional: an item without one still navigates, it just cannot
  /// be recalled by name.
  final String? focusId;

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
      id: widget.focusId,
      order: FocusRegistry.instance.nextOrder(),
      // The focus tree handles Enter/Space and the tap handler handles the
      // pointer; these exist so a gamepad, which produces neither, can still
      // press the item it just highlighted.
      activate: () {
        if (widget.enabled) {
          _select();
        }
      },
      menu: () {
        if (widget.enabled) {
          widget.onMenu?.call();
        }
      },
    );
    FocusRegistry.instance.register(_entry!);
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final FocusEntry? entry = _entry;
    if (entry == null) {
      return;
    }
    // A recycled list item can be handed a different address (the same widget
    // slot now showing a different episode). Re-point it in place so its
    // navigation slot survives; re-registering would push it to the end of the
    // registry and change what "first" means.
    if (oldWidget.focusId != widget.focusId) {
      FocusRegistry.instance.reindex(
        entry,
        id: widget.focusId,
        zoneId: FocusZone.idOf(context),
      );
    }
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

  /// The one place a press becomes both a sound and an action, so keyboard,
  /// pointer and gamepad cannot drift apart.
  void _select() {
    SoundManager.instance.play(SoundCue.select);
    widget.onSelect?.call();
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
      _focused ? (widget.focusedRadius ?? widget.radius) : widget.radius,
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
        setState(() => _pressed = true);
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        final bool fire = _pressed;
        setState(() => _pressed = false);
        if (fire) {
          _select();
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

    // Grow the artwork itself, not just the ring around it.
    //
    // `highlightScale` used to size the highlight rectangle only, so a focused
    // tile had a ring 8 % larger than its artwork — which is exactly what "the
    // ring sits a bit away from the card" looks like. Since the rect is measured
    // from the outermost render box (the MouseRegion above this transform), the
    // measurement stays at rest size and `_publish` maps it with the same
    // factor: ring and artwork land on the same edge, and shelves that grow
    // their box keep `highlightScale: 1.0` so nothing grows twice.
    //
    // The press multiplies that scale down. It is deliberately *not* folded
    // into the published rectangle: a 4 % shrink is below what the ring's own
    // 4 px stroke can show, and re-measuring mid-press would make the ring
    // twitch away from the edge it was just welded to.
    if (widget.highlightScale != 1.0 || widget.pressScale != 1.0) {
      final double held = _pressed ? 1.0 - widget.pressScale : 1.0;
      content = AnimatedScale(
        scale: (_focused ? widget.highlightScale : 1.0) * held,
        duration: _pressed ? PsMotion.fast : PsMotion.grow,
        curve: PsMotion.out,
        alignment: widget.highlightAlignment,
        child: content,
      );
    }

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
          // A pointer sweeping across a shelf would otherwise chirp on every
          // card it passes: hover is not navigation.
          if (!InputRouter.instance.device.value.points) {
            SoundManager.instance.play(SoundCue.focus);
          }
        } else if (widget.reportHighlight) {
          _highlight?.report(this, null, widget.radius, widget.accent ?? PsColor.focusRing);
        }
        widget.onFocused?.call(focused);
      },
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        // Focus follows *movement*, not presence. `onEnter` also fires when a
        // scrolling rail carries a new card under a stationary cursor — the
        // scroll moves focus, focus moves the scroll, and the shelf runs away
        // by itself. `onHover` only fires for real pointer motion, which cuts
        // that loop: the rail scrolls under the cursor until it settles, and
        // the cursor has to actually move to change the focus again.
        onHover: (PointerHoverEvent event) {
          // The pointer is now the device in use, which turns off the ring's
          // glide (see _publish) until a key or a pad is touched again.
          InputRouter.instance.notePointer();
          if (widget.enabled && !_focused) {
            _node.requestFocus();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // A click is also a pointer event: note it before acting so a press
          // that never entered (the cursor was already over the tile when the
          // pad was last used) still counts as the pointer being in charge.
          onTap: widget.enabled
              ? () {
                  InputRouter.instance.notePointer();
                  _select();
                }
              : null,
          onTapDown: widget.enabled && widget.pressScale != 1.0
              ? (TapDownDetails details) => setState(() => _pressed = true)
              : null,
          onTapUp: widget.pressScale != 1.0
              ? (TapUpDetails details) => setState(() => _pressed = false)
              : null,
          onTapCancel: widget.pressScale != 1.0
              ? () => setState(() => _pressed = false)
              : null,
          onLongPress: widget.enabled ? widget.onLongSelect : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              content,
              // Only the focused item pays for a per-frame tick: it keeps the
              // gliding ring welded to artwork that is itself still moving
              // (a rail scrolling under focus). Decorative, so it degrades to
              // a single build when the item is mounted outside the app — a
              // widget test, a golden — instead of failing the build.
              if (_focused && widget.reportHighlight)
                Positioned.fill(
                  child: IgnorePointer(
                    child: MotionBuilder.optional(
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
    const double gap = PsFocus.ringGap;
    final RRect ring = RRect.fromRectAndRadius(
      Rect.fromLTWH(-gap, -gap, size.width + gap * 2, size.height + gap * 2),
      Radius.circular(radius + gap),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = PsFocus.ringWidth
        ..color = PsColor.focusRing,
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = PsFocus.glowWidth
        ..color = PsColor.focusGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, PsFocus.glowBlur),
    );
  }

  @override
  bool shouldRepaint(_LocalRingPainter oldDelegate) =>
      oldDelegate.active != active || oldDelegate.radius != radius;
}
