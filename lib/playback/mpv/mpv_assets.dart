import 'dart:io';

import 'package:flutter/services.dart';

/// Locates the Lua OSD that lives inside mpv, and explains itself when it
/// cannot.
///
/// The OSD is the entire player UI once video is on screen — a native child
/// window sits above Flutter, so a script that fails to load means no progress
/// bar, no menus, no key bindings. It failed silently once already: the app
/// passed an empty `script=` option and mpv simply had no UI. Every failure
/// path therefore records a reason in [lastError], and the caller both loads
/// the script explicitly and verifies it against `script-list`.
class MpvAssets {
  const MpvAssets._();

  static const String _assetKey = 'assets/mpv/player_osd.lua';
  static const String scriptName = 'player_osd.lua';

  static String? _cached;

  /// Why the last [osdScriptPath] call failed, for the F1 panel. Null on
  /// success.
  static String? lastError;

  /// Where every last-resort file goes: always writable, unlike the folder the
  /// exe happens to live in.
  static Directory get _fallbackDir {
    final String base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    return Directory('$base${Platform.pathSeparator}XnX Player${Platform.pathSeparator}scripts');
  }

  static Future<String?> osdScriptPath() async {
    final String? cached = _cached;
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }
    lastError = null;

    final String exeDir = File(Platform.resolvedExecutable).parent.path;
    final String sep = Platform.pathSeparator;
    String beside(String tail) => '$exeDir$sep${tail.replaceAll('/', sep)}$sep$scriptName';

    // Release layout, then two flattened layouts people end up with when they
    // copy the build folder around by hand.
    final List<String> candidates = <String>[
      beside('data/flutter_assets/assets/mpv'),
      beside('assets/mpv'),
      beside('data/assets/mpv'),
    ];

    final List<String> tried = <String>[];
    for (final String candidate in candidates) {
      tried.add(candidate);
      if (File(candidate).existsSync()) {
        _cached = candidate;
        return candidate;
      }
    }

    // Nothing beside the exe: the asset bundle is the source of truth, so write
    // it somewhere writable and use that copy.
    try {
      final ByteData data = await rootBundle.load(_assetKey);
      final Directory dir = _fallbackDir;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final File file = File('${dir.path}$sep$scriptName');
      final Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      // Rewriting on every launch is wasteful but keeps the copy honest when
      // the bundled script changes between builds.
      await file.writeAsBytes(bytes, flush: true);
      _cached = file.path;
      return file.path;
    } catch (error) {
      lastError = '找不到 OSD 脚本：exe 同目录下试过 ${tried.length} 个位置，'
          '资源包里也读不到 $_assetKey（$error）';
      return null;
    }
  }
}
