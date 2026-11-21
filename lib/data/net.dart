import 'dart:convert';
import 'dart:io';

/// Minimal HTTP client built on `dart:io`.
///
/// Deliberately dependency-free: the whole backend layer (Emby, AList, WebDAV,
/// IPTV) speaks nothing more exotic than GET/POST/PROPFIND with a JSON or XML
/// body, and every package added to a Windows build is another thing that can
/// break CI.
class HttpResult {
  const HttpResult(this.status, this.body, this.headers);

  final int status;
  final String body;
  final Map<String, String> headers;

  bool get ok => status >= 200 && status < 300;

  Object? get json {
    final Object? decoded = jsonDecode(body);
    return decoded;
  }

  Map<String, dynamic> get jsonMap {
    final Object? decoded = body.isEmpty ? null : jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('响应不是 JSON 对象');
  }
}

class HttpFailure implements Exception {
  const HttpFailure(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : '$message (HTTP $status)';
}

abstract final class Http {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..autoUncompress = true
    ..userAgent = 'XnX Player/0.1 (Windows)';

  static const Map<String, String> userAgentHeader = <String, String>{
    'User-Agent': 'XnX Player/0.1 (Windows)',
  };

  static String basic(String user, String password) =>
      'Basic ${base64Encode(utf8.encode('$user:$password'))}';

  static String bearer(String token) => 'Bearer $token';

  static Future<HttpResult> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    String? contentType,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    // The whole exchange is bounded, not just the handshake: a server that
    // accepts the connection and then stalls mid-body used to hang the caller
    // forever, which is how a library refresh got stuck on "loading".
    final Future<HttpResult> exchange = _exchange(method, uri, headers, body, contentType);
    return exchange.timeout(timeout, onTimeout: () {
      throw HttpFailure('请求超时（${timeout.inSeconds}s）：${uri.host}');
    });
  }

  static Future<HttpResult> _exchange(
    String method,
    Uri uri,
    Map<String, String>? headers,
    String? body,
    String? contentType,
  ) async {
    final HttpClientRequest request = await _client.openUrl(method, uri);
    headers?.forEach((String name, String value) => request.headers.set(name, value));
    if (body != null) {
      request.headers.contentType = ContentType.parse(contentType ?? 'application/json; charset=utf-8');
      request.add(utf8.encode(body));
    }
    final HttpClientResponse response = await request.close();
    final String text = await response.transform(utf8.decoder).join();
    final Map<String, String> out = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      out[name.toLowerCase()] = values.join(', ');
    });
    return HttpResult(response.statusCode, text, out);
  }

  static Future<HttpResult> get(Uri uri, {Map<String, String>? headers}) =>
      send('GET', uri, headers: headers);

  static Future<HttpResult> postJson(
    Uri uri,
    Object body, {
    Map<String, String>? headers,
  }) =>
      send(
        'POST',
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
          ...?headers,
        },
        body: jsonEncode(body),
      );

  /// PROPFIND needs a body and a Depth header; it is the whole WebDAV protocol.
  static Future<HttpResult> propfind(
    Uri uri,
    String body, {
    Map<String, String>? headers,
    String depth = '1',
  }) =>
      send(
        'PROPFIND',
        uri,
        headers: <String, String>{
          'Depth': depth,
          'Content-Type': 'application/xml; charset=utf-8',
          ...?headers,
        },
        body: body,
      );

  static Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final HttpResult result = await get(uri, headers: headers);
    if (!result.ok) {
      throw HttpFailure('请求失败', status: result.status);
    }
    return result.jsonMap;
  }

  /// Same contract as [getJson] for endpoints that answer a JSON *array* —
  /// GitHub's /releases does, and the update checker used to hit a
  /// FormatException on every stable/beta/dev check because of it.
  static Future<List<dynamic>> getJsonList(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final HttpResult result = await get(uri, headers: headers);
    if (!result.ok) {
      throw HttpFailure('请求失败', status: result.status);
    }
    final Object? decoded = result.json;
    if (decoded is List<dynamic>) {
      return decoded;
    }
    if (decoded is Map<String, dynamic>) {
      return <Map<String, dynamic>>[decoded];
    }
    throw const FormatException('响应不是 JSON 列表');
  }

  static void close() => _client.close(force: true);
}

/// A parsed XML element, enough for XMLTV and WebDAV.
class XmlNode {
  XmlNode(this.name, [this.attributes = const <String, String>{}, this.parent]);

  final String name;
  final Map<String, String> attributes;
  final XmlNode? parent;
  final List<XmlNode> children = <XmlNode>[];
  String text = '';

  String get trimmed => text.trim();

  String attr(String key) => attributes[key.toLowerCase()] ?? '';

  XmlNode? child(String tag) {
    final String key = tag.toLowerCase();
    for (final XmlNode node in children) {
      if (node.name == key) {
        return node;
      }
    }
    return null;
  }

