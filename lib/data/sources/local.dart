import 'dart:io';

import '../models/artwork.dart';
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
        // Scrapers (tinyMediaManager, Emby for Windows, …) drop artwork next
        // to the video under fixed names; read all of them, not just a poster,
        // so a local library gets the same hero treatment as a server one.
        final Artwork art = _artworkFor(parent, name, siblingCache);
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
            tech: _techFromName(name),
            posterUrl: art.best(ArtKind.poster)?.url,
            backdropUrl: art.best(ArtKind.backdrop)?.url,
            artwork: art,
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

  /// Resolves artwork by the file-name conventions the whole ecosystem uses
  /// (Emby's own table; Kodi and tinyMediaManager write the same names).
  ///
  /// One directory scan fills every role at once. The sibling list is cached
  /// per folder, because a 200-title folder would otherwise stat the same
  /// files 200 times.
  static Artwork _artworkFor(String parent, String videoName, Map<String, List<String>> cache) {
    final List<String> siblings = cache.putIfAbsent(
      parent,
      () => Directory(parent)
          .listSync(recursive: false, followLinks: false)
          .whereType<File>()
          .map((File file) => file.path.toLowerCase())
          .toList(growable: false)
        ..sort(),
    );
    if (siblings.isEmpty) {
      return const Artwork.empty();
    }

    final String lower = videoName.toLowerCase();
    final String stem = lower.contains('.') ? lower.substring(0, lower.lastIndexOf('.')) : lower;

    // Stem → path, first extension wins so the result is deterministic.
    final Map<String, String> byStem = <String, String>{};
    for (final String path in siblings) {
      final String name = path.replaceAll('\\', '/').split('/').last;
      final int dot = name.lastIndexOf('.');
      if (dot <= 0) {
        continue;
      }
      final String ext = name.substring(dot + 1);
      if (ext != 'jpg' && ext != 'jpeg' && ext != 'png' && ext != 'webp') {
        continue;
      }
      byStem.putIfAbsent(name.substring(0, dot), () => path);
    }
    if (byStem.isEmpty) {
      return const Artwork.empty();
    }

    String? pick(List<String> names) {
      for (final String name in names) {
        final String? path = byStem[name];
        if (path != null) {
          return path;
        }
      }
      return null;
    }

    final ArtworkBuilder art = ArtworkBuilder();

    // Primary: the per-movie names first, then the fixed folder conventions.
    art.add(
      ArtKind.poster,
      pick(<String>[
        stem, '$stem-poster', '$stem-cover', '$stem-default', '$stem-movie',
        'poster', 'folder', 'cover', 'default', 'movie',
      ]),
      source: 'local',
    );
    art.add(ArtKind.logo, pick(<String>['$stem-logo', 'logo']), source: 'local');
    art.add(
      ArtKind.thumb,
      pick(<String>['$stem-thumb', '$stem-landscape', 'thumb', 'landscape']),
      source: 'local',
    );
    art.add(ArtKind.banner, pick(<String>['$stem-banner', 'banner']), source: 'local');
    art.add(ArtKind.disc, pick(<String>['$stem-disc', '$stem-cdart', 'disc', 'cdart']), source: 'local');
    art.add(ArtKind.clearart, pick(<String>['$stem-clearart', 'clearart']), source: 'local');

    // Backdrops: one unnumbered file, then the numbered variants.
    final String? first = pick(<String>['backdrop', 'fanart', 'background', 'art']);
    if (first != null) {
      art.add(ArtKind.backdrop, first, source: 'local');
    }
    for (int i = 1; i <= 9; i++) {
      final String? extra = pick(<String>['backdrop$i', 'fanart$i', 'fanart-$i', 'art$i']);
      if (extra != null) {
        art.add(ArtKind.backdrop, extra, source: 'local');
      }
    }

    return art.build();
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

  /// One technical line read off the file name: `2160p · HEVC · EAC3 · HDR`.
  ///
  /// A local file has no metadata server behind it, and the filename is the only
  /// thing that knows the picture is 4K or the audio is Atmos. It is a hint, not
  /// a fact — which is why it is shown as one quiet line and never as a badge
  /// the UI would act on.
  static String? _techFromName(String name) {
    final String lower = name.toLowerCase();
    final String? resolution = lower.contains('2160') || lower.contains('4k')
        ? '2160p'
        : lower.contains('1080')
            ? '1080p'
            : lower.contains('720')
                ? '720p'
                : null;
    final String? codec = lower.contains('x265') || lower.contains('h265') || lower.contains('hevc')
        ? 'HEVC'
        : lower.contains('x264') || lower.contains('h264') || lower.contains('avc')
            ? 'H.264'
            : lower.contains('av1')
                ? 'AV1'
                : null;
    // Order matters: `dts-hd` and `ddp5.1` contain the shorter tokens.
    final String? audio = lower.contains('truehd') || lower.contains('atmos')
        ? (lower.contains('atmos') ? 'TrueHD Atmos' : 'TrueHD')
        : lower.contains('dts-hd')
            ? 'DTS-HD'
            : lower.contains('dts')
                ? 'DTS'
                : lower.contains('ddp') || lower.contains('eac3') || lower.contains('dd+')
                    ? 'EAC3'
                    : lower.contains('ac3')
                        ? 'AC3'
                        : lower.contains('aac')
                            ? 'AAC'
                            : null;
    final String? hdr = lower.contains('dolby.vision') || lower.contains('dovi') || lower.contains('dv.')
        ? 'Dolby Vision'
        : lower.contains('hdr10+')
            ? 'HDR10+'
            : lower.contains('hdr')
                ? 'HDR'
                : null;
    final List<String> parts = <String>[
      if (resolution != null) resolution,
      if (codec != null) codec,
      if (audio != null) audio,
      if (hdr != null) hdr,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
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
