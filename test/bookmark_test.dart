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
        BookmarkPolicy.decide(position: const Duration(minutes: 2, seconds: 59), total: hour),
        BookmarkDecision.ignore,
      );
      expect(
        BookmarkPolicy.decide(position: const Duration(minutes: 3), total: hour),
        BookmarkDecision.resume,
      );
    });

    test('the last eight percent counts as finished', () {
      // 8 % of an hour is 4:48, so 55:12 is exactly the boundary.
      expect(
        BookmarkPolicy.decide(position: const Duration(minutes: 55, seconds: 12), total: hour),
        BookmarkDecision.finished,
      );
      expect(
        BookmarkPolicy.decide(position: const Duration(minutes: 55, seconds: 11), total: hour),
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
        BookmarkPolicy.decide(position: const Duration(minutes: 10), total: Duration.zero),
        BookmarkDecision.ignore,
      );
      expect(
        BookmarkPolicy.decide(position: Duration.zero, total: Duration.zero),
        BookmarkDecision.ignore,
      );
    });
  });

  group('Bookmark', () {
    test('part way needs a length and a position inside it', () {
      const Bookmark fresh = Bookmark(at: Duration.zero, total: Duration(minutes: 90));
      expect(fresh.isSet, isTrue);
      expect(fresh.isPartWay, isFalse);

      const Bookmark unknown = Bookmark(at: Duration(minutes: 10), total: Duration.zero);
      expect(unknown.isSet, isFalse);
      expect(unknown.isPartWay, isFalse);
      expect(unknown.fraction, 0);

      const Bookmark midway = Bookmark(at: Duration(minutes: 30), total: Duration(minutes: 90));
      expect(midway.isPartWay, isTrue);
      expect(midway.fraction, closeTo(1 / 3, 1e-9));
    });

    test('fraction never exceeds one even if the position does', () {
      // Backends report a duration that drifts; a position past it must not
      // produce a progress bar wider than the bar.
      const Bookmark overshoot = Bookmark(at: Duration(minutes: 91), total: Duration(minutes: 90));
      expect(overshoot.fraction, 1.0);
    });

    test('round trips through JSON at second resolution', () {
      const Bookmark original = Bookmark(
        at: Duration(minutes: 12, seconds: 34),
        total: Duration(minutes: 90),
        kind: BookmarkKind.mark,
        part: 2,
      );
      final Bookmark? restored = Bookmark.fromJson(original.toJson());
      expect(restored, original);

      // A resume bookmark omits the default fields, so the file stays readable.
      const Bookmark plain = Bookmark(at: Duration(minutes: 1), total: Duration(minutes: 2));
      expect(plain.toJson().containsKey('kind'), isFalse);
      expect(Bookmark.fromJson(plain.toJson()), plain);
    });

    test('malformed JSON is rejected rather than guessed', () {
      expect(Bookmark.fromJson(null), isNull);
      expect(Bookmark.fromJson(<String, Object?>{'at': 5}), isNull);
      expect(Bookmark.fromJson('nonsense'), isNull);
    });
  });
}
