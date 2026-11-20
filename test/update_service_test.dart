import 'package:flutter_test/flutter_test.dart';
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
}
