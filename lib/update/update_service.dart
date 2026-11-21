import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_paths.dart';
import '../data/net.dart';
import 'update_channel.dart';

/// In-app updater for the three shipping channels.
///
/// Artifact types differ per channel:
/// - stable/beta: a Release with a **portable zip** (used for self-update) and
///   an installer. The updater deliberately picks the portable zip.
/// - dev: the newest `nightly-*` prerelease published by every beta push. Its
///   zip is an ordinary Release asset, so it downloads anonymously — the
///   Actions artifact endpoint requires a token even on a public repository,
///   which made dev updates impossible for a normal desktop install.
///
/// Data safety is structural: user data lives in [AppPaths.dataDir], which can
/// be a custom folder or the portable `userdata/` next to the exe. Updates only
/// replace files inside the install directory, exclude the data directory,
/// `data-dir.txt`, `updates/`, `log/` and the Inno Setup uninstaller, and keep
/// each extracted build under `<install>/updates/<version>/` so rollback is the
/// same path as forward.
class UpdateService {
  UpdateService({
    this.repository = '9thChasingWindGirl/XnX-Player',
    String? githubToken,
  }) : githubToken = githubToken ??
            Platform.environment['XNX_GITHUB_TOKEN'] ??
            '';

  final String repository;

  /// Needed only for dev artifacts; Release downloads are anonymous.
  final String githubToken;

