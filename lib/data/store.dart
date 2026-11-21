import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import '../core/app_paths.dart';
import '../core/notice_center.dart';
import '../playback/mpv/hw_profile.dart';
import 'models/media_item.dart';
import 'net.dart';
import 'prefs.dart';
import 'sources/emby.dart';
import 'sources/iptv.dart';
import 'sources/local.dart';
import 'sources/media_source.dart';
import 'sources/remote_files.dart';

/// Application state: configured backends, the merged library, resume points
/// and playback preferences.
///
/// Persistence is a single JSON file `state.json` in the user's data directory
/// (installer/portable choice; default `%APPDATA%\XnX Player`) — no plugin, no
/// database, and it survives updates and uninstalls.
class AppStore extends ChangeNotifier {
  AppStore._();

  static final AppStore instance = AppStore._();

  final List<SourceConfig> sources = <SourceConfig>[];
  final List<MediaItem> items = <MediaItem>[];
  final Map<String, Duration> _resume = <String, Duration>{};
  final Map<String, MediaSource> _open = <String, MediaSource>{};
  final List<String> errors = <String>[];

  PlaybackPrefs prefs = const PlaybackPrefs();

  /// Persisted facts about this machine's display and audio endpoints,
  /// learned by the player's capability probe and reused at next start.
  HardwareProfile hw = const HardwareProfile();

  bool ready = false;
  bool loading = false;
  bool _alive = true;

  static String get stateDirectory => AppPaths.dataDir;

  static String get statePath => '$stateDirectory${Platform.pathSeparator}state.json';

  /// Catalogue split: playable library vs live channels.
  List<MediaItem> get library => items
      .where((MediaItem item) => item.kind != MediaKind.channel)
      .toList(growable: false);

  List<MediaItem> get channels => items
      .where((MediaItem item) => item.kind == MediaKind.channel)
      .toList(growable: false);

  List<MediaItem> get continueWatching {
    final List<MediaItem> out = items
        .where((MediaItem item) => item.progress > 0.02 && item.progress < 0.96 && item.isPlayable)
        .toList();
    out.sort((MediaItem a, MediaItem b) => b.progress.compareTo(a.progress));
    return out;
  }

  List<MediaItem> get recent => items
      .where((MediaItem item) => item.isPlayable && item.kind != MediaKind.channel)
      .toList(growable: false);

  bool get isEmpty => items.isEmpty;

  /// The TMDB API key configured as a metadata source, or an empty string.
  String get tmdbKey {
    for (final SourceConfig config in sources) {
      if (config.kind == SourceKind.tmdb && config.enabled) {
        return config.token.trim();
      }
    }
    return '';
  }

  bool get hasTmdb => tmdbKey.isNotEmpty;

  /// Sets or clears the TMDB metadata key.
  ///
  /// Metadata is not a media source: no browse, no refresh, only a persisted
  /// `SourceConfig` that [tmdbKey] reads back. Older builds could save several
  /// TMDB chips through the add-source dialog, so a write also collapses them
  /// into one — otherwise which key is in use would be an accident of order.
  Future<void> setTmdbKey(String key) async {
    final String trimmed = key.trim();
    final int first = sources.indexWhere(
      (SourceConfig config) => config.kind == SourceKind.tmdb,
    );
    if (trimmed.isEmpty) {
      sources.removeWhere((SourceConfig config) => config.kind == SourceKind.tmdb);
      if (first >= 0) {
        await _persist();
        _notify();
      }
      return;
    }
    final SourceConfig config = first >= 0
        ? sources[first].copyWith(name: 'TMDB', token: trimmed, enabled: true)
        : SourceConfig(
            id: 'tmdb',
            kind: SourceKind.tmdb,
            name: 'TMDB',
            token: trimmed,
          );
    if (first >= 0) {
      sources[first] = config;
    } else {
      sources.add(config);
    }
    for (int i = sources.length - 1; i >= 0; i--) {
      if (sources[i].kind == SourceKind.tmdb && !identical(sources[i], config)) {
        sources.removeAt(i);
      }
    }
    await _persist();
    _notify();
  }

