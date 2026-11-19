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

/// Turns `Show.S01E03.1080p.mkv` into something a person can read.
String prettifyFileName(String name) {
  final int dot = name.lastIndexOf('.');
  String base = dot > 0 ? name.substring(0, dot) : name;
  base = base.replaceAll(RegExp(r'[._]'), ' ').trim();
  return base;
}
