import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/core/input/held_repeat.dart';
import 'package:xnx_player/core/input/input_action.dart';
import 'package:xnx_player/core/input/keymap.dart';
import 'package:xnx_player/player/osd_keys.dart';

KeyEvent _key(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey(0),
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
    test('a tap fires exactly once', () {
      final HeldRepeat repeat = HeldRepeat();
      expect(repeat.step(InputAction.navigateRight, 0.016), InputAction.navigateRight);
      expect(repeat.isRepeating, isFalse);
      expect(_run(repeat, InputAction.navigateRight, 0.3), 0);
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

    test('the cadence is 350ms, then 110ms, then 50ms', () {
      final HeldRepeat repeat = HeldRepeat();
      expect(repeat.step(InputAction.navigateRight, 0.016), InputAction.navigateRight);
      // Nothing during the initial pause; the first repeat lands just after it.
      expect(_run(repeat, InputAction.navigateRight, 0.34), 0);
      expect(_run(repeat, InputAction.navigateRight, 0.05), 1);

      // Over three seconds the accelerating cadence has to beat a fixed 110ms
      // one by a wide margin (~47 steps against ~25). That gap is the reason
      // this class exists instead of a single interval.
      final int steps = _run(repeat, InputAction.navigateRight, 3.0);
      expect(steps, greaterThan(35));
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
