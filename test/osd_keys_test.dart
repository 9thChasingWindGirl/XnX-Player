import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/player/osd_keys.dart';

void main() {
  group('OsdKeys', () {
    test('maps the navigation and media keys the OSD binds', () {
      expect(OsdKeys.compose(LogicalKeyboardKey.space), 'space');
      expect(OsdKeys.compose(LogicalKeyboardKey.arrowLeft), 'left');
      expect(OsdKeys.compose(LogicalKeyboardKey.arrowRight), 'right');
      expect(OsdKeys.compose(LogicalKeyboardKey.arrowUp), 'up');
      expect(OsdKeys.compose(LogicalKeyboardKey.arrowDown), 'down');
      expect(OsdKeys.compose(LogicalKeyboardKey.escape), 'esc');
      expect(OsdKeys.compose(LogicalKeyboardKey.tab), 'tab');
      expect(OsdKeys.compose(LogicalKeyboardKey.backspace), 'bs');
      expect(OsdKeys.compose(LogicalKeyboardKey.pageUp), 'pageup');
      expect(OsdKeys.compose(LogicalKeyboardKey.pageDown), 'pagedown');
      expect(OsdKeys.compose(LogicalKeyboardKey.enter), 'enter');
      expect(OsdKeys.compose(LogicalKeyboardKey.numpadEnter), 'enter');
    });

    test('maps letters, digits and function keys', () {
      expect(OsdKeys.compose(LogicalKeyboardKey.keyJ), 'j');
      expect(OsdKeys.compose(LogicalKeyboardKey.keyA), 'a');
      expect(OsdKeys.compose(LogicalKeyboardKey.keyZ), 'z');
      expect(OsdKeys.compose(LogicalKeyboardKey.digit1), '1');
      expect(OsdKeys.compose(LogicalKeyboardKey.digit9), '9');
      expect(OsdKeys.compose(LogicalKeyboardKey.f7), 'f7');
      expect(OsdKeys.compose(LogicalKeyboardKey.f11), 'f11');
    });

    test('maps punctuation that drives speed and frame stepping', () {
      expect(OsdKeys.compose(LogicalKeyboardKey.bracketLeft), '[');
      expect(OsdKeys.compose(LogicalKeyboardKey.bracketRight), ']');
      expect(OsdKeys.compose(LogicalKeyboardKey.comma), 'comma');
      expect(OsdKeys.compose(LogicalKeyboardKey.period), 'period');
      expect(OsdKeys.compose(LogicalKeyboardKey.minus), '-');
    });

    test('prefixes modifiers in the order the Lua parser expects', () {
      expect(
        OsdKeys.compose(LogicalKeyboardKey.arrowLeft, shift: true),
        'shift+left',
      );
      expect(OsdKeys.compose(LogicalKeyboardKey.keyN, alt: true), 'alt+n');
      expect(OsdKeys.compose(LogicalKeyboardKey.keyS, shift: true), 'shift+s');
      expect(
        OsdKeys.compose(LogicalKeyboardKey.keyO, alt: true, shift: true),
        'alt+shift+o',
      );
      // Unmodified keys must not grow a dangling prefix.
      expect(
        OsdKeys.compose(LogicalKeyboardKey.space, shift: false, alt: false),
        'space',
      );
    });

    test('declines keys the OSD does not bind', () {
      expect(OsdKeys.compose(LogicalKeyboardKey.f1), isNull);
      expect(OsdKeys.compose(LogicalKeyboardKey.controlLeft), isNull);
      expect(OsdKeys.compose(LogicalKeyboardKey.mediaPlay), isNull);
      expect(OsdKeys.base(LogicalKeyboardKey.shiftLeft), isNull);
    });

    test('carries ctrl for the one chord the OSD owns', () {
      expect(
        OsdKeys.compose(LogicalKeyboardKey.keyB, ctrl: true),
        'ctrl+b',
      );
      // Ctrl is checked first because the shell swallows it — the player has to
      // know which keys are exceptions before it composes anything.
      expect(OsdKeys.ctrlOwned(LogicalKeyboardKey.keyB), isTrue);
      expect(OsdKeys.ctrlOwned(LogicalKeyboardKey.keyF), isFalse);
      expect(OsdKeys.ctrlOwned(LogicalKeyboardKey.arrowLeft), isFalse);
    });
  });
}
