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
class MotionBuilder extends StatelessWidget {
  const MotionBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, double dt) builder;

  @override
  Widget build(BuildContext context) {
    return builder(context, MotionScope.of(context).dt);
  }
}
