import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/net.dart';
import 'update_channel.dart';

/// In-app updater for the three shipping channels.
///
/// Data safety is structural: everything the user owns (state.json, scripts)
/// lives in `%APPDATA%\XnX Player`, which no update ever touches. Updates only
/// replace files inside the install directory, and each applied version keeps
/// its extracted build under `<install>/updates/<version>/` so rolling back is
/// the same code path as installing forward.
class UpdateService {
  UpdateService({this.repository = '9thChasingWindGirl/XnX-Player'});

  final String repository;

  static const UpdateChannel defaultChannel = UpdateChannel.stable;

  Uri get _apiBase => Uri.parse('https://api.github.com/repos/$repository');

  /// GitHub REST endpoint under this repo, built from path *segments*.
  ///
  /// `Uri.replace(path: ...)` takes a path, not a URL: interpolating
  /// `$_apiBase` into it produced `.../repos/x/yhttps://api.github.com/...`,
  /// and putting `?per_page=` inside the path got the `?` percent-encoded to
  /// `%3F`. Both shapes hit the API as a path that does not exist, which is
  /// exactly the HTTP 404 更新检查 was reporting.
  Uri _endpoint(List<String> segments, [Map<String, String>? query]) =>
      _apiBase.replace(
        pathSegments: <String>[..._apiBase.pathSegments, ...segments],
        queryParameters: query,
      );

  /// The exact URL [fetchLatest] calls for the stable/beta channels.
  ///
  /// Public so a test can assert the shape: this path silently produced a 404
  /// for every user, and a unit test is the only place that can catch the next
  /// time someone "tidies up" the URL.
  @visibleForTesting
  Uri get releasesUri =>
      _endpoint(<String>['releases'], <String, String>{'per_page': '30'});

  /// Asks GitHub what the newest build on [channel] is.
  ///
  /// stable/beta read Releases (beta = prerelease); dev reads the newest
  /// successful Actions artifact on the beta branch — that build exists before
  /// anyone has validated it, which is exactly what the channel means.
  Future<UpdateCandidate?> fetchLatest(UpdateChannel channel) async {
    if (channel == UpdateChannel.dev) {
      return _fetchDevArtifact();
    }
    final List<dynamic> releases =
        await Http.getJson(releasesUri) as List<dynamic>;
    final List<UpdateCandidate> parsed = releases.map((Object? entry) {
      final Map<String, dynamic> release = entry! as Map<String, dynamic>;
      return _releaseCandidate(release);
    }).toList(growable: false);
    return pickRelease(parsed, channel);
  }

  UpdateCandidate _releaseCandidate(Map<String, dynamic> release) {
    final String tag = release['tag_name'] as String? ?? '';
    String? assetUrl;
    for (final Object? entry in release['assets'] as List<dynamic>? ?? <dynamic>[]) {
      final Map<String, dynamic> asset = entry! as Map<String, dynamic>;
      final String name = asset['name'] as String? ?? '';
      if (name.endsWith('.zip')) {
        assetUrl = asset['browser_download_url'] as String?;
        break;
      }
    }
    return UpdateCandidate(
      version: tag,
      name: release['name'] as String? ?? tag,
      assetUrl: assetUrl ?? '',
      notes: release['body'] as String? ?? '',
      publishedAt: release['published_at'] as String? ?? '',
      isPrerelease: release['prerelease'] as bool? ?? false,
    );
  }

  Future<UpdateCandidate?> _fetchDevArtifact() async {
    final Map<String, dynamic> payload = await Http.getJson(
      _endpoint(
        <String>['actions', 'artifacts'],
        <String, String>{
          'branch': 'beta',
          'status': 'success',
          'per_page': '30',
        },
      ),
    );
    final List<dynamic> artifacts = payload['artifacts'] as List<dynamic>? ?? <dynamic>[];
    Map<String, dynamic>? best;
    for (final Object? entry in artifacts) {
      final Map<String, dynamic> artifact = entry! as Map<String, dynamic>;
      if (best == null) {
        best = artifact;
        continue;
      }
      final DateTime current = DateTime.parse(
        best['created_at'] as String? ?? '1970-01-01T00:00:00Z',
      );
      final DateTime candidate = DateTime.parse(
        artifact['created_at'] as String? ?? '1970-01-01T00:00:00Z',
      );
      if (candidate.isAfter(current)) {
        best = artifact;
      }
    }
    if (best == null) {
      return null;
    }
    final String name = best['name'] as String? ?? '';
    return UpdateCandidate(
      version: 'dev-${best['id']}-$name',
      name: 'Dev 构建 #$name',
      assetUrl: '$_apiBase/actions/artifacts/${best['id']}/zip',
      notes: 'beta 分支 Actions 未验证产物（构建于 ${best['created_at']}）',
      publishedAt: best['created_at'] as String? ?? '',
    );
  }

