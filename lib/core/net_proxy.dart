import 'dart:io';

import 'app_log.dart';

/// How outbound HTTP requests choose a proxy.
///
/// Kept in core so the media client and the update downloader share one answer:
/// having two independent proxy paths is exactly how "the app cannot reach a
/// host that the browser reaches" happens.
enum ProxyMode { none, system, custom }

abstract final class NetProxy {
  static ProxyMode mode = ProxyMode.system;
  static String custom = '';

  /// What the OS reports, resolved once at startup. Windows records this in
  /// the registry, which `HttpClient.findProxyFromEnvironment` does not read.
  static String systemDetected = '';

  static void configure(String modeName, String address) {
    mode = ProxyMode.values.firstWhere(
      (ProxyMode value) => value.name == modeName,
      orElse: () => ProxyMode.system,
    );
    custom = address.trim();
  }

  /// Reads the Windows proxy setting. Other platforms fall back to env vars.
  static Future<void> detectSystem() async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      const String key =
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      final ProcessResult enable = await Process.run(
        'reg', <String>['query', key, '/v', 'ProxyEnable'],
      );
      final String enableText = enable.stdout as String? ?? '';
      final RegExpMatch? flag = RegExp(
        r'ProxyEnable\s+REG_DWORD\s+0x([0-9a-fA-F]+)',
      ).firstMatch(enableText);
      if (flag != null && int.parse(flag.group(1)!, radix: 16) == 0) {
        systemDetected = '';
        return;
      }
      final ProcessResult server = await Process.run(
        'reg', <String>['query', key, '/v', 'ProxyServer'],
      );
      final String serverText = server.stdout as String? ?? '';
      final RegExpMatch? value = RegExp(
        r'ProxyServer\s+REG_SZ\s+(.+)',
      ).firstMatch(serverText);
      if (value == null) {
        systemDetected = '';
        return;
      }
      final String raw = value.group(1)!.trim();
      // Windows can store "http=h:80;https=h:443" instead of a plain address.
      final RegExpMatch? https = RegExp(r'https\s*=\s*([^;]+)').firstMatch(raw);
      systemDetected = (https?.group(1) ?? raw.split(';').first).trim();
    } on Object {
      systemDetected = '';
    }
  }

  /// `HttpClient.findProxy` callback. Must stay synchronous.
  static bool _logged = false;

  static String resolve(Uri uri) {
    String result;
    switch (mode) {
      case ProxyMode.none:
        result = 'DIRECT';
      case ProxyMode.system:
        result = systemDetected.isNotEmpty
            ? 'PROXY $systemDetected'
            : HttpClient.findProxyFromEnvironment(uri);
      case ProxyMode.custom:
        result = custom.isEmpty
            ? 'DIRECT'
            // "PROXY a:80; PROXY b:80" is valid; keep input whitespace tidy.
            : 'PROXY ${custom.replaceAll(RegExp(r'\s+'), ' ')}';
    }
    if (!_logged) {
      _logged = true;
      AppLog.info('网络代理模式 ${mode.name}：$result');
    }
    return result;
  }
}
