import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Locates the Lua that lives inside mpv, and explains itself when it cannot.
///
/// The OSD is the entire player UI once video is on screen — a native child
/// window sits above Flutter, so a script that fails to load means no progress
/// bar, no menus, no key bindings. It failed silently once already: the app
/// passed an empty `script=` option and mpv simply had no UI. Every failure
/// path therefore records a reason in [lastError], and the caller both loads
/// the script explicitly and verifies it against `script-list`.
///
/// The startup format badges need a second thing: a folder of BGRA bitmaps that
/// `overlay-add` reads straight from disk. Those are unpacked once, guarded by
/// the manifest version, because rewriting 3.4MB on every launch is a visible
/// delay for no benefit.
class MpvAssets {
  const MpvAssets._();

  static const String osdScript = 'player_osd.lua';
  static const String logoScript = 'startup_format_logos.lua';

  /// A Lua *module*, not a script: [logoScript] pulls it in with `dofile`.
  ///
  /// It still has to be unpacked next to the badge script — `dofile` reads it
  /// off disk at load time — but it must never be handed to mpv as a script of
  /// its own. Loading a module that only returns a table runs it twice and
  /// starts a second Lua state for something with no top-level effect.
  static const String logoBounds = 'startup-logo-bounds.lua';

  /// Logos actually shipped in the bundle. The upstream manifest describes a
  /// much larger wall; anything missing here is simply absent from
  /// [formatLogoDir] and the Lua side skips it.
  static const List<String> bundledLogos = <String>[
    'dolby-vision',
    'hdr-vivid',
    'hdr10-plus',
    'hdr10',
    'hlg',
    'sdr',
    'dolby-atmos',
    'dts-x',
    'dolby-truehd',
    'dts-hd-ma',
    'dolby-digital-plus',
    'dolby-digital',
    'dts',
    'aac',
  ];

  static const String _logoAssetDir = 'assets/mpv/format-logos';

  static String? _cached;
  static String? _logoDirCached;

  /// Why the last lookup failed, for the F1 panel. Null on success.
  static String? lastError;

  /// Where every last-resort file goes: always writable, unlike the folder the
  /// exe happens to live in.
  static Directory get _fallbackDir {
    final String base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    return Directory('$base${Platform.pathSeparator}XnX Player${Platform.pathSeparator}scripts');
  }

  /// Absolute path to a Lua script, unpacking the bundled copy if needed.
  static Future<String?> scriptPath(String name) async {
    final String sep = Platform.pathSeparator;
    final String exeDir = File(Platform.resolvedExecutable).parent.path;

    // Release layout, then two flattened layouts people end up with when they
    // copy the build folder around by hand.
    for (final String folder in <String>['data/flutter_assets/assets/mpv', 'assets/mpv', 'data/assets/mpv']) {
      final String candidate = '$exeDir$sep${folder.replaceAll('/', sep)}$sep$name';
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    try {
      final ByteData data = await rootBundle.load('assets/mpv/$name');
      final Directory dir = _fallbackDir;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final File file = File('${dir.path}$sep$name');
      final Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      // Rewriting on every launch keeps the copy honest when the bundled script
      // changes between builds; these files are small.
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (error) {
      lastError = '找不到 $name：exe 同目录下试过 3 个位置，'
          '资源包里也读不到 assets/mpv/$name（$error）';
      return null;
    }
  }

  /// Kept for callers that only care about the OSD.
  static Future<String?> osdScriptPath() async {
    final String? cached = _cached;
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }
    final String? path = await scriptPath(osdScript);
    _cached = path;
    return path;
  }

  /// The folder `overlay-add` reads BGRA frames from, unpacked from the bundle.
  ///
  /// Returns null when the bundle has no logos at all; the badge script then
  /// fails to find its manifest and does nothing, which is the correct
  /// degradation — the player works, it just does not light up a logo.
  static Future<String?> formatLogoDir() async {
    final String sep = Platform.pathSeparator;
    final String? cached = _logoDirCached;
    if (cached != null && File('$cached${sep}manifest.json').existsSync()) {
      return cached;
    }

    final Directory dir = Directory('${_fallbackDir.parent.path}${sep}format-logos');
    try {
      final ByteData raw = await rootBundle.load('$_logoAssetDir/manifest.json');
      final Uint8List manifestBytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
      final Map<String, dynamic> manifest =
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;

      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final String stamp = '${manifest['version'] ?? 0}';
      final File stampFile = File('${dir.path}$sep.version');
      if (stampFile.existsSync() && stampFile.readAsStringSync().trim() == stamp) {
        _logoDirCached = dir.path;
        return dir.path;
      }

      await File('${dir.path}${sep}manifest.json').writeAsBytes(manifestBytes, flush: true);

      final Map<String, dynamic> logos =
          (manifest['logos'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      int written = 0;
      for (final String slug in bundledLogos) {
        final Map<String, dynamic>? logo = (logos[slug] as Map?)?.cast<String, dynamic>();
        if (logo == null) {
          continue;
        }
        // Only the 156x64 tier ships; the Lua side asks for 1x at 1080p.
        final Map<String, dynamic>? variants = (logo['variants'] as Map?)?.cast<String, dynamic>();
        final Map<String, dynamic>? oneX = (variants?['1'] as Map?)?.cast<String, dynamic>();
        final Map<String, dynamic>? files = (oneX?['files'] as Map?)?.cast<String, dynamic>();
        if (files == null) {
          continue;
        }
        for (final dynamic name in files.values) {
          final String file = name as String;
          final ByteData data = await rootBundle.load('$_logoAssetDir/$file');
          await File('${dir.path}$sep$file').writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          written++;
        }
      }
      stampFile.writeAsStringSync(stamp);
      _logoDirCached = dir.path;
      if (written == 0) {
        lastError = '格式徽章资源为空：manifest.json 里没有找到已随包附带的 Logo';
      }
      return dir.path;
    } catch (error) {
      lastError = '格式徽章资源解包失败：$error';
      return null;
    }
  }
}
