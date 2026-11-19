import 'package:flutter/widgets.dart';

import '../../design/ps_tokens.dart';

/// Where a media item comes from. The UI treats every source the same way: a
/// poster, a title, a play action.
enum SourceKind { local, directUrl, emby, jellyfin, iptv, openlist, webdav }

enum MediaKind { movie, series, season, episode, channel, folder, file, program }

/// One entry in the UI, whatever its backend.
///
/// [id] is globally unique and stable (`sourceId::nativeId`), so progress,
/// artwork caches and focus memory can all key off it.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.sourceId = 'local',
    this.sourceKind = SourceKind.local,
    this.kind = MediaKind.movie,
    this.subtitle,
    this.overview,
    this.meta,
    this.progress = 0,
    this.duration,
    this.path,
    this.badge,
    this.posterUrl,
    this.backdropUrl,
    this.headers = const <String, String>{},
    this.favorite = false,
    this.group,
    this.resumeAt,
    this.year,
    this.rating,
    this.playable = true,
  });

  final String id;
  final String sourceId;
  final SourceKind sourceKind;
  final MediaKind kind;
  final String title;
  final String? subtitle;
  final String? overview;

  /// Small metadata line: year, runtime, resolution. Free-form on purpose.
  final String? meta;

  /// 0..1 watched progress.
  final double progress;
  final Duration? duration;

  /// Local path, direct URL, or a backend path resolved by its source.
  final String? path;

  /// "4K" / "HDR" / "直播" style corner label.
  final String? badge;

  final String? posterUrl;
  final String? backdropUrl;

  /// Extra headers required to fetch [path] (WebDAV auth, AList token...).
  final Map<String, String> headers;

  final bool favorite;
  final String? group;
  final Duration? resumeAt;
  final int? year;
  final double? rating;
  final bool playable;

  bool get isPlayable => playable && kind != MediaKind.folder && kind != MediaKind.season;

  bool get hasPoster => posterUrl != null && posterUrl!.isNotEmpty;

  bool get hasBackdrop => backdropUrl != null && backdropUrl!.isNotEmpty;

  /// Deterministic artwork colours, so a title always looks the same.
  List<Color> get artwork => PsColor.artFor(id);

  Color get accentColor => artwork[2];

  /// "1 小时 42 分" / "48 分钟", derived from [duration].
  String get runtimeLabel {
    final Duration? value = duration;
    if (value == null || value.inSeconds <= 0) {
      return meta ?? '';
    }
    final int hours = value.inHours;
    final int minutes = value.inMinutes.remainder(60);
    if (hours > 0) {
      return minutes > 0 ? '$hours 小时 $minutes 分' : '$hours 小时';
    }
    return '${minutes > 0 ? minutes : 1} 分钟';
  }

  MediaItem copyWith({
    String? title,
    String? subtitle,
    String? overview,
    String? meta,
    double? progress,
    Duration? duration,
    String? path,
    String? badge,
    String? posterUrl,
    String? backdropUrl,
    Map<String, String>? headers,
    bool? favorite,
    String? group,
    Duration? resumeAt,
    bool? playable,
  }) {
    return MediaItem(
      id: id,
      title: title ?? this.title,
      sourceId: sourceId,
      sourceKind: sourceKind,
      kind: kind,
      subtitle: subtitle ?? this.subtitle,
      overview: overview ?? this.overview,
      meta: meta ?? this.meta,
      progress: progress ?? this.progress,
      duration: duration ?? this.duration,
      path: path ?? this.path,
      badge: badge ?? this.badge,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      headers: headers ?? this.headers,
      favorite: favorite ?? this.favorite,
      group: group ?? this.group,
      resumeAt: resumeAt ?? this.resumeAt,
      year: year,
      rating: rating,
      playable: playable ?? this.playable,
    );
  }
}
