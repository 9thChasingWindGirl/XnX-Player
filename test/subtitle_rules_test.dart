import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/sources/subtitle_rules.dart';

void main() {
  group('SubtitleRules', () {
    test('extension table uses the Kodi conventions', () {
      expect(SubtitleRules.isSubtitle('Movie.srt'), isTrue);
      expect(SubtitleRules.isSubtitle('Movie.SRT'), isTrue);
      expect(SubtitleRules.isSubtitle('Movie.ass'), isTrue);
      expect(SubtitleRules.isSubtitle('Movie.vtt'), isTrue);
      expect(SubtitleRules.isSubtitle('Movie.idx'), isTrue);
      expect(SubtitleRules.isSubtitle('Movie.zip'), isFalse);
      expect(SubtitleRules.isSubtitle('Movie.mkv'), isFalse);
    });

    test('video name is a prefix, with a separator boundary', () {
      expect(SubtitleRules.matches('Movie.mkv', 'Movie.srt'), isTrue);
      expect(SubtitleRules.matches('Movie.mkv', 'Movie.en.srt'), isTrue);
      expect(SubtitleRules.matches('Movie.mkv', 'Movie.forced.ass'), isTrue);
      // Kodi's plain prefix match would wrongly accept these.
      expect(SubtitleRules.matches('Movie.mkv', 'Movie2.srt'), isFalse);
      expect(SubtitleRules.matches('Movie.mkv', 'Movies.srt'), isFalse);
      expect(SubtitleRules.matches('Movie.mkv', 'Other.srt'), isFalse);
    });

    test('flags and language are read from the tail of the name', () {
      final SubtitleCandidate forced =
          SubtitleRules.describe('Movie.en.forced.srt', '/m/Movie.en.forced.srt');
      expect(forced.flag, SubtitleFlag.forced);
      expect(forced.language, 'en');

      final SubtitleCandidate plain =
          SubtitleRules.describe('Movie.zh-Hans.ass', '/m/Movie.zh-Hans.ass');
      expect(plain.language, isNotNull);

      final SubtitleCandidate none =
          SubtitleRules.describe('Movie.srt', '/m/Movie.srt');
      expect(none.flag, SubtitleFlag.none);
    });

    test('forced tracks sort before ordinary ones', () {
      final SubtitleCandidate forced =
          SubtitleRules.describe('Movie.en.forced.srt', 'forced');
      final SubtitleCandidate plain =
          SubtitleRules.describe('Movie.en.srt', 'plain');
      expect(forced.priority, lessThan(plain.priority));
    });

    test('format sniffing covers the common subtitle formats', () {
      expect(
        SubtitleRules.detectFormat('1\n00:00:01,000 --> 00:00:02,000\nHi'),
        SubtitleFormat.subRip,
      );
      expect(
        SubtitleRules.detectFormat('[Script Info]\nScriptType: v4.00+'),
        SubtitleFormat.ass,
      );
      expect(SubtitleRules.detectFormat('WEBVTT\n\n00:00.000'),
          SubtitleFormat.webVtt);
      expect(SubtitleRules.detectFormat('{100}{200}Hello'),
          SubtitleFormat.microdvd);
      expect(SubtitleRules.detectFormat('just prose'), isNull);
    });
  });
}
