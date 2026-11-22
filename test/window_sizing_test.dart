import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/core/window_sizing.dart';

void main() {
  group('WindowSizing', () {
    test('minimum keeps the 16:9 design aspect', () {
      expect(WindowSizing.aspect, closeTo(16 / 9, 0.00001));
      expect(WindowSizing.minimum.width / WindowSizing.minimum.height,
          closeTo(16 / 9, 0.00001));
    });

    test('picks the largest preferred size that fits the work area', () {
      expect(WindowSizing.fit(const Size(2560, 1440)), const Size(1920, 1080));
      // 96 px margin each side: 1600x1000 leaves 1408x808, so 1440 does not fit.
      expect(WindowSizing.fit(const Size(1600, 1000)), const Size(1280, 720));
      expect(WindowSizing.fit(const Size(1366, 768)), const Size(960, 540));
    });

    test('every preferred step is 16:9', () {
      for (final Size size in WindowSizing.preferred) {
        expect(size.width / size.height, closeTo(16 / 9, 0.00001));
      }
    });

    test('a tiny display still gets a 16:9 window inside the work area', () {
      final Size picked = WindowSizing.fit(const Size(800, 600));
      expect(picked.width / picked.height, closeTo(16 / 9, 0.001));
      expect(picked.width, lessThanOrEqualTo(800 - WindowSizing.margin * 2));
      expect(picked.height, lessThanOrEqualTo(600 - WindowSizing.margin * 2));
    });

    test('clampAspect restores the ratio from an arbitrary drag', () {
      final Size squeezed = WindowSizing.clampAspect(const Size(1920, 400));
      expect(squeezed.width / squeezed.height, closeTo(16 / 9, 0.001));
      expect(squeezed.height, greaterThanOrEqualTo(WindowSizing.minimum.height));
    });
  });
}
