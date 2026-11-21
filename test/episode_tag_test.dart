import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/sources/media_source.dart';

void main() {
  group('episodeTagFromFileName', () {
    test('parses a standard SxxEyy name with an episode title', () {
      final EpisodeTag? tag = episodeTagFromFileName(
        '赛博朋克：边缘行者 - S02E05 - 如梦似幻.2160p.HEVC.mkv',
      );
      expect(tag, isNotNull);
      expect(tag!.season, 2);
      expect(tag.episode, 5);
      expect(tag.show, '赛博朋克：边缘行者');
      expect(tag.episodeTitle, '如梦似幻');
      expect(tag.badge, 'S02E05');
    });

    test('handles dot-separated scene naming', () {
      final EpisodeTag? tag = episodeTagFromFileName('Breaking.Bad.S01E03.1080p.WEB-DL.mkv');
      expect(tag, isNotNull);
      expect(tag!.show, 'Breaking Bad');
      expect(tag.season, 1);
      expect(tag.episode, 3);
      expect(tag.episodeTitle, isNull);
    });

    test('accepts lowercase s/e and a single-digit episode', () {
      final EpisodeTag? tag = episodeTagFromFileName('Show s3e7.mp4');
      expect(tag, isNotNull);
      expect(tag!.season, 3);
      expect(tag.episode, 7);
      expect(tag.badge, 'S03E07');
    });

    test('returns null for movies and names without an episode tag', () {
      expect(episodeTagFromFileName('子弹列车.2022.2160p.mkv'), isNull);
      expect(episodeTagFromFileName('Movie.S02.mkv'), isNull);
      expect(episodeTagFromFileName('S02E05.mkv'), isNull);
    });

    test('keeps a plausible show name out of the release tags', () {
      final EpisodeTag? tag = episodeTagFromFileName('The.Show.S10E02.720p.HDR.mkv');
      expect(tag, isNotNull);
      expect(tag!.show, 'The Show');
    });
  });
}
