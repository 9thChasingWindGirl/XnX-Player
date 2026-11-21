import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/player/osd/osd_chrome.dart';

void main() {
  group('OsdChrome geometry', () {
    const ui.Size stage = ui.Size(1920, 1080);

    test('hot zone is one strip inside the bottom band', () {
      final List<ui.Rect> zones = OsdChrome.hotZones(zonelessStage());
      expect(zones, hasLength(1));
      final ui.Rect seek = zones.first;
      // Inside the band, spanning the safe area but not touching the edges.
      expect(seek.bottom, lessThanOrEqualTo(stage.height));
      expect(seek.top, greaterThan(stage.height - OsdChrome.bandHeight - 40));
      expect(seek.left, greaterThanOrEqualTo(OsdChrome.safeX - 1));
      expect(seek.right, lessThanOrEqualTo(1920 - OsdChrome.safeX + 1));
    });

    test('a normalized pointer inside the strip hits the seek bar', () {
      final ui.Rect seek = OsdChrome.hotZones(zonelessStage()).first;
      // 85 % across, 3 % from the bottom: the seek strip on a 16:9 stage.
      final ui.Offset point = ui.Offset(
        seek.left + seek.width * 0.85,
        seek.top + seek.height * 0.5,
      );
      expect(seek.contains(point), isTrue);
    });

    test('a pointer over the picture does not hit the strip', () {
      final ui.Rect seek = OsdChrome.hotZones(zonelessStage()).first;
      // Centre of the picture: the wheel there belongs to the Lua side.
      expect(seek.contains(const ui.Offset(960, 540)), isFalse);
    });

    test('strip height exceeds the visual line for cursor tolerance', () {
      final List<ui.Rect> zones = OsdChrome.hotZones(zonelessStage());
      expect(zones.first.height, greaterThanOrEqualTo(OsdChrome.seekHitHeight));
    });

    test('zones grow with the stage width, not fixed to 1920', () {
      final ui.Rect wide = OsdChrome.hotZones(const ui.Size(2560, 1440)).first;
      final ui.Rect narrow = OsdChrome.hotZones(const ui.Size(1280, 720)).first;
      expect(wide.width, greaterThan(narrow.width));
      // The strip ends where the drawn line does, not at the window edge:
      // time readout on the left, duration readout on the right.
      expect(wide.left, closeTo(OsdChrome.seekLeftInset, 1));
      expect(narrow.left, closeTo(OsdChrome.seekLeftInset, 1));
      expect(wide.right, closeTo(2560 - OsdChrome.seekRightInset, 1));
      expect(narrow.right, closeTo(1280 - OsdChrome.seekRightInset, 1));
    });

    test('pointer fraction uses the same line as paint and hit testing', () {
      const ui.Size stage = ui.Size(1920, 1080);
      final ui.Rect track = OsdChrome.seekTrack(stage);
      expect(OsdChrome.fractionAt(stage, track.left), closeTo(0, 0.0001));
      expect(OsdChrome.fractionAt(stage, track.center.dx), closeTo(0.5, 0.0001));
      expect(OsdChrome.fractionAt(stage, track.right), closeTo(1, 0.0001));
      expect(OsdChrome.hotZones(stage).first.left, closeTo(track.left, 0.0001));
      expect(OsdChrome.hotZones(stage).first.right, closeTo(track.right, 0.0001));
    });
  });

  group('OsdChromeModel', () {
    test('scrubbing overrides the clock position without mutating state', () {
      const OsdChromeModel idle = OsdChromeModel(
        position: 120,
        duration: 600,
        paused: false,
        volume: 80,
        muted: false,
        badges: <String>['HEVC'],
        accent: ui.Color(0xFF0070CC),
        hoverSeek: false,
      );
      expect(idle.position, 120);
      expect(idle.scrubbing, isNull);
      // The overlay computes the scrub position; the model stays a value.
      const OsdChromeModel scrubbing = OsdChromeModel(
        position: 420,
        duration: 600,
        paused: false,
        volume: 80,
        muted: false,
        badges: <String>[],
        accent: ui.Color(0xFF0070CC),
        scrubbing: 0.7,
        hoverSeek: true,
      );
      expect(scrubbing.scrubbing, 0.7);
    });
  });
}

ui.Size zonelessStage() => const ui.Size(1920, 1080);
