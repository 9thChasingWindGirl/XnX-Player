import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/sources/resolved_media.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 11, 22, 12);

  group('ResolvedMedia', () {
    test('a link without an expiry never expires', () {
      const ResolvedMedia local = ResolvedMedia(uri: r'C:\Films\A.mkv');
      expect(local.isTemporary, isFalse);
      expect(local.isExpiredAt(now), isFalse);
      expect(local.remainingAt(now), isNull);
      expect(local.hasHeaders, isFalse);
    });

    test('a signed link expires on time, not before', () {
      final ResolvedMedia signed = ResolvedMedia(
        uri: 'https://cdn.example/a.mkv?sign=x',
        expiresAt: now.add(const Duration(hours: 2)),
      );
      expect(signed.isTemporary, isTrue);
      expect(signed.isExpiredAt(now), isFalse);
      expect(signed.isExpiredAt(now.add(const Duration(minutes: 119))), isFalse);
      expect(signed.isExpiredAt(now.add(const Duration(hours: 2))), isTrue);
      expect(signed.isExpiredAt(now.add(const Duration(hours: 3))), isTrue);
      expect(signed.remainingAt(now), const Duration(hours: 2));
      // Clamped, never negative: callers use this to decide "refresh now".
      expect(signed.remainingAt(now.add(const Duration(hours: 5))), Duration.zero);
    });

    test('headers take part in equality', () {
      const ResolvedMedia plain = ResolvedMedia(uri: 'https://example/a.mkv');
      const ResolvedMedia withAuth = ResolvedMedia(
        uri: 'https://example/a.mkv',
        headers: <String, String>{'Authorization': 'Basic abc'},
      );
      expect(plain, isNot(withAuth));
      expect(withAuth.hasHeaders, isTrue);
      expect(
        const ResolvedMedia(
          uri: 'https://example/a.mkv',
          headers: <String, String>{'Authorization': 'Basic abc'},
        ),
        withAuth,
      );
    });

    test('copyWith keeps what it is not given', () {
      final ResolvedMedia original = ResolvedMedia(
        uri: 'https://example/a.mkv',
        headers: const <String, String>{'X-Key': '1'},
        expiresAt: now.add(const Duration(minutes: 10)),
      );
      final ResolvedMedia moved = original.copyWith(uri: 'https://example/b.mkv');
      expect(moved.uri, 'https://example/b.mkv');
      expect(moved.headers, original.headers);
      expect(moved.expiresAt, original.expiresAt);
    });
  });
}
