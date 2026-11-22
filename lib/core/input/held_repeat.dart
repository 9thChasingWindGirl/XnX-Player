import 'dart:math' as math;

import 'input_action.dart';

/// Turns "this direction is being held" into steps: one immediately, then more
/// often as the hold goes on.
///
/// This exists because of a device difference, not a preference. A keyboard
/// repeats all by itself — Windows feeds the app `KeyRepeatEvent`s at the user's
/// own repeat-rate setting, and adding a timer on top would step twice per
/// repeat. A gamepad has no such thing: holding the D-pad produces one press and
/// then silence, so the UI has to generate the cadence itself.
///
/// The shape of the cadence is the reference build's list scrolling
/// (`GUIBaseContainer::OnAction`): from 100 ms the list moves at a floor of ten
/// items a second, accelerating linearly to thirty a second at 3 s, with
/// fractional steps carried between frames rather than rounded away.
///
/// A fixed ladder — 350 ms, then 110, then 50 — was the earlier shape, and it
/// reads badly at both ends: a third of a second of nothing before the second
/// step, then a hard ceiling of twenty items a second that a long shelf reaches
/// while still crawling. Continuous accumulation has neither cliff, and the
/// carry is what keeps it honest: at 0.48 steps per frame the movement still
/// averages out to the requested rate instead of half speed.
class HeldRepeat {
  HeldRepeat({
    this.delay = 0.1,
    this.rampUp = 2.9,
    this.slowRate = 10,
    this.fastRate = 30,
  });

  /// Seconds before a hold starts repeating at all.
  ///
  /// The first press is delivered by [step] itself, so this is the pause
  /// between that step and the start of the sweep.
  final double delay;

  /// Seconds over which the rate climbs from [slowRate] to [fastRate].
  final double rampUp;

  /// Steps per second at the start of a sweep. Also the floor.
  final double slowRate;

  /// Steps per second at full tilt.
  final double fastRate;

  InputAction? _held;
  double _elapsed = 0;

  /// Fractional steps not yet spent. Never reset mid-hold: that is precisely
  /// what would quantise the sweep back into a ladder.
  double _credit = 0;

  /// What is being held right now, if anything.
  InputAction? get held => _held;

  /// True once the current hold has started sweeping, so the caller can tell a
  /// deliberate tap from a held sweep (quieter cue, no glide).
  bool get isRepeating => _elapsed > delay;

  /// Call once per frame with the currently held direction and the frame time.
  /// Returns the action to fire this frame, or null.
  InputAction? step(InputAction? held, double dt) {
    if (held != _held) {
      // A fresh press (or a switch from one direction straight into another):
      // act on it now, then start the clock.
      _held = held;
      _elapsed = 0;
      _credit = 0;
      return held;
    }
    if (held == null) {
      return null;
    }

    _elapsed += dt;
    if (_elapsed < delay) {
      return null;
    }

    // Speed ramps from the floor towards the ceiling, then sits there.
    final double ramp = ((_elapsed - delay) / rampUp).clamp(0.0, 1.0);
    final double rate = math.max(slowRate, fastRate * ramp);

    _credit += rate * dt;
    if (_credit < 1) {
      return null;
    }
    // One step per frame at most, and drop any backlog: after a stall (a route
    // transition, a paused isolate) the alternative is a burst of steps the
    // user never asked for.
    _credit = math.min(_credit - 1, 1);
    return held;
  }

  void reset() {
    _held = null;
    _elapsed = 0;
    _credit = 0;
  }
}
