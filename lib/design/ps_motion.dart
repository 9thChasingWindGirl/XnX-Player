import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;

/// Physics-driven motion primitives.
///
/// Everything that *moves* in this UI is a spring chasing a target, not a
/// `Tween` with a duration. Springs are interruption-safe by construction: when
/// the player changes direction mid-flight the motion bends instead of
/// restarting, which is what makes held D-pad navigation feel fluid.
///
/// The integrator is the implicit semi-implicit Euler scheme used by the
/// reference console UI kit, so `frequency` maps to the same feel:
/// * focus moves          -> 18..22 (settles in 120..200 ms)
/// * panels and sheets    -> 12..14 (250..350 ms)
/// * colour / palette     -> 4..6   (slow, atmospheric)
class Spring {
  Spring({double value = 0, this.frequency = 20, this.damping = 1})
      : _value = value,
        _target = value;

  double _value;
  double _target;
  double _velocity;

  /// Angular frequency (rad/s). Higher is snappier.
  final double frequency;

  /// 1 = critically damped (no overshoot), < 1 = bouncy.
  final double damping;

  double get value => _value;
  double get target => _target;
  double get velocity => _velocity;

  set target(double value) => _target = value;

  bool get settled =>
      (_value - _target).abs() < 0.0005 && _velocity.abs() < 0.0005;

  void snap(double value) {
    _value = value;
    _target = value;
    _velocity = 0;
  }

  void update(double dt) {
    if (dt <= 0) {
      return;
    }
    final double f = 1 + 2 * dt * damping * frequency;
    final double oo = frequency * frequency;
    final double hoo = dt * oo;
    final double hhoo = dt * hoo;
    final double detInv = 1 / (f + hhoo);
    final double x = (f * _value + dt * _velocity + hhoo * _target) * detInv;
    final double v = (_velocity + hoo * (_target - _value)) * detInv;
    _value = x;
    _velocity = v;
  }
}

/// Four springs driving a rectangle. The gliding focus ring is one of these.
class SpringRect {
  SpringRect({double frequency = 20, double damping = 1, Rect? value})
      : _left = Spring(frequency: frequency, damping: damping),
        _top = Spring(frequency: frequency, damping: damping),
        _right = Spring(frequency: frequency, damping: damping),
        _bottom = Spring(frequency: frequency, damping: damping) {
    if (value != null) {
      snap(value);
    }
  }

  final Spring _left;
  final Spring _top;
  final Spring _right;
  final Spring _bottom;

  Rect get value => Rect.fromLTRB(_left.value, _top.value, _right.value, _bottom.value);

  bool get settled =>
      _left.settled && _top.settled && _right.settled && _bottom.settled;

  void snap(Rect rect) {
    _left.snap(rect.left);
    _top.snap(rect.top);
    _right.snap(rect.right);
    _bottom.snap(rect.bottom);
  }

  void setTarget(Rect rect) {
    _left.target = rect.left;
    _top.target = rect.top;
    _right.target = rect.right;
    _bottom.target = rect.bottom;
  }

  void update(double dt) {
    _left.update(dt);
    _top.update(dt);
    _right.update(dt);
    _bottom.update(dt);
  }
}

/// Per-channel colour spring: the backdrop takes the palette of the focused
/// cover and eases toward it, so the whole screen answers the selection.
class SpringColor {
  SpringColor(Color value, {double frequency = 5, double damping = 1})
      : _r = Spring(value: value.r, frequency: frequency, damping: damping),
        _g = Spring(value: value.g, frequency: frequency, damping: damping),
        _b = Spring(value: value.b, frequency: frequency, damping: damping),
        _a = Spring(value: value.a, frequency: frequency, damping: damping);

  final Spring _r;
  final Spring _g;
  final Spring _b;
  final Spring _a;

  Color get value => Color.fromARGB(_byte(_a.value), _byte(_r.value), _byte(_g.value), _byte(_b.value));

  void snap(Color color) {
    _r.snap(color.r);
    _g.snap(color.g);
    _b.snap(color.b);
    _a.snap(color.a);
  }

  void setTarget(Color color) {
    _r.target = color.r;
    _g.target = color.g;
    _b.target = color.b;
    _a.target = color.a;
  }

  void update(double dt) {
    _r.update(dt);
    _g.update(dt);
    _b.update(dt);
    _a.update(dt);
  }

  static int _byte(double unit) => (unit * 255).round().clamp(0, 255).toInt();
}

/// One-shot easing curves for things that arrive or leave rather than chase.
abstract final class Ease {
  static double linear(double t) => t.clamp(0.0, 1.0).toDouble();

  static double cubicOut(double t) {
    final double x = 1 - t.clamp(0.0, 1.0).toDouble();
    return 1 - x * x * x;
  }

  static double quintOut(double t) {
    final double x = 1 - t.clamp(0.0, 1.0).toDouble();
    return 1 - x * x * x * x * x;
  }

  static double cubicIn(double t) {
    final double x = t.clamp(0.0, 1.0).toDouble();
    return x * x * x;
  }

  static double smoothstep(double t) {
    final double x = t.clamp(0.0, 1.0).toDouble();
    return x * x * (3 - 2 * x);
  }

  static double backOut(double t) {
    final double x = t.clamp(0.0, 1.0).toDouble() - 1;
    return 1 + 2.70158 * x * x * x + 1.70158 * x * x;
  }

  static double sineInOut(double t) {
    final double x = t.clamp(0.0, 1.0).toDouble();
    return 0.5 - 0.5 * math.cos(math.pi * x);
  }
}

/// Slow breathing used on focus glow and idle artwork float. Amplitude stays
/// tiny: the screen is alive, not busy.
double breathe(double time, {double speed = 1.7, double phase = 0}) {
  return 0.5 + 0.5 * math.sin(time * speed + phase);
}

/// Damped oscillation used for the "soft refusal" nudge at the end of a rail.
double shake(double pulse, double time, {double amplitude = 14, double frequency = 9}) {
  return pulse * math.sin(time * frequency) * amplitude;
}

/// Staggered entrance: part `index` starts `offset` seconds after the one
/// before it and takes `duration` to arrive.
double stagger(double age, int index, {double offset = 0.08, double duration = 0.6}) {
  final double local = ((age - index * offset) / duration).clamp(0.0, 1.0).toDouble();
  return Ease.quintOut(local);
}

/// A decaying impulse: `trigger()` sets it to 1, it falls back to 0 on a spring.
/// Used for refusals (nudge) and for the little pop when a toggle flips.
class Pulse {
  Pulse({double frequency = 9}) : _spring = Spring(value: 0, frequency: frequency);

  final Spring _spring;

  double get value => _spring.value;

  void trigger() => _spring.snap(1);

  void update(double dt) {
    _spring.target = 0;
    _spring.update(dt);
  }
}

/// Linear interpolation helper that does not need `lerpDouble`.
double mix(double a, double b, double t) => a + (b - a) * t;

Offset mixOffset(Offset a, Offset b, double t) =>
    Offset(mix(a.dx, b.dx, t), mix(a.dy, b.dy, t));
