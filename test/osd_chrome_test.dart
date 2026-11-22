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
      // The strip is inset by the same safe margin as the rest of the chrome.
      expect(wide.left, closeTo(96 * 2560 / 1920, 1));
      expect(narrow.left, closeTo(96 * 1280 / 1920, 1));
      expect(wide.right, closeTo(2560 - 96 * 2560 / 1920, 1));
      expect(narrow.right, closeTo(1280 - 96 * 1280 / 1920, 1));
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

    test('the bottom band stays anchored and legible in a squeezed window', () {
      // A wide-but-short window used to scale the band by height alone: the
      // controls collapsed into a thin strip while the floored type overflowed
      // them. Sizes now follow width; the band is anchored to the bottom edge.
      const ui.Size squeezed = ui.Size(1920, 400);
      final ui.Rect wide = OsdChrome.seekTrack(const ui.Size(1920, 1080));
      final ui.Rect short = OsdChrome.seekTrack(squeezed);
      expect(short.center.dy, closeTo(204, 0.01)); // 400 - (1080 - 884)
      expect(short.height, closeTo(wide.height, 0.01));

      final ui.Rect seekZone = OsdChrome.hotZones(squeezed).first;
      expect(seekZone.height, closeTo(OsdChrome.seekHitHeight, 0.01));
      expect(seekZone.bottom, lessThanOrEqualTo(squeezed.height));

      final ui.Rect play = OsdChrome.zones(squeezed)
          .firstWhere((OsdZone zone) => zone.id == 'play')
          .rect;
      expect(play.height, closeTo(66, 0.01));
      expect(play.bottom, lessThanOrEqualTo(squeezed.height));
    });

    test('a 16:9 stage keeps the original geometry', () {
      // The bottom-anchor formula is algebraically identical to height scaling
      // when the stage keeps the design aspect ratio.
      const ui.Size stage = ui.Size(1280, 720);
      expect(OsdChrome.seekTrack(stage).center.dy, closeTo(884 * 720 / 1080, 0.01));
    });
  });

  group('OsdChromeModel', () {
    test('scrubbing overrides the clock position without mutating state', () {
      const OsdChromeModel idle = OsdChromeModel(
        title: 'Dune: Part Two',
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
        title: 'Dune: Part Two',
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
  group('OsdMenu mirroring', () {
    // The wire format Lua pushes on `player-event`: 1-based index, rows as
    // plain maps. These cases pin the shift in both directions, because an
    // off-by-one here clicks the row next to the one the user aimed at.
    Map<String, Object?> event({int index = 3}) => <String, Object?>{
          'type': 'menu',
          'open': true,
          'title': '音轨',
          'index': index,
          'rows': <Object?>[
            <Object?, Object?>{'kind': 'header', 'label': '音轨'},
            <Object?, Object?>{'kind': 'item', 'label': 'Track 1', 'value': 'chi', 'active': true},
            <Object?, Object?>{'kind': 'adjust', 'label': '同步', 'value': '0.0s'},
            <Object?, Object?>{'kind': 'item', 'label': 'Track 2'},
          ],
        };

    test('fromEvent shifts the 1-based Lua index to 0-based', () {
      final OsdMenu? menu = OsdMenu.fromEvent(event());
      expect(menu, isNotNull);
      expect(menu!.title, '音轨');
      expect(menu.index, 2); // Lua's row 3 → row 2 here.
      expect(menu.rows, hasLength(4));
      expect(menu.rows[0].isHeader, isTrue);
      expect(menu.rows[1].active, isTrue);
      expect(menu.rows[2].value, '0.0s');
    });

    test('a closed or malformed event does not fabricate a panel', () {
      // Closed arrives as open:false with no rows — that is null, not an
      // empty menu that would paint a bare frame forever.
      expect(OsdMenu.fromEvent(<Object?, Object?>{'open': false}), isNull);
      // Missing rows: not a well-formed open menu.
      expect(OsdMenu.fromEvent(<Object?, Object?>{'open': true}), isNull);
      // A row that is not a map is skipped, not a crash.
      final OsdMenu? menu = OsdMenu.fromEvent(<Object?, Object?>{
        'open': true,
        'index': 1,
        'rows': <Object?>['garbage'],
      });
      expect(menu, isNotNull);
      expect(menu!.rows, isEmpty);
    });

    test('menuZones keep real row indices and skip headers', () {
      final OsdMenu menu = OsdMenu.fromEvent(event())!;
      final List<OsdZone> rows = OsdChrome.menuZones(zonelessStage(), menu);
      // Headers are drawn but not clickable; the three non-header rows are.
      expect(rows, hasLength(3));
      expect(
        rows.map((OsdZone zone) => zone.id),
        <String>['menurow:1', 'menurow:2', 'menurow:3'],
      );
      // Clicking the second zone must name Lua's row 3 after the +1 shift —
      // the same row the event said was selected.
      final int clicked = int.parse(rows[1].id.substring(OsdChrome.menuRowZone.length)) + 1;
      expect(clicked, 3);
    });

    test('the selected row lands inside its own clickable rect', () {
      final OsdMenu menu = OsdMenu.fromEvent(event())!;
      final List<OsdZone> rows = OsdChrome.menuZones(zonelessStage(), menu);
      final OsdZone selected = rows.firstWhere(
        (OsdZone zone) => zone.id == 'menurow:${menu.index}',
      );
      expect(selected.rect.top, greaterThan(0));
      expect(selected.rect.bottom, lessThan(zonelessStage().height));
    });
  });
}

ui.Size zonelessStage() => const ui.Size(1920, 1080);
