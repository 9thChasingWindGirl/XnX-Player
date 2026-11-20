import 'input_action.dart';

/// Turns "this direction is being held" into steps: one immediately, then more,
/// and later faster.
///
/// This exists because of a device difference, not a preference. A keyboard
/// repeats all by itself — Windows feeds the app `KeyRepeatEvent`s at the user's
/// own repeat-rate setting, and adding a timer on top would step twice per
/// repeat. A gamepad has no such thing: holding the D-pad produces one press and
/// then silence, so the UI has to generate the cadence itself.
///
/// The numbers are upstream's (`core/held_step.hpp`): 350ms before the first
/// repeat, 110ms between the next six, then 50ms. Fast enough to cross a long
/// shelf, slow enough that a tap never reads as two.
class HeldRepeat {
  HeldRepeat({
    this.delay = 0.35,
    this.interval = 0.11,
    this.fastInterval = 0.05,
    this.fastAfter = 6,
  });

  /// Seconds held before the first repeat.
  final double delay;

  /// Seconds between the first repeats.
  final double interval;

  /// Seconds between the later ones.
  final double fastInterval;

  /// Repeats before the pace picks up.
  final int fastAfter;

  InputAction? _held;
  double _waited = 0;
  int _repeats = 0;

  /// What is being held right now, if anything.
  InputAction? get held => _held;

  /// True once the current hold has produced at least one repeat, so the caller
  /// can tell a deliberate tap from a held sweep (quieter cue, no glide).
  bool get isRepeating => _repeats > 0;

  /// Call once per frame with the currently held direction and the frame time.
  /// Returns the action to fire this frame, or null.
  InputAction? step(InputAction? held, double dt) {
    if (held != _held) {
      // A fresh press (or a switch from one direction straight into another):
      // act on it now, then start the clock.
      _held = held;
      _waited = 0;
      _repeats = 0;
      return held;
    }
    if (held == null) {
      return null;
    }
    _waited += dt;
    final double wait = _repeats == 0
        ? delay
        : (_repeats < fastAfter ? interval : fastInterval);
    if (_waited < wait) {
      return null;
    }
    _waited = 0;
    _repeats += 1;
    return held;
  }

  void reset() {
    _held = null;
    _waited = 0;
    _repeats = 0;
  }
}
