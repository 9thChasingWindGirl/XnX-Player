import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/design/ps_media.dart';
import 'package:xnx_player/design/ps_tokens.dart';

/// The tokens are a transcription, so the numbers themselves are the contract.
///
/// A test that only says "0.55 == 0.55" looks silly until the day someone
/// "tidies" the dock to 0.7 and every panel in the app drifts with it. Each
/// expectation below names the line in the reference it came from, so a change
/// has to argue with the source rather than with this file.
void main() {
  group('PsGlass — draw_overlay_panel, overlay.cpp:219-250', () {
    test('a frosted panel covers the blur at 55 %', () {
      expect(PsGlass.tint, 0.55);
    });

    test('the home drawer is the richer 62 % tint', () {
      // aurora.cpp:519 — the drawer is tinted with the artwork, not the page.
      expect(PsGlass.sheetTint, 0.62);
    });

    test('a sheet darkens the screen behind it by half', () {
      // SheetStyle::scrim.
      expect(PsGlass.scrim, 0.50);
    });

    test('an edge is never thinner than 1.5', () {
      // max(theme.border, 1.5).
      expect(PsGlass.edgeWidth, 1.5);
    });

    test('the dock is the page colour, not the lighter surface', () {
      expect(PsGlass.dockTintTop, 0.62);
      expect(PsGlass.dockTintBottom, 0.78);
      expect(PsGlass.dockTintBottom, greaterThan(PsGlass.dockTintTop));
    });
  });

  group('PsCard — CardLook, card.h:47-88', () {
    test('a card in a collection grows 6 %, a shelf grows 20 %', () {
      expect(PsCard.focusScale, 1.06);
      // The stage's own number is separate and stays in PsSpace.
      expect(PsSpace.cardGrow, 1.2);
    });

    test('focus rises 6 px and a press gives back 4 %', () {
      expect(PsCard.lift, 6);
      expect(PsCard.pressScale, 0.04);
    });

    test('text over art always sits on a 78 % scrim', () {
      expect(PsCard.artScrim, 0.78);
    });

    test('the watched bar is 6 tall and inset 10', () {
      expect(PsCard.progressHeight, 6);
      expect(PsCard.progressInset, 10);
    });

    test('a card does not wash its neighbours out', () {
      // CardLook::dim defaults to 0: a shelf dims by scaling, not by opacity.
      expect(PsCard.dim, 0);
    });
  });

  group('PsElevation', () {
    test('a resting card casts nothing', () {
      expect(PsElevation.cardResting, isEmpty);
    });

    test('a lifted card matches the kit formula at both ends', () {
      final BoxShadow atRest = PsElevation.cardLifted(0).single;
      expect(atRest.blurRadius, 22);
      expect(atRest.color.a, closeTo(0, 1e-6), reason: 'no focus, no shadow');
      expect(atRest.offset, const Offset(4, 10));

      final BoxShadow atFocus = PsElevation.cardLifted(1).single;
      expect(atFocus.blurRadius, 38); // 22 + 16
      expect(atFocus.color.a, closeTo(0.34, 0.001));
      expect(atFocus.offset, const Offset(4, 18)); // 10 + 8
    });
  });

  group('PsPanel — PanelStyle / ListViewStyle', () {
    test('padding, title and subtitle', () {
      expect(PsPanel.paddingX, 24);
      expect(PsPanel.paddingY, 20);
      expect(PsPanel.titleSize, 24);
      expect(PsPanel.subtitleSize, 19);
    });

    test('a row is the kit pitch, with a shorter row', () {
      expect(PsPanel.headerHeight, 52);
      expect(PsPanel.rowInset, 26);
      // 76 in the kit; 68 + 8 here because a control-center panel is 420 tall.
      expect(PsPanel.rowHeight + PsPanel.rowGap, 76);
    });
  });

  group('PsSeek — behaviour, not looks', () {
    test('a nudge is 5 s, a jump is 15 s', () {
      expect(PsSeek.step, 5);
      expect(PsSeek.jump, 15);
    });

    test('a jump is three nudges, not six', () {
      // The OSD used to jump 30 s on Shift + arrow while every other surface
      // said 15. If this ratio ever needs to change, change it everywhere.
      expect(PsSeek.jump / PsSeek.step, 3);
    });

    test('a held direction accelerates 1.3x a step and stops at 60', () {
      expect(PsSeek.repeated(0), 5);
      expect(PsSeek.repeated(1), closeTo(6.5, 0.001));
      expect(PsSeek.repeated(2), closeTo(8.45, 0.001));
      expect(PsSeek.repeated(50), 60);
      expect(PsSeek.repeated(1000), 60);
    });
  });

  group('PsControls — MediaControlsStyle, media_controls.hpp:60-104', () {
    test('the transport in a panel is smaller than the Now Playing screen', () {
      expect(PsControls.buttonSize, 56);
      expect(PsControls.playSize, 68);
      expect(PsControls.playSize, greaterThan(PsControls.buttonSize));
      // The screen's circles are 46 / 32 — a different object, not a scale.
      expect(PsTransport.playRadius, 46);
    });

    test('the scrubber in a panel is 8 tall with a 24 px thumb', () {
      expect(PsControls.trackHeight, 8);
      expect(PsControls.thumbSize, 24);
      // player.cpp draws a 9 px dot on its own stage.
      expect(PsScrubber.thumbRest, 9);
    });

    test('rewind is a nudge, not the shoulder jump', () {
      expect(PsControls.skipSeconds, 10);
      expect(PsControls.skipSeconds, lessThan(PsSeek.jump));
    });

    test('a volume press is 20 steps across the range', () {
      expect(PsControls.volumeStep, 0.05);
      expect((1 / PsControls.volumeStep).round(), 20);
    });
  });
}
