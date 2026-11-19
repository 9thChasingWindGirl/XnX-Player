import 'dart:convert';

import '../models/media_item.dart';
import '../net.dart';
import 'media_source.dart';

/// OpenList / AList.
///
/// Files are streamed through `fs/get`'s `raw_url`, so the player never proxies
/// bytes: mpv opens the storage provider's own URL.
class AListSource extends MediaSource {
  AListSource(super.config);

  String? _token;

  String get _base => trimSlashes(config.url);

  Map<String, String> get _headers => <String, String>{
        'Authorization': _token ?? config.token,
        'Content-Type': 'application/json',
      };

  Future<void> _ensureToken() async {
    if ((_token ?? config.token).isNotEmpty) {
      _token ??= config.token;
      return;
    }
    if (_base.isEmpty) {
      throw const SourceException('请填写 OpenList 服务器地址');
    }
    final HttpResult result = await Http.postJson(
      Uri.parse('$_base/api/auth/login'),
      <String, dynamic>{'username': config.username, 'password': config.password},
    );
    if (!result.ok) {
      throw SourceException('登录失败（HTTP ${result.status}）');
    }
    final Map<String, dynamic> data = result.jsonMap;
    final Object? payload = data['data'];
    if (payload is Map<String, dynamic>) {
      _token = payload['token'] as String?;
    }
    if (_token == null || _token!.isEmpty) {
      throw const SourceException('OpenList 没有返回令牌');
    }
  }

  String get _root => config.path.isEmpty ? '/' : config.path;

  @override
  Future<List<MediaItem>> browse() async {
    await _ensureToken();
    return _list(_root);
  }

