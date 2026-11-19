import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/models/media_item.dart';

void main() {
  group('MediaItem', () {
    test('artwork colours are stable for the same id', () {
      const MediaItem a = MediaItem(id: 'emby::42', title: 'A');
      const MediaItem b = MediaItem(id: 'emby::42', title: 'B');
      expect(a.artwork, b.artwork);
    });

    test('different ids usually land on different artwork', () {
      const MediaItem a = MediaItem(id: 'emby::1', title: 'A');
      const MediaItem b = MediaItem(id: 'emby::2', title: 'B');
      expect(a.artwork, isNot(equals(b.artwork)));
    });

    test('folders and seasons are not directly playable', () {
      const MediaItem folder = MediaItem(id: 'x', title: 'X', kind: MediaKind.folder);
      const MediaItem season = MediaItem(id: 'y', title: 'Y', kind: MediaKind.season);
      const MediaItem episode = MediaItem(id: 'z', title: 'Z', kind: MediaKind.episode);

      expect(folder.isPlayable, isFalse);
      expect(season.isPlayable, isFalse);
      expect(episode.isPlayable, isTrue);
    });
  });
}
