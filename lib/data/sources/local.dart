import 'dart:io';

import '../models/media_item.dart';
import 'media_source.dart';

/// Local folders.
///
/// Scanned off the UI thread by the caller (`await`), with a hard cap so a user
/// who points this at `C:\` cannot freeze the shell.
class LocalSource extends MediaSource {
  LocalSource(super.config);

  static const int _maxEntries = 400;

  @override
  Future<List<MediaItem>> browse() => _scan(config.path);

  @override
  Future<List<MediaItem>> children(MediaItem container) => _scan(container.path ?? config.path);

  Future<List<MediaItem>> _scan(String path) async {
    if (path.isEmpty) {
      throw const SourceException('还没有选择文件夹');
    }
    final Directory directory = Directory(path);
    if (!await directory.exists()) {
      throw SourceException('文件夹不存在：$path');
    }

    final List<MediaItem> out = <MediaItem>[];
    final Map<String, List<String>> siblingCache = <String, List<String>>{};
    try {
      await for (final FileSystemEntity entity
          in directory.list(recursive: true, followLinks: false)) {
        if (out.length >= _maxEntries) {
          break;
        }
        if (entity is! File) {
          continue;
        }
        final String name = entity.uri.pathSegments.last;
        if (!looksLikeVideo(name)) {
          continue;
        }
        FileStat stat;
        try {
          stat = await entity.stat();
        } on FileSystemException {
          continue;
        }
        final String parent = entity.parent.path;
        out.add(
          MediaItem(
            id: '${config.id}::$parent/$name',
            sourceId: config.id,
            sourceKind: SourceKind.local,
            kind: MediaKind.file,
            title: prettifyFileName(name),
            subtitle: parent,
            path: entity.path,
            meta: _sizeLabel(stat.size),
            badge: _resolutionBadge(name),
            // Scrapers (tinyMediaManager, Emby for Windows, …) drop a
            // poster/folder image next to the video — pick it up so the
            // library shows real artwork instead of a letter tile.
            posterUrl: _posterFor(parent, name, siblingCache),
          ),
        );
      }
    } on FileSystemException catch (error) {
      throw SourceException('读取失败：${error.message}');
    }

    out.sort((MediaItem a, MediaItem b) => a.title.compareTo(b.title));
    return out;
  }

  @override
  Future<String> resolve(MediaItem item) async {
    final String? path = item.path;
    if (path == null || !File(path).existsSync()) {
      throw const SourceException('文件已被移动或删除');
    }
    return path;
  }

  /// Finds scraped artwork for a video among its directory siblings.
  ///
  /// Priority: `<video-stem>-poster.*` / `<video-stem>.*` (per-movie artwork)
  /// first, then the fixed `poster` / `folder` / `cover` conventions. The
  /// directory listing is cached per folder — movies rarely live alone.
  static String? _posterFor(String parent, String videoName, Map<String, List<String>> cache) {
    final List<String> siblings = cache.putIfAbsent(
      parent,
      () => Directory(parent)
          .listSync(recursive: false, followLinks: false)
          .whereType<File>()
          .map((File file) => file.path.toLowerCase())
          .toList(growable: false),
    );
    if (siblings.isEmpty) {
      return null;
    }
    final String lower = videoName.toLowerCase();
    final String stem = lower.contains('.') ? lower.substring(0, lower.lastIndexOf('.')) : lower;
    const List<String> fixed = <String>['poster', 'folder', 'cover'];
    String? best;
    for (final String path in siblings) {
      final String name = path.replaceAll('\\', '/').split('/').last;
      final int dot = name.lastIndexOf('.');
      if (dot <= 0) {
        continue;
      }
      final String stemName = name.substring(0, dot);
      final String ext = name.substring(dot + 1);
      if (ext != 'jpg' && ext != 'jpeg' && ext != 'png' && ext != 'webp') {
        continue;
      }
      if (stemName == stem || stemName == '$stem-poster') {
        return path;
      }
      if (best == null && fixed.contains(stemName)) {
        best = path;
      }
    }
    return best;
  }

  static String _resolutionBadge(String name) {
    final String lower = name.toLowerCase();
    if (lower.contains('2160') || lower.contains('4k')) {
      return '4K';
    }
    if (lower.contains('1080')) {
      return 'HD';
    }
    return '';
  }

  static String _sizeLabel(int bytes) {
    if (bytes <= 0) {
      return '';
    }
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }
}
