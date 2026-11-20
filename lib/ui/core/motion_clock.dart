import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// One ticker for the whole application.
///
/// Ten-foot UIs need dozens of things to move at once; giving each one its own
/// `AnimationController` means dozens of tickers, dozens of durations and no
/// shared notion of "this frame". Instead every animated widget reads [dt] from
/// this clock and advances its own springs — the same `update(dt)` / `draw()`
/// split the reference implementation uses.
class MotionClock extends ChangeNotifier {
  MotionClock({this.reduceMotion = false}) {
    _ticker = Ticker(_tick)..start();
  }

  late final Ticker _ticker;

  Duration _last = Duration.zero;
  double _time = 0;
  double _dt = 0;

  /// When true, decorative motion stops and transitions collapse to plain
  /// fades. Mirrors the console's "Reduce Motion" accessibility setting.
  bool reduceMotion;

  /// Seconds since start. Drives `breathe`, backdrop drift and idle float.
  double get time => _time;

  /// Seconds since the previous frame, clamped so a stalled frame (window
  /// drag, GC pause) cannot teleport a spring across the screen.
  double get dt => _dt;

  /// A duration in seconds, collapsed when reduce-motion is on.
  double scaled(double seconds) => reduceMotion ? 0.001 : seconds;

  void _tick(Duration elapsed) {
    final double raw = (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    _dt = raw.clamp(0.0, 1 / 30).toDouble();
    if (_dt <= 0) {
      return;
    }
    _time += _dt;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Exposes the clock to the tree. Depending on it rebuilds the caller once per
/// frame, which is exactly what an `update(dt)` loop wants.
class MotionScope extends InheritedNotifier<MotionClock> {
  const MotionScope({super.key, required MotionClock clock, required super.child})
      : super(notifier: clock);

  static MotionClock of(BuildContext context) {
    final MotionScope? scope = context.dependOnInheritedWidgetOfExactType<MotionScope>();
    if (scope == null || scope.notifier == null) {
      throw FlutterError('MotionScope is missing: wrap the app in MotionScope(clock: ...).');
    }
    return scope.notifier!;
  }

  static MotionClock? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.notifier;

  @override
  bool updateShouldNotify(MotionScope oldWidget) => notifier != oldWidget.notifier;
}

/// Rebuilds [builder] once per frame and hands it the frame delta.
///
/// A missing [MotionScope] is a wiring error and throws: a screen whose springs
/// silently stop moving is worse than a loud failure, because nothing on screen
/// says which of the two happened.
class MotionBuilder extends StatelessWidget {
  const MotionBuilder({super.key, required this.builder}) : _optional = false;

  /// Same, but a missing [MotionScope] means "no motion" rather than an error:
  /// [builder] runs once with `dt = 0` and the widget keeps its last frame.
  ///
  /// For per-frame work that is purely decorative — a ring gliding after a rail
  /// that scrolls, a breathe — so the widget can still be pumped on its own in
  /// a test, a golden or a preview. Anything that *has* to animate to be
  /// correct should use the strict constructor and say so.
  const MotionBuilder.optional({super.key, required this.builder})
      : _optional = true;

  final Widget Function(BuildContext context, double dt) builder;
  final bool _optional;

  @override
  Widget build(BuildContext context) {
    if (_optional) {
      final MotionClock? clock = MotionScope.maybeOf(context);
      return builder(context, clock?.dt ?? 0);
    }
    return builder(context, MotionScope.of(context).dt);
  }
}
