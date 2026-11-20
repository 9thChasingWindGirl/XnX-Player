import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/models/media_item.dart';
import 'package:xnx_player/design/ps_tokens.dart';
import 'package:xnx_player/pages/home/home_tile.dart';
import 'package:xnx_player/ui/core/focus_highlight.dart';

/// The three states a cover can be in, and the geometry each one implies.
///
/// These are the values a player only notices when they are wrong: every card
/// looking focused, a ring floating outside the artwork it belongs to, or a
/// grown card keeping the corner radius of a small one.
void main() {
  group('grownRect', () {
    test('a centred grow keeps the centre and grows both ways', () {
      const Rect rest = Rect.fromLTWH(100, 200, 196, 196);
      final Rect grown = grownRect(rest, 1.2);

      expect(grown.center, rest.center);
      expect(grown.width, closeTo(196 * 1.2, 0.001));
      expect(grown.height, closeTo(196 * 1.2, 0.001));
    });

    test('a bottom-left grow keeps the baseline and the left edge', () {
      const Rect rest = Rect.fromLTWH(96, 730, 196, 196);
      final Rect grown = grownRect(rest, 1.2, alignment: Alignment.bottomLeft);

      expect(grown.left, closeTo(rest.left, 0.001));
      expect(grown.bottom, closeTo(rest.bottom, 0.001));
      expect(grown.top, closeTo(rest.top - 196 * 0.2, 0.001));
    });

    test('scale 1 is the identity', () {
      const Rect rest = Rect.fromLTWH(10, 20, 30, 40);
      expect(grownRect(rest, 1), rest);
    });
  });

  group('PosterCard focus states', () {
    const MediaItem item = MediaItem(id: 'local::a', title: 'A');

    Future<BoxDecoration> decorationFor(WidgetTester tester, bool? focused) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: PosterCard(item: item, width: 196, height: 196, focused: focused),
          ),
        ),
      );
      final Finder box = find
          .descendant(of: find.byType(PosterCard), matching: find.byType(DecoratedBox))
          .first;
      return tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
    }

    testWidgets('unfocused: small corner, resting shadow', (WidgetTester tester) async {
      final BoxDecoration decoration = await decorationFor(tester, false);

      expect(decoration.borderRadius, BorderRadius.circular(PsRadius.card));
      expect(decoration.boxShadow, PsElevation.cardResting);
    });

    testWidgets('focused: larger corner, lifted', (WidgetTester tester) async {
      final BoxDecoration decoration = await decorationFor(tester, true);

      expect(decoration.borderRadius, BorderRadius.circular(PsRadius.cardFocused));
      expect(decoration.boxShadow, PsElevation.cardFocused);
    });

    testWidgets('a surface that does not track focus keeps the card lit and quiet', (
      WidgetTester tester,
    ) async {
      final BoxDecoration decoration = await decorationFor(tester, null);

      expect(decoration.borderRadius, BorderRadius.circular(PsRadius.card));
      expect(decoration.boxShadow, PsElevation.cardResting);
      // No dimming layer is inserted when the surface does not track focus.
      expect(
        find.descendant(of: find.byType(PosterCard), matching: find.byType(ColoredBox)),
        findsNothing,
      );
    });

    testWidgets('an unfocused card on a tracking surface is dimmed', (
      WidgetTester tester,
    ) async {
      await decorationFor(tester, false);
      // Exactly one: the dim layer over the artwork. (The progress bar would be
      // a second, but this item has no progress.)
      expect(
        find.descendant(of: find.byType(PosterCard), matching: find.byType(ColoredBox)),
        findsOneWidget,
      );
    });
  });
}
