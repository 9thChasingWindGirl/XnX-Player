import 'package:flutter/widgets.dart';

import '../../design/ps_tokens.dart';
import 'artwork.dart';

/// Where a media item comes from. The UI treats every source the same way: a
/// poster, a title, a play action.
enum SourceKind { local, directUrl, emby, jellyfin, iptv, openlist, webdav }

enum MediaKind { movie, series, season, episode, channel, folder, file, program }

/// One credited person on a detail page.
///
/// Deliberately flat: a name, what they did, and a portrait when the server has
/// one. Cast and crew share the type because the UI treats them the same way —
/// a row of faces with two lines of text — and the difference is carried by
/// [role] ("饰 尼奥" vs "导演").
class MediaPerson {
  const MediaPerson({
    required this.name,
    this.role,
    this.job,
    this.type = 'Actor',
    this.imageUrl,
    this.headers = const <String, String>{},
  });

  final String name;

  /// Character played, for cast.
  final String? role;

  /// Job title, for crew ("导演", "编剧").
  final String? job;

  /// 'Actor' / 'Director' / 'Writer' ... as the server labels it.
  final String type;

  final String? imageUrl;
  final Map<String, String> headers;

  /// The second line of the tile: the character for cast, the job for crew.
  String? get caption => role ?? job;

  bool get isCast => type == 'Actor';
}

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
    this.artwork = const Artwork.empty(),
    this.headers = const <String, String>{},
    this.favorite = false,
    this.group,
    this.resumeAt,
    this.year,
    this.rating,
    this.playable = true,
    this.tagline,
    this.genres = const <String>[],
    this.people = const <MediaPerson>[],
    this.studio,
    this.officialRating,
    this.tech,
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

  /// The full art set, when the source has one.
  ///
  /// [posterUrl] and [backdropUrl] stay as the flat fields every card already
  /// reads; this carries the roles a shelf cannot show but a hero can — the
  /// transparent logo, the 16:9 still, the disc, the clearart.
  final Artwork artwork;

  /// Extra headers required to fetch [path] (WebDAV auth, AList token...).
  final Map<String, String> headers;

  final bool favorite;
  final String? group;
  final Duration? resumeAt;
  final int? year;
  final double? rating;
  final bool playable;

  /// Marketing line above the summary ("来自 8 月 15 日起，无处可逃").
  final String? tagline;

  /// Genres as the server spells them, in its own order.
  final List<String> genres;

  /// Cast then crew, already ordered by the server (`People` order).
  final List<MediaPerson> people;

  /// Studio / network, when the source distinguishes one.
  final String? studio;

  /// Age rating: "PG-13", "TV-MA", "R".
  final String? officialRating;

  /// One-line technical summary — "2160p · HEVC · EAC3 5.1" — for a detail page.
  ///
  /// A joined string rather than three fields because the only consumer paints
  /// it as one line, and a filename-derived value cannot fill three fields
  /// honestly (a local file knows "2160p" from its name but nothing about the
  /// bit depth).
  final String? tech;

  /// Cast with a role, which is what a detail page shows first.
  List<MediaPerson> get cast =>
      people.where((MediaPerson p) => p.isCast).toList(growable: false);

  /// Directors, writers and everyone else the server listed after the cast.
  List<MediaPerson> get crew =>
      people.where((MediaPerson p) => !p.isCast).toList(growable: false);

  bool get isPlayable => playable && kind != MediaKind.folder && kind != MediaKind.season;

  bool get hasPoster => posterUrl != null && posterUrl!.isNotEmpty;

  bool get hasBackdrop => backdropUrl != null && backdropUrl!.isNotEmpty;

  /// Transparent title treatment. When present, a hero should draw it instead
  /// of the title text — that is the whole point of having it.
  String? get logoUrl => artwork.best(ArtKind.logo)?.url;

  bool get hasLogo => logoUrl != null && logoUrl!.isNotEmpty;

  /// Headers needed to fetch [logoUrl] (Plex). Empty for the common case.
  Map<String, String> get logoHeaders =>
      artwork.best(ArtKind.logo)?.headers ?? const <String, String>{};

  /// 16:9 still, falling back to the poster: a landscape screen should never
  /// stretch a 2:3 cover when nothing else exists.
  String? get thumbUrl => artwork.best(ArtKind.thumb)?.url ?? posterUrl;

  String? get bannerUrl => artwork.best(ArtKind.banner)?.url;

  String? get discUrl => artwork.best(ArtKind.disc)?.url;

  String? get clearartUrl => artwork.best(ArtKind.clearart)?.url;

  /// Every backdrop the source has, in preference order. Servers usually carry
  /// more than one so a client can alternate them.
  List<String> get backdrops {
    final List<String> urls = artwork
        .all(ArtKind.backdrop)
        .map((ArtRef ref) => ref.url)
        .where((String url) => url.isNotEmpty)
        .toList(growable: false);
    if (urls.isNotEmpty) {
      return urls;
    }
    return hasBackdrop ? <String>[backdropUrl!] : const <String>[];
  }

  /// The widest image available, for a full-bleed hero or a hub background.
  String? get heroBackdropUrl {
    final List<String> wide = backdrops;
    if (wide.isNotEmpty) {
      return wide.first;
    }
    return thumbUrl;
  }

  /// Deterministic artwork colours, so a title always looks the same.
  ///
  /// Named [palette] rather than `artwork` because [artwork] is the art set
  /// itself: one is "which images exist", this is "what colour they read as".
  List<Color> get palette => PsColor.artFor(id);

  Color get accentColor => palette[2];

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
    int? year,
    double? rating,
    String? tagline,
    List<String>? genres,
    List<MediaPerson>? people,
    String? studio,
    String? officialRating,
    String? tech,
    Artwork? artwork,
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
      artwork: artwork ?? this.artwork,
      headers: headers ?? this.headers,
      favorite: favorite ?? this.favorite,
      group: group ?? this.group,
      resumeAt: resumeAt ?? this.resumeAt,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      playable: playable ?? this.playable,
      tagline: tagline ?? this.tagline,
      genres: genres ?? this.genres,
      people: people ?? this.people,
      studio: studio ?? this.studio,
      officialRating: officialRating ?? this.officialRating,
      tech: tech ?? this.tech,
    );
  }
}