  List<XmlNode> named(String tag) {
    final String key = tag.toLowerCase();
    return children.where((XmlNode node) => node.name == key).toList(growable: false);
  }

  /// Depth-first search, so namespaced documents (`d:response`) work without a
  /// namespace resolver.
  List<XmlNode> descendants(String tag) {
    final String key = tag.toLowerCase();
    final List<XmlNode> out = <XmlNode>[];
    void walk(XmlNode node) {
      for (final XmlNode child in node.children) {
        if (child.name == key) {
          out.add(child);
        }
        walk(child);
      }
    }

    walk(this);
    return out;
  }

  String? textOf(String tag) => child(tag)?.trimmed;
}

/// Tiny namespace-agnostic XML reader.
///
/// Strips the prefix from element names (`d:href` -> `href`) and lowercases the
/// rest, which is why a single reader can handle both XMLTV and PROPFIND.
XmlNode parseXml(String source) {
  final XmlNode root = XmlNode('#document');
  final List<XmlNode> stack = <XmlNode>[root];
  int i = 0;

  while (i < source.length) {
    final int lt = source.indexOf('<', i);
    if (lt == -1) {
      stack.last.text += _decode(source.substring(i));
      break;
    }
    if (lt > i) {
      stack.last.text += _decode(source.substring(i, lt));
    }

    if (source.startsWith('<!--', lt)) {
      final int end = source.indexOf('-->', lt);
      i = end == -1 ? source.length : end + 3;
      continue;
    }
    if (source.startsWith('<![CDATA[', lt)) {
      final int end = source.indexOf(']]>', lt);
      final int stop = end == -1 ? source.length : end;
      stack.last.text += source.substring(lt + 9, stop);
      i = end == -1 ? source.length : end + 3;
      continue;
    }
    if (source.startsWith('<?', lt)) {
      final int end = source.indexOf('?>', lt);
      i = end == -1 ? source.length : end + 2;
      continue;
    }
    if (source.startsWith('<!', lt)) {
      final int end = source.indexOf('>', lt);
      i = end == -1 ? source.length : end + 1;
      continue;
    }

    final int gt = source.indexOf('>', lt);
    if (gt == -1) {
      break;
    }
    String inner = source.substring(lt + 1, gt);

    if (inner.startsWith('/')) {
      final String name = _local(inner.substring(1).trim());
      for (int s = stack.length - 1; s > 0; s--) {
        if (stack[s].name == name) {
          stack.removeRange(s, stack.length);
          break;
        }
      }
      i = gt + 1;
      continue;
    }

    final bool selfClosing = inner.endsWith('/');
    if (selfClosing) {
      inner = inner.substring(0, inner.length - 1);
    }

    int p = 0;
    while (p < inner.length && !_isSpace(inner.codeUnitAt(p)) && inner[p] != '/') {
      p++;
    }
    final String name = _local(inner.substring(0, p));
    if (name.isEmpty) {
      i = gt + 1;
      continue;
    }
    final XmlNode node = XmlNode(name, _attributes(inner.substring(p)), stack.last);
    stack.last.children.add(node);
    if (!selfClosing) {
      stack.add(node);
    }
    i = gt + 1;
  }

  return root;
}

String _local(String raw) {
  final int colon = raw.indexOf(':');
  final String name = colon == -1 ? raw : raw.substring(colon + 1);
  return name.trim().toLowerCase();
}

bool _isSpace(int code) => code == 32 || code == 9 || code == 10 || code == 13;

Map<String, String> _attributes(String input) {
  final Map<String, String> out = <String, String>{};
  int i = 0;
  while (i < input.length) {
    while (i < input.length && (_isSpace(input.codeUnitAt(i)) || input[i] == '/')) {
      i++;
    }
    if (i >= input.length) {
      break;
    }
    final int start = i;
    while (i < input.length && input[i] != '=' && !_isSpace(input.codeUnitAt(i))) {
      i++;
    }
    final String name = input.substring(start, i).toLowerCase();
    while (i < input.length && _isSpace(input.codeUnitAt(i))) {
      i++;
    }
    if (i >= input.length || input[i] != '=') {
      if (name.isNotEmpty) {
        out[name] = '';
      }
      continue;
    }
    i++;
    while (i < input.length && _isSpace(input.codeUnitAt(i))) {
      i++;
    }
    String value;
    if (i < input.length && (input[i] == '"' || input[i] == "'")) {
      final String quote = input[i];
      i++;
      final int end = input.indexOf(quote, i);
      value = end == -1 ? input.substring(i) : input.substring(i, end);
      i = end == -1 ? input.length : end + 1;
    } else {
      final int valueStart = i;
      while (i < input.length && !_isSpace(input.codeUnitAt(i))) {
        i++;
      }
      value = input.substring(valueStart, i);
    }
    if (name.isNotEmpty) {
      out[name] = _decode(value);
    }
  }
  return out;
}

String _decode(String input) {
  if (!input.contains('&')) {
    return input;
  }
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}
