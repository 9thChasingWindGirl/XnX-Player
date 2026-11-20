import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/models/artwork.dart';
import 'package:xnx_player/data/models/media_item.dart';

MediaItem _item({Artwork artwork = const Artwork.empty(), String? poster, String? backdrop}) {
  return MediaItem(
    id: 'emby::1',
    title: 'Blade Runner 2049',
    posterUrl: poster,
    backdropUrl: backdrop,
    artwork: artwork,
  );
}

void main() {
  group('Artwork', () {
    test('best returns the first ref of a role, all returns every one', () {
      final Artwork art = (ArtworkBuilder()
            ..add(ArtKind.backdrop, 'b1')
            ..add(ArtKind.backdrop, 'b2')
            ..add(ArtKind.logo, 'logo.png'))
          .build();

      expect(art.best(ArtKind.backdrop)?.url, 'b1');
      expect(art.all(ArtKind.backdrop).map((ArtRef r) => r.url), <String>['b1', 'b2']);
      expect(art.all(ArtKind.disc), isEmpty);
      expect(art.has(ArtKind.logo), isTrue);
      expect(art.has(ArtKind.poster), isFalse);
    });

    test('mergedUnder fills gaps but keeps our own first', () {
      final Artwork child = (ArtworkBuilder()..add(ArtKind.thumb, 'episode.jpg')).build();
      final Artwork parent = (ArtworkBuilder()
            ..add(ArtKind.logo, 'series-logo.png')
            ..add(ArtKind.backdrop, 'series-fanart.jpg')
            ..add(ArtKind.thumb, 'series-still.jpg'))
          .build();

      final Artwork merged = child.mergedUnder(parent);

      expect(merged.best(ArtKind.logo)?.url, 'series-logo.png');
      expect(merged.best(ArtKind.backdrop)?.url, 'series-fanart.jpg');
      // Own art wins the first slot; the parent's stays as an alternative.
      expect(merged.all(ArtKind.thumb).map((ArtRef r) => r.url),
          <String>['episode.jpg', 'series-still.jpg']);
    });

    test('an empty side is a no-op, not an empty merge', () {
      final Artwork art = (ArtworkBuilder()..add(ArtKind.logo, 'l.png')).build();

      expect(identical(art.mergedUnder(const Artwork.empty()), art), isTrue);
      expect(identical(const Artwork.empty().mergedUnder(art), art), isTrue);
    });

    test('empty urls are dropped rather than stored as misses', () {
      final Artwork art = (ArtworkBuilder()
            ..add(ArtKind.poster, null)
            ..add(ArtKind.poster, '')
            ..add(ArtKind.poster, 'ok.jpg'))
          .build();

      expect(art.all(ArtKind.poster), hasLength(1));
      expect(art.best(ArtKind.poster)?.url, 'ok.jpg');
    });
  });

  group('MediaItem art accessors', () {
    test('falls back to the flat fields when the set is empty', () {
      final MediaItem item = _item(poster: 'p.jpg', backdrop: 'b.jpg');

      expect(item.hasLogo, isFalse);
      expect(item.thumbUrl, 'p.jpg');
      expect(item.heroBackdropUrl, 'b.jpg');
      expect(item.backdrops, <String>['b.jpg']);
    });

    test('prefers the real roles when present', () {
      final MediaItem item = _item(
        poster: 'p.jpg',
        artwork: (ArtworkBuilder()
              ..add(ArtKind.logo, 'logo.png')
              ..add(ArtKind.thumb, 'still.jpg')
              ..add(ArtKind.backdrop, 'bd1.jpg')
              ..add(ArtKind.backdrop, 'bd2.jpg'))
            .build(),
      );

      expect(item.hasLogo, isTrue);
      expect(item.thumbUrl, 'still.jpg');
      expect(item.heroBackdropUrl, 'bd1.jpg');
      expect(item.backdrops, <String>['bd1.jpg', 'bd2.jpg']);
    });
  });
}
