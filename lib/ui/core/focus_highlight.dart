import 'package:flutter/widgets.dart';

import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';
import 'motion_clock.dart';

/// Callback used by focusables to publish where the one highlight should go.
typedef HighlightReporter = void Function(
  Object owner,
  Rect? rect,
  double radius,
  Color accent,
);

/// Lets any focusable, however deep in the tree, hand its rectangle to the one
/// highlight object that glides between items.
///
/// This is the single most visible difference between a list of boxes and a
/// console UI: the eye follows the ring, so it must be one continuous object
/// with momentum, never a border painted per item.
class FocusHighlightScope extends InheritedWidget {
  const FocusHighlightScope({
    super.key,
    required this.report,
    required this.stageKey,
    required super.child,
  });

  final HighlightReporter report;
  final GlobalKey stageKey;

  static FocusHighlightScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FocusHighlightScope>();

  @override
  bool updateShouldNotify(FocusHighlightScope oldWidget) =>
      report != oldWidget.report || stageKey != oldWidget.stageKey;
}

/// Hosts the content and draws the gliding highlight above it.
///
/// The stage defines the coordinate space: focusables report rectangles in
/// stage-local units (design units inside [TvScale]), so the ring keeps its
/// geometry at any window size or DPI.
class GlideFocusStage extends StatefulWidget {
  const GlideFocusStage({super.key, required this.child});

  final Widget child;

  @override
  State<GlideFocusStage> createState() => _GlideFocusStageState();
}

class _GlideFocusStageState extends State<GlideFocusStage> {
  final GlobalKey _stageKey = GlobalKey();
  final SpringRect _rect = SpringRect(frequency: 20);
  final Spring _opacity = Spring(value: 0, frequency: 22);
  final Spring _radius = Spring(value: PsRadius.card, frequency: 18);
  final SpringColor _accent = SpringColor(PsColor.focusRing, frequency: 8);

  Object? _owner;
  Rect? _target;
  bool _placed = false;
  double _lastTime = -1;

  void _report(Object owner, Rect? rect, double radius, Color accent) {
    if (rect == null) {
      if (identical(owner, _owner)) {
        _owner = null;
        _target = null;
        _opacity.target = 0;
      }
      return;
    }
    _owner = owner;
    _target = rect;
    _radius.target = radius;
    _accent.setTarget(accent);
    _opacity.target = 1;
    if (!_placed) {
      _rect.snap(rect);
      _opacity.snap(1);
      _accent.snap(accent);
      _radius.snap(radius);
      _placed = true;
    } else {
      _rect.setTarget(rect);
    }
  }

  void _advance(double dt) {
    _rect.update(dt);
    _radius.update(dt);
    _opacity.update(dt);
    _accent.update(dt);
  }

  @override
  Widget build(BuildContext context) {
    return FocusHighlightScope(
      report: _report,
      stageKey: _stageKey,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          KeyedSubtree(key: _stageKey, child: widget.child),
          Positioned.fill(
            child: IgnorePointer(
              child: MotionBuilder(
                builder: (BuildContext context, double dt) {
                  final MotionClock clock = MotionScope.of(context);
                  if (clock.time != _lastTime) {
                    _lastTime = clock.time;
                    _advance(dt);
                  }
                  if (_opacity.value < 0.01 || _target == null) {
                    return const SizedBox.shrink();
                  }
                  return CustomPaint(
                    painter: _GlidePainter(
                      rect: _rect.value,
                      radius: _radius.value,
                      accent: _accent.value,
                      opacity: _opacity.value.clamp(0.0, 1.0).toDouble(),
                      time: clock.time,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlidePainter extends CustomPainter {
  const _GlidePainter({
    required this.rect,
    required this.radius,
    required this.accent,
    required this.opacity,
    required this.time,
  });

  final Rect rect;
  final double radius;
  final Color accent;
  final double opacity;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    if (rect.isEmpty || opacity <= 0.01) {
      return;
    }
    final RRect ring = RRect.fromRectAndRadius(
      rect.inflate(PsFocus.ringGap),
      Radius.circular(radius + PsFocus.ringGap),
    );

    // Glow spills the focused item's own accent, not one global highlight
    // colour, and breathes slowly so the screen reads as lit rather than pasted.
    final double pulse = 0.72 + 0.28 * breathe(time, speed: 1.35);
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = PsFocus.glideGlowWidth
        ..color = accent.withValues(alpha: 0.26 * opacity * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, PsFocus.glideGlowBlur),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = PsFocus.ringWidth
        ..color = const Color(0xFFFFFFFF).withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_GlidePainter oldDelegate) {
    return oldDelegate.rect != rect ||
        oldDelegate.radius != radius ||
        oldDelegate.accent != accent ||
        oldDelegate.opacity != opacity ||
        (oldDelegate.time - time).abs() > 0.01;
  }
}

/// Turns a rect from a deep child into stage coordinates.
///
/// `localToGlobal(..., ancestor: stage)` is the only conversion that survives
/// the single `FittedBox` used for the 1920x1080 canvas: it walks the transform
/// chain but stops before the scale, so the result stays in design units.
Rect? rectInStage(GlobalKey stageKey, RenderObject? self) {
  final RenderObject? stage = stageKey.currentContext?.findRenderObject();
  if (stage is! RenderBox || self is! RenderBox) {
    return null;
  }
  if (!stage.attached || !self.attached || !self.hasSize) {
    return null;
  }
  final Offset topLeft = self.localToGlobal(Offset.zero, ancestor: stage);
  return topLeft & self.size;
}

/// Grow a rest rectangle the way a focused card grows.
///
/// [alignment] describes the anchor: `Alignment.bottomLeft` keeps the shelf
/// baseline and the left edge fixed while the card lifts and widens, which is
/// how the reference grows a cover. Getting this wrong leaves the ring visibly
/// off-centre from the artwork.
Rect grownRect(Rect rest, double scale, {Alignment alignment = Alignment.center}) {
  if (scale == 1.0) {
    return rest;
  }
  final double dw = rest.width * (scale - 1);
  final double dh = rest.height * (scale - 1);
  final double dx = (alignment.x + 1) / 2 * dw;
  final double dy = (alignment.y + 1) / 2 * dh;
  return Rect.fromLTWH(rest.left - dx, rest.top - dy, rest.width + dw, rest.height + dh);
}

/// Distance-fade used by the shelves: the focused row is fully lit, the row
/// above it dissolves, the row below dims to 55%.
double rowPresence(double distance) {
  final double near = (1 + distance * 2.5).clamp(0.0, 1.0).toDouble();
  final double far =
      distance > 0 ? 1 - 0.45 * distance.clamp(0.0, 1.0).toDouble() : 1.0;
  return near * far;
}

/// Small helper so callers do not import `dart:math` just for a clamp.
double clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

/// Eased 0..1 progress from a free-running age and a duration in seconds.
double progressOf(double age, double duration) {
  if (duration <= 0) {
    return 1;
  }
  return Ease.quintOut((age / duration).clamp(0.0, 1.0).toDouble());
}
