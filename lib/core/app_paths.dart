import 'dart:io';

/// Where the app keeps user data.
///
/// Resolution order:
/// 1. `XNX_DATA_DIR` environment variable (advanced/portable launchers)
/// 2. `data-dir.txt` next to the executable
///    - `default` → `%APPDATA%\XnX Player`
///    - a relative path → relative to the executable (portable mode uses
///      `userdata`, so the payload stays self-contained; it cannot be `data`,
///      which is Flutter's runtime asset directory)
///    - an absolute path → used as-is (installer custom page)
/// 3. `%APPDATA%\XnX Player`
///
/// The installer writes `data-dir.txt`; the portable zip ships one containing
/// `userdata`. Updates never touch this file or the directory it points at.
abstract final class AppPaths {
  AppPaths._();

  static String get installDir {
    try {
      return File(Platform.resolvedExecutable).parent.path;
    } on Object {
      return Directory.current.path;
    }
  }

  static final String dataDir = _resolveDataDir();

  static String get logDir => '$dataDir${Platform.pathSeparator}log';

  static String get screenshotDir => '$dataDir${Platform.pathSeparator}screenshots';

  static String get statePath => '$dataDir${Platform.pathSeparator}state.json';

  static String _resolveDataDir() {
    final String exeDir = installDir;
    final String? env = Platform.environment['XNX_DATA_DIR'];
    if (env != null && env.trim().isNotEmpty) {
      return _absolute(env.trim(), exeDir);
    }
    try {
      final File pointer = File('$exeDir${Platform.pathSeparator}data-dir.txt');
      if (pointer.existsSync()) {
        final String raw = pointer.readAsStringSync().trim();
        if (raw.isNotEmpty) {
          if (raw.toLowerCase() == 'default') {
            return _appDataDefault(exeDir);
          }
          return _absolute(raw, exeDir);
        }
      }
    } on Object {
      // Fall through to the default; the installer may not have written it yet.
    }
    return _appDataDefault(exeDir);
  }

  static String _appDataDefault(String fallback) {
    final String? appData = Platform.environment['APPDATA'];
    final String base =
        appData != null && appData.isNotEmpty ? appData : fallback;
    return '$base${Platform.pathSeparator}XnX Player';
  }

  static String _absolute(String value, String exeDir) {
    final bool absolute = RegExp(r'^[A-Za-z]:[\\/]|^\\\\').hasMatch(value) ||
        value.startsWith('/');
    if (absolute) {
      return value;
    }
    return '$exeDir${Platform.pathSeparator}$value';
  }
}
