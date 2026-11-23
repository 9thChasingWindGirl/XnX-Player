import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import '../core/app_paths.dart';
import '../core/notice_center.dart';
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
/// How this copy of the app got onto the machine.
///
/// The distinction decides which update package a user may take: an installed
/// copy must update through the setup program so the uninstall entry, shortcut
/// and registry stay correct; a portable copy replaces files in place and may
/// opt into the installer.
enum InstallKind { portable, installed }

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

  /// Every release that belongs to [channel], newest first — the list behind
  /// the rollback picker. Same listing [fetchLatest] reads; only the filter
  /// and the ordering differ. Versions without a portable zip are dropped:
  /// an entry the app cannot download is noise in a picker.
  Future<List<UpdateCandidate>> fetchHistory(UpdateChannel channel) async {
    final List<dynamic> releases = await Http.getJsonList(
      releasesUri,
      headers: _apiHeaders,
    );
    final List<UpdateCandidate> parsed = <UpdateCandidate>[];
    for (final Object? entry in releases) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final UpdateCandidate candidate = _releaseCandidate(entry);
      if (candidate.assetUrl.isEmpty) {
        continue;
      }
      if (!belongsToChannel(candidate.version, candidate.isPrerelease, channel)) {
        continue;
      }
      parsed.add(candidate);
    }
    parsed.sort(
      (UpdateCandidate a, UpdateCandidate b) =>
          compareVersions(b.version, a.version),
    );
    return parsed;
  }

  UpdateCandidate _releaseCandidate(Map<String, dynamic> release) {
    final String tag = release['tag_name'] as String? ?? '';
    String? zipUrl;
    String? exeUrl;
    for (final Object? entry in release['assets'] as List<dynamic>? ?? <dynamic>[]) {
      final Object? raw = entry;
      if (raw is! Map) {
        continue;
      }
      final Map<Object?, Object?> asset = raw;
      final String name = asset['name'] as String? ?? '';
      final String lower = name.toLowerCase();
      final String? url = asset['browser_download_url'] as String?;
      if (lower.endsWith('.exe')) {
        // The setup program. An installed copy needs it; a portable copy may
        // choose it. Keep scanning: the zip may come after it in the list.
        exeUrl ??= url;
        continue;
      }
      if (!lower.endsWith('.zip')) {
        continue;
      }
      // Prefer the explicitly portable asset; fall back to any zip so older
      // releases keep working.
      if (lower.contains('portable')) {
        zipUrl = url ?? zipUrl;
      } else {
        zipUrl ??= url;
      }
    }
    return UpdateCandidate(
      version: tag,
      name: release['name'] as String? ?? tag,
      assetUrl: zipUrl ?? '',
      installerUrl: exeUrl ?? '',
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
  ///
  /// 已解包完整的版本直接复用：重复点"安装"不再重新下载，堆积的目录
  /// 也就没有了"每试一次堆一层"的来源。
  Future<String> prepareInstall(
    UpdateCandidate candidate, {
    void Function(int received, int total)? onProgress,
  }) async {
    final String root = _updateRoot();
    final String versionDir = '$root${Platform.pathSeparator}'
        '${_safeName(candidate.version)}';
    final Directory? ready = _payloadDir(versionDir);
    if (ready != null) {
      AppLog.info('更新包已就绪，复用 ${ready.path}');
      return ready.path;
    }
    Directory(versionDir).createSync(recursive: true);
    final String zipPath = '$versionDir${Platform.pathSeparator}update.zip';
    await _download(candidate.assetUrl, zipPath, onProgress: onProgress);
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

  /// True when user data lives inside the install folder (a portable layout).
  ///
  /// That is the only arrangement an in-place swap can plausibly damage, so it
  /// is also the only one worth asking the user about.
  bool get isPortable {
    final String install = AppPaths.installDir.toLowerCase();
    final String data = AppPaths.dataDir.toLowerCase();
    final String sep = Platform.pathSeparator;
    final String prefix = install.endsWith(sep) ? install : '$install$sep';
    // The separator matters: `C:\app` must not claim `C:\appdata` as inside it.
    return data.startsWith(prefix);
  }

  /// True when this process is running from a rollback snapshot rather than
  /// the real install root.
  ///
  /// `<install>/updates/<version>/` deliberately holds a *complete* portable
  /// build so rollback can swap it back. Starting that exe makes every path
  /// (install root, data dir, next download) relative to the snapshot, so each
  /// update nests another whole app inside it.
  bool get isSnapshotLaunch => snapshotRoot() != null;

  /// The real install root when running from a snapshot, else null.
  ///
  /// Guarded three ways so a user who simply installed into a folder named
  /// `updates` is not misidentified: the segment must be followed by a
  /// version-shaped directory, and the candidate root must contain the main
  /// exe. Only the first `updates` segment counts, which also handles an
  /// already-nested launch.
  static String? snapshotRoot() {
    final String exeDir = File(Platform.resolvedExecutable).parent.path;
    final List<String> parts = exeDir.split(Platform.pathSeparator);
    for (int i = 0; i < parts.length - 1; i++) {
      if (parts[i].toLowerCase() != 'updates') {
        continue;
      }
      if (!RegExp(
        r'^\d+\.\d+\.\d+(\.(Dev|Beta))?$',
        caseSensitive: false,
      ).hasMatch(parts[i + 1])) {
        continue;
      }
      final String root = parts.sublist(0, i).join(Platform.pathSeparator);
      if (File('$root${Platform.pathSeparator}xnx_player.exe').existsSync()) {
        return root;
      }
    }
    return null;
  }

  /// Call once at startup: a bad launch should be visible, not just logged.
  static void reportSnapshotLaunch() {
    final String? root = snapshotRoot();
    if (root == null) {
      return;
    }
    AppLog.warn('正在从更新备份目录启动：${Platform.resolvedExecutable}；'
        '正确位置是 $root');
    NoticeCenter.instance.publish(
      'snapshot-launch',
      '正在从更新备份目录启动',
      body: '请改从 $root${Platform.pathSeparator}xnx_player.exe 启动；'
          '在备份目录里更新会不断生成嵌套的便携版副本。'
          '应用内更新已暂时停用。',
      kind: NoticeKind.warning,
    );
  }

  /// Whether this copy is managed by the Inno setup program.
  ///
  /// The uninstaller (`unins000.exe`) is written next to the exe by the setup
  /// and by nothing else, so its presence is the one reliable signal. A folder
  /// that cannot be read is treated as portable, which never touches the
  /// registry.
  InstallKind get installKind {
    try {
      for (final FileSystemEntity entity
          in Directory(AppPaths.installDir).listSync(recursive: false)) {
        final String name = entity.uri.pathSegments.last.toLowerCase();
        if (name.startsWith('unins') && name.endsWith('.exe')) {
          return InstallKind.installed;
        }
      }
    } on Object {
      // Unreadable folder: fall through.
    }
    return InstallKind.portable;
  }

  /// Downloads the setup program for [candidate] and returns its path.
  Future<String> prepareInstaller(
    UpdateCandidate candidate, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!candidate.hasInstaller) {
      throw StateError('该版本没有提供安装包，请改用便携更新');
    }
    final String dir = '${_updateRoot()}${Platform.pathSeparator}'
        '${_safeName(candidate.version)}';
    Directory(dir).createSync(recursive: true);
    final String path = '$dir${Platform.pathSeparator}'
        'XnX-Player-Setup-${_safeName(candidate.version)}.exe';
    await _download(candidate.installerUrl, path, onProgress: onProgress);
    return path;
  }

  /// Hands over to the setup program and exits.
  ///
  /// Deliberately not silent: the wizard is the "mini install" the user asked
  /// for, and it is also where the data folder is confirmed — the installer
  /// preselects the existing one, so an update keeps the library where it is.
  /// `/CLOSEAPPLICATIONS` lets the setup shut this process through Restart
  /// Manager instead of failing on a locked exe.
  Future<void> applyInstaller(String setupPath) async {
    await Process.start(
      setupPath,
      <String>['/CLOSEAPPLICATIONS', '/NORESTART'],
      mode: ProcessStartMode.detached,
    );
    debugPrint('installer launched from $setupPath');
    exit(0);
  }

  /// Stages a restart-and-swap by restarting THIS executable in updater mode
  /// (`--apply-update`). The updater is a small visible window: it waits for
  /// this process to exit, sweeps the install directory, copies the payload
  /// with a real progress bar, starts the new build and reports the result.
  /// The old apply_update.ps1 was invisible on purpose and silent on failure —
  /// a locked file killed it mid-copy, leaving the old version running, the
  /// payload stranded in `updates/` and the user with no idea what happened.
  ///
  /// [keepUserData] defaults to true: replacing a config the user built up
  /// with the package defaults is never a silent decision. When it is false
  /// the updater removes `state.json` after the swap, so the new build starts
  /// clean on purpose.
  Future<void> apply(String payloadDir, {bool keepUserData = true}) async {
    final String dataDir = AppPaths.dataDir;
    await Process.start(
      Platform.resolvedExecutable,
      <String>[
        '--apply-update',
        payloadDir,
        '--data-dir',
        dataDir,
        '--keep-data',
        keepUserData ? 'true' : 'false',
      ],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  /// Removes a downloaded update the user chose not to apply now. Leaving it
  /// in `updates/` is how the directory grew four versions deep — every
  /// attempt re-downloaded and none of them ever finished applying.
  void discardDownload(String version) {
    try {
      final Directory dir = Directory(
        '${_updateRoot()}${Platform.pathSeparator}${_safeName(version)}',
      );
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } on Object {
      // 缓存清理失败无害：下次启动的 pruneUpdateCache 会再收一次。
    }
  }

  /// 启动时清理 updates/ 的堆积：历史版本目录、旧脚本、.updating 残留。
  /// snapshot 启动（exe 就在 updates/ 里）时跳过——清掉的是正在运行的家。
  /// 正常启动则可以放心清：这些只是下载缓存，当前版本不在其中。
  static void pruneUpdateCache() {
    if (snapshotRoot() != null) {
      return;
    }
    try {
      final Directory root = Directory(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}updates',
      );
      if (!root.existsSync()) {
        return;
      }
      for (final FileSystemEntity entity in root.listSync()) {
        final String name = entity.uri.pathSegments.last.toLowerCase();
        final bool stale = name == 'apply_update.ps1' ||
            name.endsWith('.updating') ||
            (entity is Directory && RegExp(r'^\d+\.\d+').hasMatch(name));
        if (stale) {
          try {
            entity.deleteSync(recursive: true);
          } on Object {
            // 锁定（例如用户手动从缓存目录启动过）就留给下一次启动。
          }
        }
      }
    } on Object {
      // 清理失败无害——堆积只是磁盘占用，不影响功能。
    }
  }

  String _updateRoot() {
    final String install = File(Platform.resolvedExecutable).parent.path;
    return '$install${Platform.pathSeparator}updates';
  }

  Directory? _payloadDir(String versionDir) {
    final Directory dir = Directory(versionDir);
    if (!dir.existsSync()) {
      return null;
    }
    try {
      // Return the directory that actually holds the exe, not the extraction
      // root. An archive that wraps the build in a folder would otherwise copy
      // that wrapper folder into the install directory — one more whole app.
      // Take the shallowest match so an already-nested `updates/<version>`
      // inside a snapshot cannot win.
      File? best;
      int bestDepth = 1 << 30;
      for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('xnx_player.exe')) {
          continue;
        }
        final int depth =
            entity.path.split(Platform.pathSeparator).length;
        if (depth < bestDepth) {
          bestDepth = depth;
          best = entity;
        }
      }
      return best?.parent;
    } on Object {
      return null;
    }
  }

  /// Downloads [url] into [target], retrying a failed transfer.
  ///
  /// A release asset is tens of megabytes over a link that is often the reason
  /// the check was slow in the first place, so this is deliberately more
  /// patient than the JSON calls: a system proxy is honoured (a user who needs
  /// one to reach GitHub has already configured it), the connection gets 30 s
  /// and a stalled body 90 s, and a dropped transfer starts over instead of
  /// leaving half a zip to fail Expand-Archive later.
  Future<void> _download(
    String url,
    String target, {
    void Function(int received, int total)? onProgress,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      if (attempt > 1) {
        await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
        try {
          final File partial = File(target);
          if (partial.existsSync()) {
            partial.deleteSync();
          }
        } on Object {
          // A stuck handle only costs a full re-download.
        }
      }
      final HttpClient client = HttpClient()
        ..userAgent = Http.userAgentHeader['User-Agent']
        // `api.github.com` often answers while `objects.githubusercontent.com`
        // (where release assets live) does not. Honouring a proxy is therefore
        // the difference between "checked fine" and "download impossible".
        ..findProxy = _proxyFor
        ..connectionTimeout = const Duration(seconds: 30);
      try {
        final Uri uri = Uri.parse(_mirrored(url));
        final HttpClientRequest request = await client.getUrl(uri);
        if (githubToken.isNotEmpty && uri.host == 'api.github.com') {
          request.headers.set('Authorization', 'Bearer $githubToken');
          request.headers.set('Accept', 'application/vnd.github+json');
        }
        final HttpClientResponse response =
            await request.close().timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) {
          throw HttpFailure('下载失败', status: response.statusCode);
        }
        final int total = response.contentLength;
        final IOSink sink = File(target).openWrite();
        int received = 0;
        try {
          await for (final List<int> chunk
              in response.timeout(const Duration(seconds: 90))) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        return;
      } on Object catch (error) {
        lastError = error;
      } finally {
        client.close(force: true);
      }
    }
    throw StateError(
      '下载更新包失败（已重试 3 次）：$lastError\n'
      '若网络无法直连 GitHub，可设置环境变量 XNX_UPDATE_PROXY（如 127.0.0.1:7890）'
      '或 XNX_UPDATE_MIRROR（镜像前缀）。',
    );
  }

  /// Proxy for a request: the explicit override first, then the environment.
  ///
  /// Dart does not read the Windows "Internet options" proxy, so an explicit
  /// variable is the only dependable hook for a user who set it system-wide.
  static String _proxyFor(Uri uri) {
    final String explicit = (Platform.environment['XNX_UPDATE_PROXY'] ?? '').trim();
    if (explicit.isNotEmpty) {
      return 'PROXY $explicit';
    }
    return HttpClient.findProxyFromEnvironment(uri);
  }

  /// Optional prefix for asset downloads (a GitHub mirror).
  ///
  /// Release assets are served from a host that is commonly unreachable on some
  /// networks while the API itself works. A prefix is the only remedy that does
  /// not require shipping a proxy; empty by default so the official host is
  /// what everyone else gets.
  static String _mirrored(String url) {
    final String prefix = (Platform.environment['XNX_UPDATE_MIRROR'] ?? '').trim();
    if (prefix.isEmpty || !url.startsWith('http')) {
      return url;
    }
    return prefix.endsWith('/') ? '$prefix$url' : '$prefix/$url';
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
