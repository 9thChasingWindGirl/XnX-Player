import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/models/artwork.dart';
import 'package:xnx_player/data/models/media_item.dart';
import 'package:xnx_player/design/ps_tokens.dart';
import 'package:xnx_player/ui/core/title_treatment.dart';

/// A title either arrives as artwork or as words; both must end up on screen.
void main() {
  Future<void> pump(WidgetTester tester, MediaItem item) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: TitleTreatment(item: item, style: PsType.display, maxWidth: 1000),
        ),
      ),
    );
  }

  testWidgets('no logo: the title is drawn as text', (WidgetTester tester) async {
    const MediaItem item = MediaItem(id: 'local::a', title: 'Blade Runner 2049');
    await pump(tester, item);

    expect(find.text('Blade Runner 2049'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a logo reserves its box instead of the text line', (
    WidgetTester tester,
  ) async {
    const MediaItem item = MediaItem(
      id: 'emby::a',
      title: 'Blade Runner 2049',
      artwork: Artwork(<ArtKind, List<ArtRef>>{
        ArtKind.logo: <ArtRef>[ArtRef('http://example.test/logo.png')],
      }),
    );
    await pump(tester, item);

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Blade Runner 2049'), findsNothing);
  });
}
