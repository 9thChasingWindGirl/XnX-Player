// Fetches a Windows x86-64 libmpv build and stages `libmpv-2.dll` in
// third_party/mpv/ so CMake/CI can copy it next to the executable.
//
//   dart run tool/fetch_libmpv.dart
//
// Pin a specific build with MPV_TAG=<release tag> (recommended for releases);
// otherwise the latest LGPL dev build is used.

import 'dart:convert';
import 'dart:io';

const String _repo = 'zhongfly/mpv-winbuild';
const String _outDir = 'third_party/mpv';
const String _dllName = 'libmpv-2.dll';

Future<void> main(List<String> args) async {
  final File target = File('$_outDir/$_dllName');
  if (target.existsSync() && !args.contains('--force')) {
    stdout.writeln('[libmpv] already present: ${target.path}');
    return;
  }

  final String? pinned = Platform.environment['MPV_TAG'];
  final Uri releaseUri = (pinned == null || pinned.isEmpty)
      ? Uri.parse('https://api.github.com/repos/$_repo/releases/latest')
      : Uri.parse('https://api.github.com/repos/$_repo/releases/tags/$pinned');

  stdout.writeln('[libmpv] resolving $releaseUri');
  final Map<String, dynamic> release = await _getJson(releaseUri);
  final Object? assets = release['assets'];
  if (assets is! List) {
    throw StateError('release has no assets');
  }

  final RegExp pattern = RegExp(r'^mpv-dev.*x86_64.*\.7z$', caseSensitive: false);
  Map<String, dynamic>? chosen;
  for (final Object? asset in assets) {
    if (asset is! Map) {
      continue;
    }
    final Object? name = asset['name'];
    if (name is String && pattern.hasMatch(name)) {
      chosen = asset.cast<String, dynamic>();
      break;
    }
  }
  if (chosen == null) {
    throw StateError('no mpv-dev x86_64 .7z asset in ${release['tag_name']}');
  }

  final String name = chosen['name'] as String;
  final String url = chosen['browser_download_url'] as String;
  final Directory tmp = Directory.systemTemp.createTempSync('xnx_mpv_');
  final File archive = File('${tmp.path}/$name');

  stdout.writeln('[libmpv] downloading $name');
  await _download(Uri.parse(url), archive);

  stdout.writeln('[libmpv] extracting');
  final Directory extractDir = Directory('${tmp.path}/x')..createSync(recursive: true);
  final bool ok = await _extract(archive, extractDir);
  if (!ok) {
    throw StateError('failed to extract $name (需要 7z 或 bsdtar)');
  }

  File? dll;
  for (final FileSystemEntity entity in extractDir.listSync(recursive: true)) {
    if (entity is File && entity.path.toLowerCase().endsWith(_dllName)) {
      dll = entity;
      break;
    }
  }
  if (dll == null) {
    throw StateError('$_dllName not found inside $name');
  }

  Directory(_outDir).createSync(recursive: true);
  dll.copySync(target.path);
  stdout.writeln('[libmpv] staged ${target.path} (${target.lengthSync()} bytes)');

  try {
    tmp.deleteSync(recursive: true);
  } catch (_) {
    // Temp cleanup is best effort.
  }
}

Future<Map<String, dynamic>> _getJson(Uri uri) async {
  final HttpClient client = HttpClient()..userAgent = 'xnx-player-build';
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final String? token = Platform.environment['GITHUB_TOKEN'];
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}: $body');
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('unexpected release payload');
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

Future<void> _download(Uri uri, File file) async {
  final HttpClient client = HttpClient()..userAgent = 'xnx-player-build';
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    final HttpClientResponse response = await request.close();
    if (response.statusCode != 200) {
      throw StateError('download failed: HTTP ${response.statusCode}');
    }
    final IOSink sink = file.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }
  } finally {
    client.close(force: true);
  }
}

Future<bool> _extract(File archive, Directory destination) async {
  final List<String> executables = <String>[
    r'C:\Program Files\7-Zip\7z.exe',
    r'C:\Program Files (x86)\7-Zip\7z.exe',
    '7z',
  ];

  for (final String exe in executables) {
    try {
      final ProcessResult result = await Process.run(
        exe,
        <String>['x', archive.path, '-o${destination.path}', '-y'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        return true;
      }
    } catch (_) {
      continue;
    }
  }

  try {
    final ProcessResult result = await Process.run(
      'tar',
      <String>['-xf', archive.path, '-C', destination.path],
      runInShell: true,
    );
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
