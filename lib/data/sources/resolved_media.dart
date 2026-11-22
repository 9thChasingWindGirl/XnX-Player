/// What a source produced for one item: the URL mpv opens, plus what is known
/// about that URL's lifetime.
///
/// Kodi's `IDirectory::Resolve` returns the same triple — a URL, the headers the
/// fetch needs, and how long the answer stays valid — because resolving is a
/// round trip whose result can go stale. Returning a bare `String`, which is
/// what [MediaSource.resolve] does, throws that away: a signed URL that expired
/// while the app sat in a menu can only produce a generic "cannot play", and a
/// source that needs an `Authorization` header has to smuggle it into the URL.
///
/// The player only reads [uri] today. [expiresAt] exists so the retry path can
/// be added without changing every source: a resolver that knows its link is
/// temporary fills it in, and the caller re-asks instead of reporting failure.
class ResolvedMedia {
  const ResolvedMedia({
    required this.uri,
    this.headers = const <String, String>{},
    this.expiresAt,
  });

  /// The address handed to mpv. For local files this is a path; for a backend
  /// it is whatever URL that backend signed for us.
  final String uri;

  /// Extra request headers the URL needs. Empty means "the URL says it all",
  /// which is how Emby (`api_key` in the query) and WebDAV (userinfo) work.
  final Map<String, String> headers;

  /// When [uri] stops being valid, or null when it does not expire.
  final DateTime? expiresAt;

  bool get hasHeaders => headers.isNotEmpty;

  /// Whether the link is only good for a while.
  bool get isTemporary => expiresAt != null;

  /// Whether the link is already useless at [now].
  ///
  /// A null [expiresAt] never expires — treating "unknown" as "expired" would
  /// make every local file unplayable.
  bool isExpiredAt(DateTime now) {
    final DateTime? deadline = expiresAt;
    return deadline != null && !now.isBefore(deadline);
  }

  /// How long the link is still good for. Null when it does not expire.
  Duration? remainingAt(DateTime now) {
    final DateTime? deadline = expiresAt;
    if (deadline == null) {
      return null;
    }
    final Duration left = deadline.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  ResolvedMedia copyWith({
    String? uri,
    Map<String, String>? headers,
    DateTime? expiresAt,
  }) {
    return ResolvedMedia(
      uri: uri ?? this.uri,
      headers: headers ?? this.headers,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ResolvedMedia &&
        other.uri == uri &&
        other.expiresAt == expiresAt &&
        _sameHeaders(other.headers, headers);
  }

  @override
  int get hashCode => Object.hash(uri, expiresAt, headers.length);

  @override
  String toString() {
    return 'ResolvedMedia($uri, ${headers.length} headers, '
        '${expiresAt == null ? 'no expiry' : 'until $expiresAt'})';
  }
}

bool _sameHeaders(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<String, String> entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
