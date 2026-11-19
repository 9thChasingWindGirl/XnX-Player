import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/player/osd_keys.dart';

void main() {
  group('OsdKeys', () {
    test('maps the navigation and media keys the OSD binds', () {
      expect(OsdKeys.compose('Space'), 'space');
      expect(OsdKeys.compose('Arrow Left'), 'left');
      expect(OsdKeys.compose('Arrow Right'), 'right');
      expect(OsdKeys.compose('Arrow Up'), 'up');
      expect(OsdKeys.compose('Arrow Down'), 'down');
      expect(OsdKeys.compose('Escape'), 'esc');
      expect(OsdKeys.compose('Tab'), 'tab');
      expect(OsdKeys.compose('Backspace'), 'bs');
      expect(OsdKeys.compose('Page Up'), 'pageup');
      expect(OsdKeys.compose('Page Down'), 'pagedown');
    });

    test('maps letters, digits and function keys', () {
      expect(OsdKeys.compose('Key J'), 'j');
      expect(OsdKeys.compose('Key A'), 'a');
      expect(OsdKeys.compose('Key Z'), 'z');
      expect(OsdKeys.compose('Digit 1'), '1');
      expect(OsdKeys.compose('Digit 9'), '9');
      expect(OsdKeys.compose('F7'), 'f7');
      expect(OsdKeys.compose('F11'), 'f11');
    });

    test('maps punctuation that drives speed and frame stepping', () {
      expect(OsdKeys.compose('Bracket Left'), '[');
      expect(OsdKeys.compose('Bracket Right'), ']');
      expect(OsdKeys.compose('Comma'), 'comma');
      expect(OsdKeys.compose('Period'), 'period');
      expect(OsdKeys.compose('Minus'), '-');
    });

    test('prefixes modifiers in the order the Lua parser expects', () {
      expect(OsdKeys.compose('Arrow Left', shift: true), 'shift+left');
      expect(OsdKeys.compose('Key N', alt: true), 'alt+n');
      expect(OsdKeys.compose('Key S', shift: true), 'shift+s');
      expect(OsdKeys.compose('Key O', alt: true, shift: true), 'alt+shift+o');
      // Unmodified keys must not grow a dangling prefix.
      expect(OsdKeys.compose('Space', shift: false, alt: false), 'space');
    });

    test('declines keys the OSD does not bind', () {
      expect(OsdKeys.compose('Cut'), isNull);
      expect(OsdKeys.compose('Media Play'), isNull);
      expect(OsdKeys.compose(null), isNull);
      expect(OsdKeys.base(''), isNull);
    });
  });
}
