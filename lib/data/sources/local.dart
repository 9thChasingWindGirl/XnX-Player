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
