import 'package:flutter/widgets.dart';

import '../../design/ps_tokens.dart';

/// Where a media item comes from. Kept in one enum because the UI treats every
/// source the same way: a poster, a title, a play action.
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
    this.sourceId = 'demo',
    this.sourceKind = SourceKind.local,
    this.kind = MediaKind.movie,
    this.subtitle,
    this.overview,
    this.meta,
    this.progress = 0,
    this.duration,
    this.path,
    this.badge,
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

  /// Local path or remote URL, when already resolvable without a backend call.
  final String? path;

  /// "4K" / "HDR" / "直播" style corner label.
  final String? badge;

  bool get isPlayable => kind != MediaKind.folder && kind != MediaKind.season;

  /// Deterministic artwork colours, so a title always looks the same.
  List<Color> get artwork => PsColor.artFor(id);
}
