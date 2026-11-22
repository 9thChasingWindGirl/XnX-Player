import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/sources/media_source.dart';

/// Parses a name and asserts a tag was found, returning it non-null.
///
/// `expect(tag, isNotNull)` does not promote the type — Dart's flow analysis
/// only understands `assert`/`if`, not matcher calls. Binding the result to a
/// non-nullable local keeps every following access clean.
EpisodeTag _require(String name, {String? folder}) {
  final EpisodeTag? tag = episodeTagFromFileName(name, folderHint: folder);
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

    test('accepts the conventions Kodi recognises beyond SxxEyy', () {
      final EpisodeTag scene = _require('Friends.1x09.mkv');
      expect(scene.show, 'Friends');
      expect(scene.season, 1);
      expect(scene.episode, 9);

      // A bare E09 takes its season from the containing folder.
      final EpisodeTag bare = _require('Show.E09.720p.mkv', folder: 'Season 2');
      expect(bare.season, 2);
      expect(bare.episode, 9);

      final EpisodeTag roman = _require('Show.Part II.mkv', folder: 'Season 1');
      expect(roman.episode, 2);

      final EpisodeTag dated = _require('Show.2024.03.15.mkv');
      expect(dated.season, 2024);
      expect(dated.episode, 15);

      final EpisodeTag absolute = _require('Show.103.mkv');
      expect(absolute.season, 1);
      expect(absolute.episode, 3);

      final EpisodeTag chinese = _require('剧集.第2季第05集.mkv');
      expect(chinese.season, 2);
      expect(chinese.episode, 5);
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
