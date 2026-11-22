import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/core/bookmark.dart';

void main() {
  group('BookmarkPolicy', () {
    const Duration hour = Duration(hours: 1);

    test('a position inside the first minutes is not worth remembering', () {
      expect(
        BookmarkPolicy.decide(position: Duration.zero, total: hour),
        BookmarkDecision.ignore,
      );
      expect(
        BookmarkPolicy.decide(
          position: const Duration(minutes: 2, seconds: 59),
          total: hour,
        ),
        BookmarkDecision.ignore,
      );
      expect(
        BookmarkPolicy.decide(
          position: const Duration(minutes: 3),
          total: hour,
        ),
        BookmarkDecision.resume,
      );
    });

    test('the last eight percent counts as finished', () {
      // 8 % of an hour is 4:48, so 55:12 is exactly the boundary.
      expect(
        BookmarkPolicy.decide(
          position: const Duration(minutes: 55, seconds: 12),
          total: hour,
        ),
        BookmarkDecision.finished,
      );
      expect(
        BookmarkPolicy.decide(
          position: const Duration(minutes: 55, seconds: 11),
          total: hour,
        ),
        BookmarkDecision.resume,
      );
    });

    test('a short item watched to its end is finished, not ignored', () {
      // The end test has to run first: a two-minute clip is below the start
      // threshold for the whole of its runtime.
      expect(
        BookmarkPolicy.decide(
          position: const Duration(minutes: 1, seconds: 58),
          total: const Duration(minutes: 2),
        ),
        BookmarkDecision.finished,
      );
    });

    test('an unknown length is never a bookmark', () {
      expect(
        BookmarkPolicy.decide(
          position: const Duration(minutes: 10),
          total: Duration.zero,
        ),
        BookmarkDecision.ignore,
      );
      expect(
        BookmarkPolicy.decide(position: Duration.zero, total: Duration.zero),
        BookmarkDecision.ignore,
      );
    });

    test('a position past the reported length is still finished', () {
      // Backends report durations that drift by a few seconds; a position the
      // player has run past must not fall through to "resume".
      expect(
        BookmarkPolicy.decide(
          position: const Duration(minutes: 61),
          total: hour,
        ),
        BookmarkDecision.finished,
      );
    });
  });
}
