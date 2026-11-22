// Fetches a Windows x86-64 libmpv build and stages `libmpv-2.dll` in
// third_party/mpv/ so CMake/CI can copy it next to the executable.
//
//   dart run tool/fetch_libmpv.dart
//
// Pin a specific build with MPV_TAG=<release tag> (recommended for releases);
// otherwise the newest release is used.
//
// Which asset gets picked is spelled out in [_pick], not left to a wildcard:
// the release carries three x86_64 libmpv packages whose names all start with
// `mpv-dev` and all contain `x86_64`, and they differ in licence and in CPU
// requirements. See the comment on [_pick] for what each one is.

import 'dart:convert';
import 'dart:io';

const String _repo = 'zhongfly/mpv-winbuild';
const String _outDir = 'third_party/mpv';
const String _dllName = 'libmpv-2.dll';

/// Written next to the DLL so a build can be traced back to the exact asset it
/// came from.
///
/// `THIRD_PARTY_NOTICES.md` tells readers to check this file for the licence
/// that actually shipped, so it has to exist on the build machine — a licence
/// claim nobody can verify is worse than no claim at all.
const String _sourceName = 'SOURCE.txt';

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

  final List<_Asset> candidates = <_Asset>[];
  for (final Object? raw in assets) {
    if (raw is Map) {
      final _Asset? asset = _Asset.tryParse(raw.cast<String, dynamic>());
      if (asset != null) {
        candidates.add(asset);
      }
    }
  }
  final _Asset? chosen = _pick(candidates);
  final String tag = '${release['tag_name']}';
  if (chosen == null) {
    final bool onlyAvx2 = candidates.any((_Asset asset) => asset.avx2);
    throw StateError(
      onlyAvx2
          ? 'release $tag only ships AVX2 (v3) libmpv builds; refusing to '
              'stage one that cannot start on older CPUs'
          : 'no x86_64 libmpv build for $tag',
    );
  }

  final String name = chosen.name;
  final String url = chosen.url;
  stdout.writeln('[libmpv] asset $name (${chosen.licence})');
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
  File('$_outDir/$_sourceName').writeAsStringSync(
    'asset: $name\n'
    'tag: $tag\n'
    'licence: ${chosen.licence}\n'
    'source: $url\n',
  );
  stdout.writeln('[libmpv] staged ${target.path} (${target.lengthSync()} bytes)');

  try {
    tmp.deleteSync(recursive: true);
  } catch (_) {
    // Temp cleanup is best effort.
  }
}

/// One downloadable libmpv package.
///
/// Parsed from the asset name rather than re-matched per query, so the licence
/// this build will be distributed under is a property of the file that was
/// actually downloaded, not of a guess made from a wildcard.
class _Asset {
  const _Asset({
    required this.name,
    required this.url,
    required this.lgpl,
    required this.avx2,
  });

  final String name;
  final String url;

  /// True for `mpv-dev-lgpl-*`: libmpv LGPL-2.1-or-later with FFmpeg LGPLv3
  /// statically linked. False for `mpv-dev-*`: GPL-2.0-or-later throughout.
  final bool lgpl;

  /// True for the `-v3` variants, which are compiled for AVX2.
  final bool avx2;

  String get licence => lgpl
      ? 'LGPL-2.1-or-later (FFmpeg LGPL-3.0-or-later)'
      : 'GPL-2.0-or-later';

  /// Null when the asset is not a libmpv package we can use at all.
  static _Asset? tryParse(Map<String, dynamic> asset) {
    final Object? name = asset['name'];
    final Object? url = asset['browser_download_url'];
    if (name is! String || url is! String || !name.toLowerCase().endsWith('.7z')) {
      return null;
    }
    // `mpv-dev-…` is libmpv; `mpv-…` and `mpv-debug-…` are the full player and
    // a debug build, and neither contains the DLL we stage.
    if (!name.startsWith('mpv-dev-')) {
      return null;
    }
    final List<String> parts = name.substring(0, name.length - 3).split('-');
    if (!parts.contains('x86_64') || parts.contains('aarch64')) {
      return null;
    }
    return _Asset(
      name: name,
      url: url,
      lgpl: parts.contains('lgpl'),
      avx2: parts.contains('v3'),
    );
  }
}

/// Picks the asset to download, LGPL first, never the AVX2 build.
///
/// A release carries three x86_64 libmpv packages whose names all start with
/// `mpv-dev` and all contain `x86_64`:
///
///   mpv-dev-lgpl-x86_64-…      LGPL licence, baseline CPU
///   mpv-dev-x86_64-…           GPL licence, baseline CPU
///   mpv-dev-lgpl-x86_64-v3-…   LGPL licence, requires AVX2
///
/// The previous wildcard matched all three and took whichever came first, so
/// which licence shipped depended on the order of `release.assets` — not
/// something GitHub promises to keep. That is how a GPL build could replace the
/// LGPL one without a single line changing here.
///
/// `-v3` is refused instead of ranked last: it is the same licence and would
/// "work" on the build machine, then die inside `mpv_create` on an older CPU,
/// which the user has no way to tell apart from a broken install. Failing the
/// build is the honest outcome, so a release with only v3 assets throws.
_Asset? _pick(List<_Asset> assets) {
  final List<_Asset> baseline = assets.where((_Asset asset) => !asset.avx2).toList();
  for (final _Asset asset in baseline) {
    if (asset.lgpl) {
      return asset;
    }
  }
  return baseline.isEmpty ? null : baseline.first;
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
