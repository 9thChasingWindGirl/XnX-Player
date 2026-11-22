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
  Future<List<MediaItem>> browse() async {
    final List<MediaItem> scanned = await _scan(config.path);
    // Series containers replace their loose episode files in the top-level
    // library; the episodes themselves are reachable through children().
    final Map<String, MediaItem> series = <String, MediaItem>{};
    final List<MediaItem> out = <MediaItem>[];
    for (final MediaItem item in scanned) {
      final String? show = item.group;
      if (item.kind == MediaKind.episode && show != null && show.isNotEmpty) {
        series.putIfAbsent(show, () => _seriesFor(show, item));
      } else {
        out.add(item);
      }
    }
    out.addAll(series.values);
    out.sort((MediaItem a, MediaItem b) => a.title.compareTo(b.title));
    return out;
  }

  @override
  Future<List<MediaItem>> children(MediaItem container) async {
    if (container.kind == MediaKind.series) {
      // A local series container carries its show name in [group]. Return only
      // that show's episodes, ordered by season then episode number.
      final String show = container.group ?? '';
      final List<MediaItem> episodes = (await _scan(config.path))
          .where((MediaItem item) =>
              item.kind == MediaKind.episode && item.group == show)
          .toList();
      episodes.sort((MediaItem a, MediaItem b) {
        final int bySeason = (a.season ?? 0).compareTo(b.season ?? 0);
        return bySeason != 0 ? bySeason : (a.episode ?? 0).compareTo(b.episode ?? 0);
      });
      return episodes;
    }
    return _scan(container.path ?? config.path);
  }

  /// The series container shown in the library for a set of episode files.
  ///
  /// Artwork is inherited from the first episode so a TV show gets the same
  /// poster/backdrop treatment as any other library entry.
  MediaItem _seriesFor(String show, MediaItem first) {
    final String id = '${config.id}::series:$show';
    final String root = _seriesRoot(first.path);
    return MediaItem(
      id: id,
      sourceId: config.id,
      sourceKind: SourceKind.local,
      kind: MediaKind.series,
      title: show,
      group: show,
      // The detail page decides "can this be opened" from a non-empty path,
      // and children() uses it to scan one show instead of the whole library.
      path: root.isEmpty ? null : root,
      posterUrl: first.posterUrl,
      backdropUrl: first.backdropUrl,
      artwork: first.artwork,
      genres: first.genres,
      year: first.year,
    );
  }

  /// The show folder an episode lives in.
  ///
  /// Kodi/TMM layouts put episodes under `season01/`, so the folder one level
  /// up is the show; a flat folder of episodes is its own show folder.
  static String _seriesRoot(String? episodePath) {
    if (episodePath == null || episodePath.isEmpty) {
      return '';
    }
    final Directory parent = File(episodePath).parent;
    final List<String> segments = parent.uri.pathSegments
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    final String name = segments.isEmpty ? '' : segments.last;
    final bool isSeasonFolder = RegExp(
      r'^(?:(?:season|s)\s*\d{1,2}|第\s*[一二三四五六七八九十\d]+\s*季)$',
      caseSensitive: false,
    ).hasMatch(name);
    return isSeasonFolder ? parent.parent.path : parent.path;
  }

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
        final EpisodeTag? tag = episodeTagFromFileName(name);
        out.add(
          MediaItem(
            id: '${config.id}::$parent/$name',
            sourceId: config.id,
            sourceKind: SourceKind.local,
            kind: tag == null ? MediaKind.file : MediaKind.episode,
            title: tag == null ? prettifyFileName(name) : (tag.episodeTitle ?? tag.show),
            subtitle: tag == null ? parent : tag.show,
            group: tag?.show,
            season: tag?.season,
            episode: tag?.episode,
            path: entity.path,
            meta: _sizeLabel(stat.size),
            badge: tag == null ? _resolutionBadge(name) : tag.badge,
            tech: _techFromName(name),
            year: yearFromFileName(name),
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
    // Order matters: `dts-hd` and `ddp5.1` contain the shorter tokens, and
    // "EAC3 Atmos" must not be reported as "TrueHD Atmos" just because the
    // object-audio tag is present.
    final bool atmos = lower.contains('atmos');
    final String? audio = lower.contains('truehd')
        ? (atmos ? 'TrueHD Atmos' : 'TrueHD')
        : lower.contains('dts-hd')
            ? 'DTS-HD'
            : lower.contains('dts')
                ? 'DTS'
                : lower.contains('ddp') || lower.contains('eac3') || lower.contains('dd+')
                    ? (atmos ? 'EAC3 Atmos' : 'EAC3')
                    : lower.contains('ac3')
                        ? 'AC3'
                        : lower.contains('aac')
                            ? 'AAC'
                            : (atmos ? 'Atmos' : null);
    final String? hdr = lower.contains('dolby.vision') || lower.contains('dovi') || lower.contains('dv.')
        ? 'Dolby Vision'
        : lower.contains('hdr10+')
            ? 'HDR10+'
            : lower.contains('hdr')
                ? 'HDR'
                : null;
    final String? depth = lower.contains('10bit') || lower.contains('10-bit')
        ? '10-bit'
        : lower.contains('8bit') || lower.contains('8-bit')
            ? '8-bit'
            : null;
    final String? channels =
        RegExp(r'(?:^|[^0-9])([257])\.1(?:[^0-9]|$)').firstMatch(lower)?.group(1);
    final RegExpMatch? fpsMatch =
        RegExp(r'(\d{2,3}(?:\.\d+)?)\s*fps').firstMatch(lower);
    final String? fps = fpsMatch == null ? null : '${fpsMatch.group(1)} fps';
    final String? audioLabel = audio == null
        ? null
        : (channels == null ? audio : '$audio $channels.1');
    final List<String> parts = <String>[
      if (resolution != null) resolution,
      if (codec != null) codec,
      if (depth != null) depth,
      if (audioLabel != null) audioLabel,
      if (hdr != null) hdr,
      if (fps != null) fps,
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
