import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/design/ps_motion.dart';

void main() {
  group('Spring', () {
    test('settles on its target without overshoot when critically damped', () {
      final Spring spring = Spring(frequency: 20);
      spring.target = 100;
      double peak = 0;
      for (int i = 0; i < 120; i++) {
        spring.update(1 / 60);
        peak = spring.value > peak ? spring.value : peak;
      }
      expect(spring.value, closeTo(100, 0.5));
      expect(peak, lessThan(101.5));
    });

    test('is frame-rate independent', () {
      final Spring fast = Spring(frequency: 18)..target = 1;
      final Spring slow = Spring(frequency: 18)..target = 1;
      for (int i = 0; i < 60; i++) {
        fast.update(1 / 60);
      }
      for (int i = 0; i < 30; i++) {
        slow.update(1 / 30);
      }
      expect(fast.value, closeTo(slow.value, 0.02));
    });

    test('interrupting mid-flight does not restart from zero', () {
      final Spring spring = Spring(frequency: 20)..target = 100;
      for (int i = 0; i < 6; i++) {
        spring.update(1 / 60);
      }
      final double travelled = spring.value;
      spring.target = -100;
      spring.update(1 / 60);
      expect(travelled, greaterThan(0));
      expect(spring.value, greaterThan(0));
      expect(spring.value, lessThan(travelled + 1));
    });
  });

  group('SpringRect', () {
    test('moves every edge toward the target rect', () {
      final SpringRect rect = SpringRect(value: Rect.zero, frequency: 20);
      rect.setTarget(const Rect.fromLTWH(100, 200, 50, 60));
      for (int i = 0; i < 180; i++) {
        rect.update(1 / 60);
      }
      expect(rect.value.left, closeTo(100, 0.5));
      expect(rect.value.width, closeTo(50, 1));
      expect(rect.value.height, closeTo(60, 1));
    });
  });

  group('Ease', () {
    test('clamps outside the unit interval', () {
      expect(Ease.cubicOut(-1), 0);
      expect(Ease.cubicOut(2), 1);
      expect(Ease.quintOut(0), 0);
      expect(Ease.smoothstep(1), 1);
      expect(Ease.backOut(1), closeTo(1, 0.001));
    });

    test('arrivals start fast and stop soft', () {
      expect(Ease.quintOut(0.5), greaterThan(0.5));
      expect(Ease.cubicIn(0.5), lessThan(0.5));
    });
  });

  group('stagger', () {
    test('later parts start later', () {
      expect(stagger(0, 0), 0);
      expect(stagger(0, 3), 0);
      expect(stagger(1, 0), 1);
      expect(stagger(0.1, 0), greaterThan(stagger(0.1, 2)));
    });
  });
}