  Future<void> load() async {
    AppLog.info('读取配置：$statePath');
    try {
      final File file = File(statePath);
      if (await file.exists()) {
        final Object? decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          final Object? rawSources = decoded['sources'];
          if (rawSources is List) {
            for (final Object? entry in rawSources) {
              if (entry is Map<String, dynamic>) {
                sources.add(SourceConfig.fromJson(entry));
              }
            }
          }
          final Object? rawPrefs = decoded['prefs'];
          if (rawPrefs is Map<String, dynamic>) {
            prefs = PlaybackPrefs.fromJson(rawPrefs);
          }
          final Object? rawHw = decoded['hw'];
          if (rawHw is Map<String, dynamic>) {
            hw = HardwareProfile.fromJson(rawHw);
          }
          final Object? rawResume = decoded['resume'];
          if (rawResume is Map<String, dynamic>) {
            rawResume.forEach((String key, Object? value) {
              if (value is num) {
                _resume[key] = Duration(milliseconds: value.toInt());
              }
            });
          }
        }
      }
    } on Object catch (error, stack) {
      errors.add('读取配置失败：$error');
      AppLog.error('读取配置失败', error, stack);
    }
    ready = true;
    AppLog.info('配置已载入：${sources.length} 个来源，${items.length} 项媒体');
    _notify();
    if (sources.isNotEmpty) {
      unawaited(refresh());
    }
  }

  Future<void> _persist() async {
    try {
      final Directory directory = Directory(stateDirectory);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final Map<String, dynamic> snapshot = <String, dynamic>{
        'version': 1,
        'sources': sources.map((SourceConfig config) => config.toJson()).toList(),
        'prefs': prefs.toJson(),
        'hw': hw.toJson(),
        'resume': _resume.map(
          (String key, Duration value) => MapEntry<String, int>(key, value.inMilliseconds),
        ),
      };
      await File(statePath).writeAsString(jsonEncode(snapshot));
    } on Object catch (error, stack) {
      errors.add('保存配置失败：$error');
      AppLog.error('保存配置失败', error, stack);
    }
  }

  MediaSource _sourceFor(SourceConfig config) {
    final MediaSource? existing = _open[config.id];
    if (existing != null) {
      return existing;
    }
    final MediaSource created = switch (config.kind) {
      SourceKind.emby || SourceKind.jellyfin => EmbySource(config),
      SourceKind.iptv => IptvSource(config),
      SourceKind.openlist => AListSource(config),
      SourceKind.webdav => WebDavSource(config),
      SourceKind.local => LocalSource(config),
      SourceKind.directUrl => LocalSource(config),
      SourceKind.tmdb => throw const SourceException('TMDB 只提供门户元数据，不提供媒体文件'),
    };
    _open[config.id] = created;
    return created;
  }

  Future<void> addSource(SourceConfig config) async {
    final int index = sources.indexWhere((SourceConfig entry) => entry.id == config.id);
    if (index >= 0) {
      sources[index] = config;
    } else {
      sources.add(config);
    }
    _open.remove(config.id);
    AppLog.info('保存媒体源：${config.label}（${config.kind.name}）${config.url}');
    await _persist();
    NoticeCenter.instance.publish(
      'source-add-${config.id}',
      '已连接媒体来源：${config.label}',
      body: config.url,
      kind: NoticeKind.success,
    );
    _notify();
    await refresh();
  }

  Future<void> removeSource(String id) async {
    AppLog.info('移除媒体源：$id');
    sources.removeWhere((SourceConfig config) => config.id == id);
    final MediaSource? source = _open.remove(id);
    await source?.close();
    items.removeWhere((MediaItem item) => item.sourceId == id);
    await _persist();
    _notify();
  }

  Future<void> updatePrefs(PlaybackPrefs value) async {
    prefs = value;
    await _persist();
    _notify();
  }

  /// Dismisses the collected source errors. The control center shows them as
  /// notifications, and a notification list you cannot clear is a list nobody
  /// reads after the first day.
  void clearErrors() {
    if (errors.isEmpty) {
      return;
    }
    errors.clear();
    _notify();
  }

  /// Records what the capability probe learned about this machine so the next
  /// start can decide passthrough and HDR handling without probing blind.
  Future<void> updateHwProfile(HardwareProfile value) async {
    hw = value;
    await _persist();
    _notify();
  }

  Future<void> refresh() async {
    if (loading) {
      return;
    }
    loading = true;
    errors.clear();
    AppLog.info('刷新媒体库开始（${sources.length} 个来源）');
    LibraryLog.write('刷新开始（${sources.length} 个来源）');
    // A refresh that takes a minute is exactly the silent wait a notification
    // is for: it becomes a live row in the centre and in the top bar.
    NoticeCenter.instance.activity('library-refresh', '正在刷新媒体库',
        body: '${sources.length} 个来源');
    _notify();

    final List<MediaItem> collected = <MediaItem>[];
    final Set<String> seen = <String>{};

    try {
      // TMDB is a metadata portal: it has no files to enumerate, so it never
      // takes part in the library refresh.
      for (final SourceConfig config
          in sources.where((SourceConfig entry) => entry.enabled && entry.kind != SourceKind.tmdb)) {
        try {
          // One stalled source must not hold the whole library hostage: each
          // source gets its own deadline, and a miss is recorded as an error
          // the control center can show instead of an eternal skeleton.
          final MediaSource source = _sourceFor(config);
          final List<MediaItem> listing =
              await source.browse().timeout(const Duration(seconds: 60));
          for (final MediaItem item in listing) {
            if (seen.add(item.id)) {
              collected.add(_withResume(item));
            }
          }
          if (source is EmbySource) {
            for (final MediaItem item in await source.resumable()) {
              if (seen.add(item.id)) {
                collected.add(_withResume(item));
              }
            }
          }
          LibraryLog.write('${config.label}：${listing.length} 项');
        } on Object catch (error, stack) {
          errors.add('${config.label}：$error');
          AppLog.error('媒体源刷新失败：${config.label}', error, stack);
          LibraryLog.write('${config.label}：失败 — $error');
          // One row per failing source, refreshed on a retry rather than piled
          // up: the id is the source, not the failure.
          NoticeCenter.instance.publish(
            'source-fail-${config.id}',
            '${config.label} 连接失败',
            body: '$error',
            kind: NoticeKind.error,
          );
        }
      }

      items
        ..clear()
        ..addAll(collected);
      AppLog.info('刷新媒体库完成：${collected.length} 项，${errors.length} 个错误');
      LibraryLog.write('刷新完成：${collected.length} 项');
    } finally {
      // A timeout or an unexpected throw above must still release the flag,
      // otherwise the home page spins its loading skeleton forever.
      loading = false;
      NoticeCenter.instance.finish(
        'library-refresh',
        title: errors.isEmpty ? '媒体库已更新' : '媒体库已更新，部分来源失败',
        body: '${collected.length} 项媒体'
            '${errors.isEmpty ? '' : '，${errors.length} 个来源失败'}',
        kind: errors.isEmpty ? NoticeKind.success : NoticeKind.warning,
      );
      _notify();
    }
  }

  MediaItem _withResume(MediaItem item) {
    final Duration? saved = _resume[item.id];
    if (saved == null || item.duration == null || item.duration!.inMilliseconds <= 0) {
      return item;
    }
    final double progress =
        (saved.inMilliseconds / item.duration!.inMilliseconds).clamp(0.0, 1.0).toDouble();
    return item.copyWith(progress: progress, resumeAt: saved);
  }

  Future<List<MediaItem>> children(MediaItem container) async {
    final SourceConfig? config = _configFor(container);
    if (config == null) {
      return const <MediaItem>[];
    }
    final MediaSource source = _sourceFor(config);
    return source.children(container);
  }

  /// The full record for a hub page, with the resume bookmark folded in.
  ///
  /// A failure here must never cost the user the page: the hub already has
  /// everything a shelf knows, so a source that is offline or a server that
  /// drops the extra fields simply leaves the hub with less to say.
  Future<MediaItem> details(MediaItem item) async {
    final SourceConfig? config = _configFor(item);
    if (config == null) {
      return item;
    }
    try {
      return _withResume(await _sourceFor(config).details(item));
    } on Object {
      return item;
    }
  }

  SourceConfig? _configFor(MediaItem item) {
    for (final SourceConfig config in sources) {
      if (config.id == item.sourceId) {
        return config;
      }
    }
    return null;
  }

  /// The URL handed to mpv, after any backend round-trip (AList raw URL).
  Future<String> resolve(MediaItem item) async {
    final String? path = item.path;
    if (path == null || path.isEmpty) {
      throw const SourceException('这一项没有可播放的地址');
    }
    if (item.sourceKind == SourceKind.local ||
        item.sourceKind == SourceKind.directUrl ||
        item.sourceKind == SourceKind.iptv) {
      return path;
    }
    final SourceConfig? config = _configFor(item);
    if (config == null) {
      return path;
    }
    return _sourceFor(config).resolve(item);
  }

  /// Headers mpv would need. Kept for completeness: credentials are instead
  /// embedded in the resolved URL (api_key for Emby, userinfo for WebDAV),
  /// because mpv's `http-header-fields` cannot carry commas.
  Map<String, String> headersFor(MediaItem item) {
    if (item.sourceKind == SourceKind.webdav) {
      final SourceConfig? config = _configFor(item);
      if (config != null) {
        return <String, String>{'Authorization': Http.basic(config.username, config.password)};
      }
    }
    return item.headers;
  }

  void remember(MediaItem item, Duration position, Duration duration) {
    _resume[item.id] = position;
    final int index = items.indexWhere((MediaItem entry) => entry.id == item.id);
    if (index >= 0) {
      final double progress = duration.inMilliseconds <= 0
          ? 0
          : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
      items[index] = items[index].copyWith(progress: progress, resumeAt: position);
    }
    _notify();
    unawaited(_persist());
  }

  void toggleFavorite(MediaItem item) {
    final int index = items.indexWhere((MediaItem entry) => entry.id == item.id);
    if (index >= 0) {
      items[index] = items[index].copyWith(favorite: !items[index].favorite);
      _notify();
    }
  }

  List<MediaItem> search(String query) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const <MediaItem>[];
    }
    return items
        .where((MediaItem item) =>
            item.title.toLowerCase().contains(needle) ||
            (item.subtitle ?? '').toLowerCase().contains(needle) ||
            (item.group ?? '').toLowerCase().contains(needle))
        .take(40)
        .toList(growable: false);
  }

  void _notify() {
    if (_alive) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _alive = false;
    for (final MediaSource source in _open.values) {
      unawaited(source.close());
    }
    super.dispose();
  }
}

/// Library-refresh logging, appended to `library.log` in the data directory.
///
/// Playback already had mpv's own log file; the library side was silent, so a
/// refresh that never finished had nothing to inspect. Best-effort by design:
/// a log write that fails must never break the refresh it is describing.
class LibraryLog {
  LibraryLog._();

  static const int _maxBytes = 256 * 1024;

  static Future<void> write(String message) async {
    try {
      final File file = File('${AppStore.stateDirectory}${Platform.pathSeparator}library.log');
      final String stamp = DateTime.now().toIso8601String();
      final String line = '[$stamp] $message\n';
      if (await file.exists() && await file.length() > _maxBytes) {
        // Keep it a tail, not an archive: the newest run matters.
        await file.writeAsString(line);
        return;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(line, mode: FileMode.append);
    } on Object {
      // Logging is a courtesy; ignore every failure.
    }
  }
}