  /// Downloads and unpacks the candidate into
  /// `<install>/updates/<version>/`, returning the payload directory that
  /// `apply` would copy over the install directory.
  Future<String> prepareInstall(UpdateCandidate candidate) async {
    final String root = _updateRoot();
    final String versionDir = '$root${Platform.pathSeparator}'
        '${_safeName(candidate.version)}';
    Directory(versionDir).createSync(recursive: true);
    final String zipPath = '$versionDir${Platform.pathSeparator}update.zip';
    await _download(candidate.assetUrl, zipPath);
    await Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-Command',
        'Expand-Archive -Force -LiteralPath \'$zipPath\' -DestinationPath \'$versionDir\'',
      ],
    ).then((ProcessResult result) {
      if (result.exitCode != 0) {
        throw StateError('解压更新包失败：${result.stderr}');
      }
    });
    final Directory? payload = _payloadDir(versionDir);
    if (payload == null) {
      throw StateError('更新包里没有可执行文件');
    }
    return payload.path;
  }

  /// Returns the payload directory of a previously prepared version, for
  /// rollback. Same contract as [prepareInstall]; the version must already
  /// exist under `updates/`.
  Future<String> prepareInstalled(String version) async {
    final String versionDir = '${_updateRoot()}'
        '${Platform.pathSeparator}${_safeName(version)}';
    final Directory? payload = _payloadDir(versionDir);
    if (payload == null) {
      throw StateError('该版本没有已解压的本地副本：$version');
    }
    return payload.path;
  }

  /// Stages a restart-and-swap: a small PowerShell script waits for this
  /// process to exit, copies the new build over the install directory while
  /// excluding `updates/` and `log/`, then starts the new exe.
  ///
  /// Rollback uses the same entry point with an older payload dir — user data
  /// in `%APPDATA%` is never part of the swap.
  Future<void> apply(String payloadDir) async {
    final String install = File(Platform.resolvedExecutable).parent.path;
    final String script = '$install${Platform.pathSeparator}updates'
        '${Platform.pathSeparator}apply_update.ps1';
    File(script).parent.createSync(recursive: true);
    File(script).writeAsStringSync('''
\$ErrorActionPreference = 'Stop'
\$payload = '$payloadDir'
\$install = '$install'
\$exe = Join-Path \$install 'xnx_player.exe'
\$self = \$MyInvocation.MyCommand.Path
Start-Sleep -Seconds 2
Get-ChildItem -LiteralPath \$install -Exclude updates,log,apply_update.ps1 | ForEach-Object {
  \$target = Join-Path \$install \$_.Name
  if (\$_.PSIsContainer) {
    if (Test-Path \$target) { Remove-Item -Recurse -Force \$target }
  } else {
    Remove-Item -Force \$target
  }
}
Copy-Item -Recurse -Force (Join-Path \$payload '*') \$install
Start-Process -FilePath \$exe
Remove-Item -Force \$self
''');
    await Process.start(
      'powershell.exe',
      <String>['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script],
      mode: ProcessStartMode.detached,
    );
    debugPrint('update staged from $payloadDir');
    exit(0);
  }

  /// Versions that already have an extracted build on disk, newest first —
  /// the rollback menu.
  List<String> installedVersions() {
    final Directory root = Directory(_updateRoot());
    if (!root.existsSync()) {
      return <String>[];
    }
    return root
        .listSync()
        .whereType<Directory>()
        .where((Directory dir) => _payloadDir(dir.path) != null)
        .map((Directory dir) => dir.uri.pathSegments.last)
        .toList()
      ..sort((String a, String b) => compareVersions(b, a));
  }

  String _updateRoot() {
    final String install = File(Platform.resolvedExecutable).parent.path;
    return '$install${Platform.pathSeparator}updates';
  }

  Directory? _payloadDir(String versionDir) {
    final Directory dir = Directory(versionDir);
    for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.exe')) {
        return dir;
      }
    }
    return null;
  }

  Future<void> _download(String url, String target) async {
    final HttpClient client = HttpClient()
      ..userAgent = Http.userAgentHeader['User-Agent'];
    try {
      final HttpClientResponse response =
          await (await client.getUrl(Uri.parse(url))).close();
      if (response.statusCode != 200) {
        throw HttpFailure('下载失败', status: response.statusCode);
      }
      final IOSink sink = File(target).openWrite();
      await response.pipe(sink);
    } finally {
      client.close(force: true);
    }
  }

  static String _safeName(String version) =>
      version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Convenience: latest candidate for a channel as JSON, for the UI layer.
  Future<Map<String, dynamic>?> fetchLatestJson(UpdateChannel channel) async {
    final UpdateCandidate? candidate = await fetchLatest(channel);
    return candidate?.toJson();
  }

  /// Parses an artifact/release list body — kept small and testable.
  static List<UpdateCandidate> parseReleases(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! List<dynamic>) {
      return <UpdateCandidate>[];
    }
    return decoded.map((Object? entry) {
      final Map<String, dynamic> release = entry! as Map<String, dynamic>;
      return UpdateCandidate(
        version: release['tag_name'] as String? ?? '',
        name: release['name'] as String? ?? '',
        isPrerelease: release['prerelease'] as bool? ?? false,
      );
    }).toList(growable: false);
  }
}
