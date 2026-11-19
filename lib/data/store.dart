import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
/// Persistence is a single JSON file in `%APPDATA%\XnX Player\state.json` — no
/// plugin, no database, and it survives a clean uninstall of the Flutter SDK.
class AppStore extends ChangeNotifier {
  AppStore._();

  static final AppStore instance = AppStore._();

  final List<SourceConfig> sources = <SourceConfig>[];
  final List<MediaItem> items = <MediaItem>[];
  final Map<String, Duration> _resume = <String, Duration>{};
  final Map<String, MediaSource> _open = <String, MediaSource>{};
  final List<String> errors = <String>[];

  PlaybackPrefs prefs = const PlaybackPrefs();

  bool ready = false;
  bool loading = false;
  bool _alive = true;

  static String get stateDirectory {
    final String? appData = Platform.environment['APPDATA'];
    final String base = appData != null && appData.isNotEmpty
        ? appData
        : Directory.current.path;
    return '$base${Platform.pathSeparator}XnX Player';
  }

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

  Future<void> load() async {
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
    } on Object catch (error) {
      errors.add('读取配置失败：$error');
    }
    ready = true;
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
        'resume': _resume.map(
          (String key, Duration value) => MapEntry<String, int>(key, value.inMilliseconds),
        ),
      };
      await File(statePath).writeAsString(jsonEncode(snapshot));
    } on Object catch (error) {
      errors.add('保存配置失败：$error');
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
    await _persist();
    _notify();
    await refresh();
  }

  Future<void> removeSource(String id) async {
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

  Future<void> refresh() async {
    if (loading) {
      return;
    }
    loading = true;
    errors.clear();
    _notify();

    final List<MediaItem> collected = <MediaItem>[];
    final Set<String> seen = <String>{};

    for (final SourceConfig config in sources.where((SourceConfig entry) => entry.enabled)) {
      try {
        final MediaSource source = _sourceFor(config);
        final List<MediaItem> listing = await source.browse();
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
      } on Object catch (error) {
        errors.add('${config.label}：$error');
      }
    }

    items
      ..clear()
      ..addAll(collected);
    loading = false;
    _notify();
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
