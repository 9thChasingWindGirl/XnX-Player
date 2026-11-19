import 'dart:io';

import 'package:flutter/services.dart';

/// Resolves the on-disk path of the Lua OSD.
///
/// mpv can only load scripts from the filesystem, so the bundled asset is
/// looked up inside the Flutter bundle first and extracted to a temp folder as
/// a fallback (debug runs from the build tree).
class MpvAssets {
  const MpvAssets._();

  static const String _assetKey = 'assets/mpv/xnx_osd.lua';
  static const String scriptName = 'xnx_osd.lua';

  static String? _cached;

  static Future<String?> osdScriptPath() async {
    final String? cached = _cached;
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }

    final String exeDir = File(Platform.resolvedExecutable).parent.path;
    final String sep = Platform.pathSeparator;
    final List<String> candidates = <String>[
      '$exeDir${sep}data${sep}flutter_assets${sep}assets${sep}mpv${sep}$scriptName',
      '$exeDir${sep}assets${sep}mpv${sep}$scriptName',
      '$exeDir${sep}data${sep}assets${sep}mpv${sep}$scriptName',
    ];

    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) {
        _cached = candidate;
        return candidate;
      }
    }

    try {
      final data = await rootBundle.load(_assetKey);
      final Directory dir = Directory('${Directory.systemTemp.path}${sep}xnx_player');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final File file = File('${dir.path}${sep}$scriptName');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      _cached = file.path;
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