  Map<String, String> get _apiHeaders => <String, String>{
        'Accept': 'application/vnd.github+json',
        if (githubToken.isNotEmpty) 'Authorization': 'Bearer $githubToken',
      };

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
  /// All three channels read Releases now. stable/beta pick from ordinary
  /// releases/prereleases; dev picks the newest `nightly-*` prerelease the beta
  /// workflow publishes. Reading artifacts here used to throw "needs token"
  /// because their download endpoint authenticates even on public repos.
  Future<UpdateCandidate?> fetchLatest(UpdateChannel channel) async {
    if (channel == UpdateChannel.dev) {
      return _fetchNightly();
    }
    final List<dynamic> releases = await Http.getJsonList(
      releasesUri,
      headers: _apiHeaders,
    );
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
      if (!name.endsWith('.zip')) {
        // The installer is a .exe; in-app updates always use the portable zip.
        continue;
      }
      // Prefer the explicitly portable asset; fall back to any zip so older
      // releases keep working.
      if (name.toLowerCase().contains('portable')) {
        assetUrl = asset['browser_download_url'] as String?;
        break;
      }
      assetUrl ??= asset['browser_download_url'] as String?;
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

  /// The newest `nightly-*` prerelease, if any. The beta workflow publishes one
  /// per successful push; the version is the tag minus its prefix and the zip
  /// rides as an ordinary release asset — anonymous-downloadable.
  Future<UpdateCandidate?> _fetchNightly() async {
    final List<dynamic> releases = await Http.getJsonList(
      releasesUri,
      headers: _apiHeaders,
    );
    final UpdateCandidate? best = pickNightly(releases);
    if (best == null) {
      return null;
    }
    return UpdateCandidate(
      version: best.version,
      name: best.name,
      assetUrl: best.assetUrl,
      notes: 'beta 分支自动构建（未验证）· 构建于 ${best.publishedAt}',
      publishedAt: best.publishedAt,
      isPrerelease: true,
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
    final ProcessResult result = await Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-Command',
        'Expand-Archive -Force -LiteralPath \'$zipPath\' -DestinationPath \'$versionDir\'',
      ],
    );
    if (result.exitCode != 0) {
      throw StateError('解压更新包失败：${result.stderr}');
    }
    // 解压后 zip 就没用了；留着会被下一次 apply 一起搬进安装目录。
    try {
      File(zipPath).deleteSync();
    } on Object {
      // 删不掉也不影响这次更新。
    }
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
    final String sep = Platform.pathSeparator;
    // If the user chose data inside the install directory (portable-style),
    // the swap must leave that top-level folder alone. data-dir.txt is also
    // preserved: it records where the data is, and the update package ships
    // its own copy for fresh installs only.
    final String dataDir = AppPaths.dataDir;
    String? dataSegment;
    final String prefix = install.endsWith(sep) ? install : '$install$sep';
    if (dataDir.toLowerCase().startsWith(prefix.toLowerCase())) {
      final String relative = dataDir.substring(prefix.length);
      final String first = relative.split(RegExp(r'[\\/]')).first;
      if (first.isNotEmpty) {
        dataSegment = first;
      }
    }
    final List<String> excluded = <String>[
      'updates',
      'log',
      'data-dir.txt',
      'apply_update.ps1',
      // Inno Setup 的卸载器属于安装记录，换掉它会让“应用和功能”里的条目失效。
      'unins*',
      if (dataSegment != null) dataSegment,
    ];
    final String excludeList = excluded
        .map((String name) => "'${name.replaceAll("'", "''")}'")
        .join(',');
    final String script = '$install${Platform.pathSeparator}updates'
        '${Platform.pathSeparator}apply_update.ps1';
    File(script).parent.createSync(recursive: true);
    File(script).writeAsStringSync('''
\$ErrorActionPreference = 'Stop'
\$payload = '$payloadDir'
\$install = '$install'
\$exe = Join-Path \$install 'xnx_player.exe'
\$self = \$MyInvocation.MyCommand.Path
\$exclude = @($excludeList)
Start-Sleep -Seconds 2
Get-ChildItem -LiteralPath \$install -Exclude \$exclude | ForEach-Object {
  \$target = Join-Path \$install \$_.Name
  if (\$_.PSIsContainer) {
    if (Test-Path \$target) { Remove-Item -Recurse -Force \$target }
  } else {
    Remove-Item -Force \$target
  }
}
# data-dir.txt 记录的是用户的现有数据位置，更新包里的那份只对全新解压有意义。
# updates/ 与 log/ 是运行时目录，覆盖它们会打断本次更新或清掉日志。
\$skip = @('data-dir.txt', 'updates', 'log')
Get-ChildItem -LiteralPath \$payload | Where-Object { \$skip -notcontains \$_.Name } | ForEach-Object {
  Copy-Item -LiteralPath \$_.FullName -Destination \$install -Recurse -Force
}
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
    final Uri uri = Uri.parse(url);
    final HttpClient client = HttpClient()
      ..userAgent = Http.userAgentHeader['User-Agent'];
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      if (githubToken.isNotEmpty && uri.host == 'api.github.com') {
        request.headers.set('Authorization', 'Bearer $githubToken');
        request.headers.set('Accept', 'application/vnd.github+json');
      }
      final HttpClientResponse response = await request.close();
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

  /// Picks the newest `nightly-*` release from a decoded release list.
  ///
  /// Kept pure so the dev-channel selection is testable without network: the
  /// tag prefix is stripped from [UpdateCandidate.version] and the highest
  /// version wins. Non-nightly releases (beta prereleases, stable) are ignored.
  static UpdateCandidate? pickNightly(List<dynamic> releases) {
    UpdateCandidate? best;
    for (final Object? entry in releases) {
      if (entry is! Map) {
        continue;
      }
      final Map<String, dynamic> release = entry.cast<String, dynamic>();
      final String tag = release['tag_name'] as String? ?? '';
      if (!tag.startsWith('nightly-')) {
        continue;
      }
      String? zipUrl;
      for (final Object? asset in release['assets'] as List<dynamic>? ?? <dynamic>[]) {
        if (asset is! Map) {
          continue;
        }
        final String name = asset['name'] as String? ?? '';
        if (name.endsWith('.zip')) {
          zipUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      final UpdateCandidate candidate = UpdateCandidate(
        version: tag.substring('nightly-'.length),
        name: release['name'] as String? ?? tag,
        assetUrl: zipUrl ?? '',
        publishedAt: release['published_at'] as String? ?? '',
        notes: release['body'] as String? ?? '',
        isPrerelease: true,
      );
      if (best == null || compareVersions(candidate.version, best.version) > 0) {
        best = candidate;
      }
    }
    return best;
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
