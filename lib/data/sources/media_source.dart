import '../models/media_item.dart';

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
];

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