  Future<List<MediaItem>> _list(String path) async {
    final HttpResult result = await Http.postJson(
      Uri.parse('$_base/api/fs/list'),
      <String, dynamic>{
        'path': path,
        'password': '',
        'page': 1,
        'per_page': 500,
        'refresh': false,
      },
      headers: _headers,
    );
    if (!result.ok) {
      throw SourceException('读取目录失败（HTTP ${result.status}）');
    }
    final Map<String, dynamic> data = result.jsonMap;
    final Object? payload = data['data'];
    if (payload is! Map<String, dynamic>) {
      return const <MediaItem>[];
    }
    final Object? content = payload['content'];
    if (content is! List) {
      return const <MediaItem>[];
    }

    final List<MediaItem> out = <MediaItem>[];
    for (final Object? entry in content) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final String name = entry['name'] as String? ?? '';
      if (name.isEmpty) {
        continue;
      }
      final bool isDir = entry['is_dir'] as bool? ?? false;
      final int size = (entry['size'] as num?)?.toInt() ?? 0;
      final String child = path.endsWith('/') ? '$path$name' : '$path/$name';
      if (!isDir && !looksLikeVideo(name)) {
        continue;
      }
      out.add(
        MediaItem(
          id: '${config.id}::$child',
          sourceId: config.id,
          sourceKind: SourceKind.openlist,
          kind: isDir ? MediaKind.folder : MediaKind.file,
          title: isDir ? name : prettifyFileName(name),
          path: child,
          meta: isDir ? '文件夹' : _sizeLabel(size),
          badge: isDir ? null : '网盘',
          posterUrl: entry['thumb'] as String?,
          playable: !isDir,
        ),
      );
    }
    out.sort((MediaItem a, MediaItem b) {
      final bool aDir = a.kind == MediaKind.folder;
      final bool bDir = b.kind == MediaKind.folder;
      if (aDir != bDir) {
        return aDir ? -1 : 1;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return out;
  }

  @override
  Future<List<MediaItem>> children(MediaItem container) async {
    await _ensureToken();
    return _list(container.path ?? _root);
  }

  @override
  Future<String> resolve(MediaItem item) async {
    await _ensureToken();
    final HttpResult result = await Http.postJson(
      Uri.parse('$_base/api/fs/get'),
      <String, dynamic>{'path': item.path ?? _root, 'password': ''},
      headers: _headers,
    );
    if (!result.ok) {
      throw SourceException('获取直链失败（HTTP ${result.status}）');
    }
    final Object? payload = result.jsonMap['data'];
    if (payload is Map<String, dynamic>) {
      final String? raw = payload['raw_url'] as String?;
      if (raw != null && raw.isNotEmpty) {
        return raw;
      }
    }
    throw const SourceException('存储返回的直链为空');
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

/// Plain WebDAV (CloudDrive2, Nextcloud, Alist's dav endpoint, ...).
///
/// URLs are composed as `scheme://authority` + an absolute server path. WebDAV
/// hrefs are always rooted at the server, so keeping the configured URL's own
/// path prefix inside `_base` would duplicate it: with
/// `https://host/remote.php/dav/files/me` a listing of `/remote.php/dav/...`
/// would come out as `/remote.php/dav/files/me/remote.php/dav/...`.
class WebDavSource extends MediaSource {
  WebDavSource(super.config);

  Uri get _url => Uri.tryParse(
        config.url.contains('://') ? config.url.trim() : 'http://${config.url.trim()}',
      ) ??
      Uri();

  String get _origin =>
      _url.host.isEmpty ? '' : '${_url.scheme}://${_url.authority}';

  /// Absolute server path the browser starts at: the configured sub-path when
  /// present, otherwise whatever path the configured URL carried.
  String get _rootPath {
    final String configured = config.path.trim().isNotEmpty ? config.path.trim() : _url.path;
    final String normalized = _normalizePath(configured);
    return normalized == '/' ? '/' : '$normalized/';
  }

  Map<String, String> get _headers => <String, String>{
        'Authorization': Http.basic(config.username, config.password),
        'Accept': '*/*',
      };

  static const String _body = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:displayname/><d:resourcetype/><d:getcontentlength/><d:getlastmodified/>'
      '</d:prop></d:propfind>';

  @override
  Future<List<MediaItem>> browse() async {
    if (_origin.isEmpty) {
      throw const SourceException('请填写 WebDAV 地址');
    }
    return _list(_rootPath);
  }

  Future<List<MediaItem>> _list(String path) async {
    final Uri uri = Uri.parse('$_origin${path.startsWith('/') ? path : '/$path'}');
    final HttpResult result = await Http.propfind(uri, _body, headers: _headers);
    if (result.status == 401) {
      throw const SourceException('WebDAV 认证失败');
    }
    if (!result.ok && result.status != 207) {
      throw SourceException('WebDAV 返回 HTTP ${result.status}');
    }
    return parseWebDav(result.body, config.id, uri, path);
  }

  @override
  Future<List<MediaItem>> children(MediaItem container) async {
    return _list(container.path ?? '/');
  }

  @override
  Future<String> resolve(MediaItem item) async {
    final String path = item.path ?? '';
    if (path.startsWith('http')) {
      return path;
    }
    return '$_origin${path.startsWith('/') ? path : '/$path'}';
  }

  @override
  Map<String, String> headersFor(MediaItem item) => <String, String>{
        'Authorization': Http.basic(config.username, config.password),
      };
}

/// Namespace-agnostic PROPFIND reader, exported for tests.
List<MediaItem> parseWebDav(String xml, String sourceId, Uri requestUri, String requestPath) {
  final XmlNode root = parseXml(xml);
  final List<MediaItem> out = <MediaItem>[];

  for (final XmlNode response in root.descendants('response')) {
    final List<XmlNode> hrefs = response.descendants('href');
    if (hrefs.isEmpty) {
      continue;
    }
    final String rawHref = hrefs.first.trimmed;
    if (rawHref.isEmpty) {
      continue;
    }
    String decoded;
    try {
      decoded = Uri.decodeFull(rawHref);
    } on Object {
      decoded = rawHref;
    }

    final bool isDir = response.descendants('collection').isNotEmpty;
    final String name = _leafName(decoded);
    if (name.isEmpty) {
      continue;
    }
    // The PROPFIND response always includes the requested collection itself.
    // Compare whole paths (not suffixes): every folder href ends with '/', so a
    // suffix test on the root would drop the entire listing.
    if (_normalizePath(decoded) == _normalizePath(requestPath)) {
      continue;
    }
    if (!isDir && !looksLikeVideo(name)) {
      continue;
    }

    // A WebDAV href is already rooted at the server ("/dav/Movies/x.mkv"), so
    // it is a path, not something to resolve against the request URI. The
    // previous version rebuilt an absolute URL with
    // `requestUri.replace(query: '')`; that sets an *empty* query rather than
    // clearing it, so toString() produced "http://host?" and everything after
    // it parsed as a query string — leaving every path empty.
    final Uri? parsedHref = Uri.tryParse(decoded);
    final String rawPath;
    if (parsedHref != null && parsedHref.hasScheme) {
      rawPath = parsedHref.path; // Some servers return absolute URLs.
    } else if (decoded.startsWith('/')) {
      rawPath = decoded;
    } else {
      final String base = requestUri.path.endsWith('/')
          ? requestUri.path
          : '${requestUri.path}/';
      rawPath = '$base$decoded';
    }
    String path = _normalizePath(rawPath);
    // Keep the trailing slash on collections: PROPFIND on "/dav/Movies" 301s
    // to "/dav/Movies/" and dart:io does not re-send a non-GET method.
    if (isDir && path != '/') {
      path = '$path/';
    }
    final int size = int.tryParse(_descendantText(response, 'getcontentlength')) ?? 0;

    out.add(
      MediaItem(
        id: '$sourceId::$path',
        sourceId: sourceId,
        sourceKind: SourceKind.webdav,
        kind: isDir ? MediaKind.folder : MediaKind.file,
        title: isDir ? name : prettifyFileName(name),
        path: path,
        meta: isDir ? '文件夹' : (size > 0 ? '$size B' : ''),
        badge: isDir ? null : 'WebDAV',
        playable: !isDir,
      ),
    );
  }
  return out;
}

String _normalizePath(String path) {
  String value = path;
  final int query = value.indexOf('?');
  if (query >= 0) {
    value = value.substring(0, query);
  }
  if (!value.startsWith('/')) {
    value = '/$value';
  }
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

String _descendantText(XmlNode node, String tag) {
  final List<XmlNode> found = node.descendants(tag);
  return found.isEmpty ? '' : found.first.trimmed;
}

String _leafName(String href) {
  final String trimmed = href.endsWith('/') ? href.substring(0, href.length - 1) : href;
  final int slash = trimmed.lastIndexOf('/');
  final String name = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
  if (name.isEmpty) {
    return '';
  }
  try {
    return Uri.decodeComponent(name);
  } on Object {
    return name;
  }
}

/// Small re-export so callers can build the same auth header for mpv.
String webDavAuthHeader(String user, String password) => Http.basic(user, password);

/// Kept for symmetry with the other sources when serialising diagnostics.
String encodeJsonHeaders(Map<String, String> headers) => jsonEncode(headers);
