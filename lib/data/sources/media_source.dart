import '../models/media_item.dart';
import 'resolved_media.dart';

/// Persisted description of a configured backend.
class SourceConfig {
  const SourceConfig({
    required this.id,
    required this.kind,
    required this.name,
    this.url = '',
    this.username = '',
    this.password = '',
    this.token = '',
    this.userId = '',
    this.path = '',
    this.enabled = true,
  });

  final String id;
  final SourceKind kind;
  final String name;
  final String url;
  final String username;
  final String password;
  final String token;
  final String userId;

  /// Root folder for file-based sources.
  final String path;
  final bool enabled;

  String get label => name.isEmpty ? kind.name : name;

  SourceConfig copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    String? token,
    String? userId,
    String? path,
    bool? enabled,
  }) {
    return SourceConfig(
      id: id,
      kind: kind,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      token: token ?? this.token,
      userId: userId ?? this.userId,
      path: path ?? this.path,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'name': name,
        'url': url,
        'username': username,
        'password': password,
        'token': token,
        'userId': userId,
        'path': path,
        'enabled': enabled,
      };

  static SourceConfig fromJson(Map<String, dynamic> json) {
    return SourceConfig(
      id: json['id'] as String? ?? 'source',
      kind: SourceKind.values.firstWhere(
        (SourceKind kind) => kind.name == json['kind'],
        orElse: () => SourceKind.local,
      ),
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      token: json['token'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      path: json['path'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class SourceException implements Exception {
  const SourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A configured backend. Every implementation returns plain [MediaItem]s so the
/// UI never learns which protocol it is looking at.
abstract class MediaSource {
  MediaSource(this.config);

  final SourceConfig config;

  SourceKind get kind => config.kind;

  /// Top level listing: the latest items, the channel list, the root folder.
  Future<List<MediaItem>> browse();

  /// Drill-down for series / folders / seasons.
  Future<List<MediaItem>> children(MediaItem container) async => const <MediaItem>[];

  /// The richer record behind one item's hub page.
  ///
  /// Lists are projections — a shelf needs a poster, a title and a bar, and
  /// asking 80 items for their cast would make every browse slow. A hub needs
  /// tagline, genres, credits and technical detail, so it asks once, for one
  /// item. Sources that keep no more than the projection simply return [item].
  Future<MediaItem> details(MediaItem item) async => item;

  /// The URL mpv should open. May involve a backend round-trip (AList raw URL).
  Future<String> resolve(MediaItem item) async {
    final String? path = item.path;
    if (path == null || path.isEmpty) {
      throw const SourceException('这一项没有可播放的地址');
    }
    return path;
  }

  /// [resolve] plus the context that belongs with the URL.
  ///
  /// Callers should prefer this: a signed link knows when it goes stale, and a
  /// source that authenticates by header rather than by query string knows which
  /// header to send. Sources that can only produce a URL inherit this default
  /// and lose nothing.
  Future<ResolvedMedia> resolveMedia(MediaItem item) async {
    return ResolvedMedia(uri: await resolve(item), headers: headersFor(item));
  }

  Map<String, String> headersFor(MediaItem item) => item.headers;

  Future<void> close() async {}
}

String trimSlashes(String value) {
  String out = value.trim();
  while (out.endsWith('/')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

const Set<String> videoExtensions = <String>{
  'mkv', 'mp4', 'm4v', 'avi', 'mov', 'webm', 'ts', 'm2ts', 'mts', 'flv',
  'wmv', 'mpg', 'mpeg', 'rmvb', 'iso', 'ogv', '3gp',
};

bool looksLikeVideo(String name) {
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return false;
  }
  return videoExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Release tags that belong in a file-information panel, not in a title.
final List<RegExp> _releaseTags = <RegExp>[
  // A parenthesised year is shown in the facts row instead of the title; a
  // bare year stays, because "2012" and "1917" are the titles themselves.
  RegExp(r'\(\s*(?:19|20)\d{2}\s*\)'),
  RegExp(r'\b(?:2160p|1080p|720p|480p|4k|8k|uhd)\b', caseSensitive: false),
  RegExp(r'\b(?:x265|x264|h\.?265|h\.?264|hevc|avc|av1|vp9)\b', caseSensitive: false),
  RegExp(r'\b(?:eac3|dd\+?|ac3|aac|dts(?:-hd(?:-ma)?)?|truehd|atmos|flac)\b',
      caseSensitive: false),
  RegExp(r'\b(?:hdr10\+?|hdr|dolby\.?vision|dovi|hlg)\b', caseSensitive: false),
  RegExp(r'\b(?:10bit|8bit|web-?dl|webrip|bluray|blu-ray|bdrip|remux|hdtv|dvdrip)\b',
      caseSensitive: false),
  RegExp(r'\b\d+(?:\.\d+)?\s*(?:gb|mb)\b', caseSensitive: false),
  // A season/episode tag belongs to the series structure, not to a title.
  RegExp(r'\b[Ss]\d{1,2}\s*[._ -]?\s*[Ee]\d{1,3}\b'),
];

/// A `SxxEyy` tag parsed from a video file name.
///
/// Local folders have no metadata server, so the file name is the only place
/// that knows a clip is episode 5 of season 2. Turning that into a series /
/// episode structure is what keeps a TV library from looking like a folder of
/// unrelated single files.
class EpisodeTag {
  const EpisodeTag({
    required this.show,
    required this.season,
    required this.episode,
    this.episodeTitle,
  });

  /// The show name, cleaned up and used as the grouping key.
  final String show;
  final int season;
  final int episode;

  /// Whatever follows the tag, e.g. "如梦似幻". Null when the name ends at the tag.
  final String? episodeTitle;

  String get badge =>
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
}

/// One episode-naming convention.
///
/// Patterns are tried in order, the same way Kodi's
/// `m_tvshowEnumRegExps` is ordered in `AdvancedSettings.cpp:372-407`:
/// explicit `SxxEyy` first, the ambiguous three-digit form last (it would
/// otherwise swallow a release year).
class _EpisodePattern {
 const _EpisodePattern({
    required this.regex,
    this.seasonGroup,
    required this.episodeGroup,
    this.defaultSeason,
    this.seasonFromFolder = false,
    this.byDate = false,
    this.rejectLeadingSeason = false,
  });

  final RegExp regex;
  final int? seasonGroup;
  final int episodeGroup;
  final int? defaultSeason;
  final bool seasonFromFolder;
  final bool byDate;
  final bool rejectLeadingSeason;
}

/// Ordered rules transcribed from Kodi's defaults, with Chinese/roman forms
/// added for the libraries XnX actually sees.
const List<_EpisodePattern> _episodePatterns = <_EpisodePattern>[
  // 1) S01E02, s01.e02, S01-E02, S01xE02, with optional episode suffix a-i.
  _EpisodePattern(
    regex: RegExp(r'[Ss](\d{1,2})\s*[._x -]?\s*[Ee](\d{1,3}(?:[a-i]|\.[1-9])?)', caseSensitive: false),
    seasonGroup: 1,
    episodeGroup: 2,
  ),
  // 2) 1x09 — Kodi's fifth default rule.
  _EpisodePattern(
    regex: RegExp(r'[\/\\._ -](\d{1,2})x(\d{1,2})(?![0-9])', caseSensitive: false),
    seasonGroup: 1,
    episodeGroup: 2,
  ),
  // 3) Bare E09 / ep09: the season folder supplies the season number.
  //    A leading `Sxx` with no E of its own ("S02E05.mkv") must not match
  //    here — that is a malformed SxxEyy, not a season-1 episode.
  _EpisodePattern(
    regex: RegExp(r'(?<!\d)[Ee](?:p[ ._-]?)?(\d{1,3})(?![0-9])', caseSensitive: false),
    episodeGroup: 1,
    seasonFromFolder: true,
    defaultSeason: 1,
    rejectLeadingSeason: true,
  ),
  // 4) 第2季第05集 / 第05集 — Chinese scene naming.
  _EpisodePattern(
    regex: RegExp(r'第\s*(\d{1,2})\s*季\s*第\s*(\d{1,3})\s*集'),
    seasonGroup: 1,
    episodeGroup: 2,
  ),
  _EpisodePattern(
    regex: RegExp(r'第\s*(\d{1,3})\s*集'),
    episodeGroup: 1,
    seasonFromFolder: true,
    defaultSeason: 1,
  ),
  // 5) Part I / Pt.VI / Part 3 — a single-part season entry.
  _EpisodePattern(
    regex: RegExp(r'[\._ -](?:part|pt)[._ -]*([ivx]+|\d{1,2})(?![\w])', caseSensitive: false),
    episodeGroup: 1,
    seasonFromFolder: true,
    defaultSeason: 1,
  ),
  // 6) Air dates: yyyy.mm.dd or mm.dd.yyyy. Kodi uses the full year as
  //    season and the day as episode. The year must be one capture group.
  _EpisodePattern(
    regex: RegExp(r'(?<!\d)((?:19|20)\d{2})[.\-_](\d{2})[.\-_](\d{2})(?!\d)'),
    seasonGroup: 1,
    episodeGroup: 3,
    byDate: true,
  ),
  _EpisodePattern(
    regex: RegExp(r'(?<!\d)(\d{2})[.\-_](\d{2})[.\-_]((?:19|20)\d{2})(?!\d)'),
    seasonGroup: 3,
    episodeGroup: 2,
    byDate: true,
  ),
  // 7) foo.103 -> S01E03. MUST stay last: digits like 2024 look like 20x24.
  _EpisodePattern(
    regex: RegExp(r'[\/\\._ -]([1-9])(\d{2})(?!\d)'),
    seasonGroup: 1,
    episodeGroup: 2,
  ),
];

int? _romanToInt(String value) {
  const Map<String, int> values = <String, int>{
    'i': 1, 'v': 5, 'x': 10, 'l': 50, 'c': 100, 'd': 500, 'm': 1000,
  };
  final String lower = value.toLowerCase();
  if (RegExp(r'^[ivxlcdm]+$').hasMatch(lower) == false) {
    return int.tryParse(lower);
  }
  int total = 0;
  for (int i = 0; i < lower.length; i++) {
    final int current = values[lower[i]]!;
    final int next = i + 1 < lower.length ? values[lower[i + 1]]! : 0;
    total += current < next ? -current : current;
  }
  return total > 0 ? total : null;
}

int? _seasonFromFolderName(String? folder) {
  if (folder == null || folder.isEmpty) {
    return null;
  }
  final RegExpMatch? match = RegExp(
    r'(?:season|s)\s*(\d{1,2})|第\s*([一二三四五六七八九十\d]+)\s*季',
    caseSensitive: false,
  ).firstMatch(folder);
  if (match == null) {
    return null;
  }
  final String? digits = match.group(1) ?? match.group(2);
  if (digits == null) {
    return null;
  }
  return int.tryParse(digits) ?? _romanToInt(digits);
}

/// Parses a video file name into its series tag.
///
/// A folder hint is used by the bare-`E09` and `Part I` conventions, where
/// the season is encoded in the containing `Season 2` folder instead.
EpisodeTag? episodeTagFromFileName(String name, {String? folderHint}) {
  for (final _EpisodePattern rule in _episodePatterns) {
    final RegExpMatch? match = rule.regex.firstMatch(name);
    if (match == null) {
      continue;
    }
    int? season;
    if (rule.seasonGroup != null) {
      final String raw = match.group(rule.seasonGroup)!;
      season = rule.byDate ? int.tryParse(raw) : int.tryParse(raw);
    } else if (rule.seasonFromFolder) {
      season = _seasonFromFolderName(folderHint) ?? rule.defaultSeason;
    }
    final String rawEpisode = match.group(rule.episodeGroup)!;
    // Roman numerals (Part VI) and letter suffixes (S01E02a).
    final int? episode = int.tryParse(rawEpisode) ??
        int.tryParse(RegExp(r'^\d+').firstMatch(rawEpisode)?.group(0) ?? '') ??
        _romanToInt(rawEpisode);
    if (season == null || season < 0 || episode == null || episode < 1) {
      continue;
    }

    String show = name.substring(0, match.start).replaceAll(RegExp(r'[._]'), ' ');
    // "S02E05.mkv" reaches the bare-E rule with show == "S02". That is a
    // tag without a title, not an episode whose show is literally "S02".
    if (rule.rejectLeadingSeason &&
        RegExp(r'^\s*[Ss]\d{1,2}\s*$').hasMatch(show)) {
      continue;
    }
    show = show.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    // Plex/TMM style names put a hyphen between the show and the tag
    // ("Show - S02E05 - Title"). Only the trailing separator is stripped: a
    // hyphen inside a name ("Spider-Man") is part of the title.
    show = show.replaceAll(RegExp(r'\s*[-–—]+\s*$'), '').trim();
    if (show.isEmpty) {
      return null;
    }

    String tail = name.substring(match.end);
    final int dot = tail.lastIndexOf('.');
    if (dot > 0) {
      tail = tail.substring(0, dot);
    }
    tail = tail.replaceAll(RegExp(r'[._]'), ' ');
    for (final RegExp pattern in _releaseTags) {
      tail = tail.replaceAll(pattern, ' ');
    }
    tail = tail.replaceAll(RegExp(r'^\s*[-–—]+'), ' ');
    tail = tail.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    return EpisodeTag(
      show: show,
      season: season,
      episode: episode,
      episodeTitle: tail.isEmpty ? null : tail,
    );
  }
  return null;
}

/// Turns `Show.S01E03.1080p.WEB-DL.mkv` into something a person can read.
///
/// The release tags are stripped here, not from the item: the hub page still
/// shows the untouched file name, and a shelf title that reads like a scene
/// listing is the first thing that makes a library look like a file manager.
String prettifyFileName(String name) {
  final int dot = name.lastIndexOf('.');
  String base = dot > 0 ? name.substring(0, dot) : name;
  base = base.replaceAll(RegExp(r'[._]'), ' ');
  for (final RegExp pattern in _releaseTags) {
    base = base.replaceAll(pattern, ' ');
  }
  base = base.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return base.isEmpty ? name : base;
}

/// Four-digit year in a file name, if there is one.
int? yearFromFileName(String name) {
  final RegExpMatch? match = RegExp(r'(?:19|20)\d{2}').firstMatch(name);
  final int? value = match == null ? null : int.tryParse(match.group(0)!);
  if (value == null || value < 1900 || value > DateTime.now().year + 2) {
    return null;
  }
  return value;
}
