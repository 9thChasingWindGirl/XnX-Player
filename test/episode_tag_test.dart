import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/sources/media_source.dart';

/// Parses a name and asserts a tag was found, returning it non-null.
///
/// `expect(tag, isNotNull)` does not promote the type — Dart's flow analysis
/// only understands `assert`/`if`, not matcher calls. Binding the result to a
/// non-nullable local keeps every following access clean.
EpisodeTag _require(String name) {
  final EpisodeTag? tag = episodeTagFromFileName(name);
  expect(tag, isNotNull, reason: 'expected an episode tag in "$name"');
  return tag!;
}

void main() {
  group('episodeTagFromFileName', () {
    test('parses a standard SxxEyy name with an episode title', () {
      final EpisodeTag tag =
          _require('赛博朋克：边缘行者 - S02E05 - 如梦似幻.2160p.HEVC.mkv');
      expect(tag.season, 2);
      expect(tag.episode, 5);
      expect(tag.show, '赛博朋克：边缘行者');
      expect(tag.episodeTitle, '如梦似幻');
      expect(tag.badge, 'S02E05');
    });

    test('handles dot-separated scene naming', () {
      final EpisodeTag tag = _require('Breaking.Bad.S01E03.1080p.WEB-DL.mkv');
      expect(tag.show, 'Breaking Bad');
      expect(tag.season, 1);
      expect(tag.episode, 3);
      expect(tag.episodeTitle, isNull);
    });

    test('accepts lowercase s/e and a single-digit episode', () {
      final EpisodeTag tag = _require('Show s3e7.mp4');
      expect(tag.season, 3);
      expect(tag.episode, 7);
      expect(tag.badge, 'S03E07');
    });

    test('returns null for movies and names without an episode tag', () {
      expect(episodeTagFromFileName('子弹列车.2022.2160p.mkv'), isNull);
      expect(episodeTagFromFileName('Movie.S02.mkv'), isNull);
      expect(episodeTagFromFileName('S02E05.mkv'), isNull);
    });

    test('keeps a plausible show name out of the release tags', () {
      final EpisodeTag tag = _require('The.Show.S10E02.720p.HDR.mkv');
      expect(tag.show, 'The Show');
    });

    test('drops the separator before the tag without eating a hyphen in the name', () {
      // The exact shape in the library: "Show - SxxEyy - Title.mkv".
      final EpisodeTag tag = _require(
          '赛博朋克：边缘行者 - S02E01 - 危险边缘的慢舞.mkv');
      expect(tag.show, '赛博朋克：边缘行者');
      expect(tag.episodeTitle, '危险边缘的慢舞');

      // A hyphen inside the title is not a separator.
      expect(_require('Spider-Man - S01E02.mkv').show, 'Spider-Man');
    });
  });
}
