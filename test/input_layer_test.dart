import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/core/input/held_repeat.dart';
import 'package:xnx_player/core/input/input_action.dart';
import 'package:xnx_player/core/input/keymap.dart';
import 'package:xnx_player/player/osd_keys.dart';

KeyEvent _key(LogicalKeyboardKey key) => KeyDownEvent(
  timeStamp: Duration.zero,
  physicalKey: const PhysicalKeyboardKey(0),
  logicalKey: key,
);

/// Feeds [seconds] of 10ms frames into [repeat] and returns how many steps fired.
int _run(HeldRepeat repeat, InputAction? held, double seconds) {
  int steps = 0;
  const double dt = 0.01;
  for (double t = 0; t < seconds; t += dt) {
    if (repeat.step(held, dt) != null) {
      steps += 1;
    }
  }
  return steps;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HeldRepeat', () {
    test('a tap fires at once and nothing follows inside the first fifth', () {
      final HeldRepeat repeat = HeldRepeat();
      expect(repeat.step(InputAction.navigateRight, 0.016), InputAction.navigateRight);
      expect(repeat.isRepeating, isFalse);
      // The first press is free; the sweep starts at 100 ms and needs a full
      // step of credit before it moves again.
      expect(_run(repeat, InputAction.navigateRight, 0.19), 0);
      expect(_run(repeat, InputAction.navigateRight, 0.1), greaterThan(0));
    });

    test('nothing is emitted once the direction is released', () {
      final HeldRepeat repeat = HeldRepeat();
      repeat.step(InputAction.navigateDown, 0.016);
      expect(_run(repeat, null, 1.0), 0);
      // A new press after a release is immediate again — the delay is per hold,
      // not a standing cost on every tap.
      expect(repeat.step(InputAction.navigateDown, 0.016), InputAction.navigateDown);
    });

    test('changing direction steps at once instead of waiting out the delay', () {
      final HeldRepeat repeat = HeldRepeat();
      repeat.step(InputAction.navigateLeft, 0.016);
      expect(_run(repeat, InputAction.navigateLeft, 0.5), greaterThan(0));
      expect(repeat.step(InputAction.navigateUp, 0.016), InputAction.navigateUp);
    });

    test('the sweep starts at ten a second and climbs to thirty', () {
      // Upstream's list scrolling: a floor of 10 items/s from 100 ms, linear to
      // 30 items/s at 3 s. Checked as cumulative counts on fresh instances,
      // which is the only way to see the ramp rather than one instant.
      int steps(double seconds) {
        final HeldRepeat repeat = HeldRepeat();
        repeat.step(InputAction.navigateRight, 0.016);
        return _run(repeat, InputAction.navigateRight, seconds);
      }

      final int firstSecond = steps(1);
      final int twoSeconds = steps(2);
      final int threeSeconds = steps(3);

      // 10/s floor, minus the 100 ms the ramp spends getting started.
      expect(firstSecond, inInclusiveRange(7, 11));
      // Each second covers more ground than the one before: that is the ramp.
      expect(twoSeconds - firstSecond, greaterThan(firstSecond));
      expect(threeSeconds, greaterThan(twoSeconds + firstSecond));
    });

    test('fractional steps are carried, not rounded away', () {
      // At 16 ms frames the 10/s floor is 0.16 steps per frame; rounding that
      // down every frame would produce nothing at all, and rounding it up would
      // produce sixty a second. The carry is what makes the rate true.
      final HeldRepeat repeat = HeldRepeat();
      repeat.step(InputAction.navigateRight, 0.016);
      int steps = 0;
      for (int i = 0; i < 125; i++) {
        if (repeat.step(InputAction.navigateRight, 0.016) != null) {
          steps += 1;
        }
      }
      // Two seconds of 16 ms frames lands in the low twenties: below the 30/s
      // ceiling because the ramp is still climbing, and far above what a
      // per-frame floor of 0.16 steps would give if it were rounded down.
      expect(steps, inInclusiveRange(18, 28));
    });

    test('reset drops the hold and the repeat count', () {
      final HeldRepeat repeat = HeldRepeat();
      repeat.step(InputAction.navigateUp, 0.016);
      _run(repeat, InputAction.navigateUp, 0.5);
      expect(repeat.isRepeating, isTrue);
      repeat.reset();
      expect(repeat.isRepeating, isFalse);
      expect(repeat.held, isNull);
      expect(repeat.step(InputAction.navigateUp, 0.016), InputAction.navigateUp);
    });
  });

  group('hold rules', () {
    test('a press becomes a hold past the shared threshold', () {
      const InputIntent tap = InputIntent.action(
        InputAction.confirm,
        device: InputDevice.gamepad,
      );
      expect(tap.isHold, isFalse);

      const InputIntent held = InputIntent.action(
        InputAction.confirm,
        device: InputDevice.gamepad,
        held: Duration(milliseconds: 600),
      );
      expect(held.isHold, isTrue);
      expect(kHoldMenuAfter, const Duration(milliseconds: 550));
    });
  });

  group('device rules', () {
    test('only continuous actions repeat', () {
      expect(InputAction.navigateLeft.repeats, isTrue);
      expect(InputAction.volumeUp.repeats, isTrue);
      expect(InputAction.pageNext.repeats, isTrue);
      // A held Enter that fires twice reads as a double tap and skips a screen.
      expect(InputAction.confirm.repeats, isFalse);
      expect(InputAction.back.repeats, isFalse);
      expect(InputAction.contextMenu.repeats, isFalse);
      expect(InputAction.toggleDock.repeats, isFalse);
    });

    test('only a pointer counts as aiming', () {
      expect(InputDevice.pointer.points, isTrue);
      expect(InputDevice.keyboard.points, isFalse);
      expect(InputDevice.gamepad.points, isFalse);
      expect(InputDevice.keyboard.steps, isTrue);
      expect(InputDevice.gamepad.steps, isTrue);
      expect(InputDevice.pointer.steps, isFalse);
    });
  });

  group('Keymap', () {
    test('maps navigation, back and the app shortcuts', () {
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.arrowUp)), InputAction.navigateUp);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.arrowDown)), InputAction.navigateDown);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.arrowLeft)), InputAction.navigateLeft);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.arrowRight)), InputAction.navigateRight);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.escape)), InputAction.back);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.tab)), InputAction.toggleDock);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.f1)), InputAction.openFile);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.f11)), InputAction.fullscreen);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.slash)), InputAction.search);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.pageDown)), InputAction.pageNext);
    });

    test('leaves the OSD its own keys', () {
      // The player forwards raw events for these, so the table must not claim
      // them: mapping them to actions would drop `[`, `]`, digits and `alt+n`.
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.bracketLeft)), isNull);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.digit5)), isNull);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.keyS)), isNull);
      expect(Keymap.actionFor(_key(LogicalKeyboardKey.period)), isNull);
    });
  });

  group('OsdKeys.nameForAction', () {
    test('gives a pad the subset of the OSD keymap it can reach', () {
      expect(OsdKeys.nameForAction(InputAction.back), 'esc');
      expect(OsdKeys.nameForAction(InputAction.confirm), 'enter');
      expect(OsdKeys.nameForAction(InputAction.playPause), 'space');
      expect(OsdKeys.nameForAction(InputAction.navigateLeft), 'left');
      expect(OsdKeys.nameForAction(InputAction.seekJumpForward), 'shift+right');
      expect(OsdKeys.nameForAction(InputAction.jumpPrev), 'shift+left');
      expect(OsdKeys.nameForAction(InputAction.pageNext), 'pagedown');
      // Actions that only make sense in the shell have no OSD meaning.
      expect(OsdKeys.nameForAction(InputAction.search), isNull);
      expect(OsdKeys.nameForAction(InputAction.openFile), isNull);
    });
  });
}
