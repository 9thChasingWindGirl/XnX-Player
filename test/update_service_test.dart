import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/update/update_channel.dart';
import 'package:xnx_player/update/update_service.dart';

void main() {
  group('update endpoints', () {
    // 更新检查曾对每个用户都返回 404：`Uri.replace(path: ...)` 的参数是路径，
    // 不是 URL。把 `$_apiBase` 插进去会得到
    // `.../repos/x/yhttps://api.github.com/...`；把 `?per_page=` 塞进 path
    // 又会被百分号编码成 `%3F`。两种形状在 GitHub 上都指向不存在的路径。
    test('release listing is a plain path with a real query string', () {
      final UpdateService service = UpdateService();
      final Uri uri = service.releasesUri;

      expect(uri.host, 'api.github.com');
      expect(
        uri.path,
        '/repos/9thChasingWindGirl/XnX-Player/releases',
      );
      expect(uri.queryParameters['per_page'], '30');
      expect(uri.toString(), isNot(contains('%3F')));
      // The old code interpolated the whole URL into `path:`, which the Uri
      // parser then escaped into a single nonsense segment.
      expect(uri.path, isNot(contains('http')));
    });

    test('repository is configurable without breaking the path', () {
      final UpdateService service = UpdateService(repository: 'owner/name');
      final Uri uri = service.releasesUri;

      expect(uri.path, '/repos/owner/name/releases');
      expect(uri.queryParameters['per_page'], '30');
    });
  });

  group('dev channel nightly selection', () {
    // dev used to read Actions artifacts, whose download endpoint requires a
    // token even on public repos — a normal desktop install could never
    // self-update. Release assets are anonymous, so nightly tags are the
    // single source now.
    test('picks the highest nightly and strips the tag prefix', () {
      final List<dynamic> releases = <dynamic>[
        <String, dynamic>{
          'tag_name': 'v1.00.00',
          'name': 'stable',
          'prerelease': false,
        },
        <String, dynamic>{
          'tag_name': 'nightly-0.00.02.Dev',
          'name': 'Dev 0.00.02.Dev',
          'prerelease': true,
          'published_at': '2026-11-21T00:00:00Z',
          'assets': <dynamic>[
            <String, dynamic>{
              'name': 'XnX-Player-Portable-0.00.02.Dev.zip',
              'browser_download_url': 'https://example/nightly2.zip',
            },
          ],
        },
        <String, dynamic>{
          'tag_name': 'nightly-0.00.03.Dev',
          'name': 'Dev 0.00.03.Dev',
          'prerelease': true,
          'published_at': '2026-11-22T00:00:00Z',
          'assets': <dynamic>[
            <String, dynamic>{
              'name': 'XnX-Player-Portable-0.00.03.Dev.zip',
              'browser_download_url': 'https://example/nightly3.zip',
            },
          ],
        },
      ];

      final UpdateCandidate? picked = UpdateService.pickNightly(releases);

      expect(picked, isNotNull);
      final UpdateCandidate best = picked!;
      expect(best.version, '0.00.03.Dev');
      expect(best.assetUrl, 'https://example/nightly3.zip');
      expect(best.isPrerelease, isTrue);
    });

    test('returns null when no nightly release exists', () {
      expect(
        UpdateService.pickNightly(<dynamic>[
          <String, dynamic>{'tag_name': 'v1.00.00', 'prerelease': false},
        ]),
        isNull,
      );
    });
  });
}
