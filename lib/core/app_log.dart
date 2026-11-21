import 'dart:io';

/// The application's own log, separate from mpv's playback log.
///
/// Playback always wrote `player_mpv.log`, but the app itself was silent: a
/// launch that never reached the player, a source that failed to load or an
/// unhandled exception left nothing to inspect. This writes one line per
/// event to `<exe>/log/app.log`, falling back to
/// `%APPDATA%\XnX Player\log\app.log` when the install folder is read-only
/// (Program Files).
///
/// Everything here is best effort: a log write must never be the reason the
/// app fails to start or a refresh fails.
abstract final class AppLog {
  AppLog._();

  /// Roll over at 512 KiB, keeping the newest run rather than an archive.
  static const int _maxBytes = 512 * 1024;

  static String? _path;
  static Future<void> _tail = Future<void>.value();
  static bool _ready = false;

  /// The file being written, for the diagnostics surfaces.
  static String get path => _path ?? '（日志未初始化）';

  /// Resolves the log path and writes a first line. Safe to call more than
  /// once; the first successful call wins.
  static Future<void> init() async {
    if (_ready) {
      return;
    }
    final String? exe = _exeLogPath();
    final String? appData = _appDataLogPath();
    final List<String> candidates = <String>[
      if (exe != null) exe,
      if (appData != null) appData,
      '${Directory.systemTemp.path}${Platform.pathSeparator}XnX Player'
          '${Platform.pathSeparator}log${Platform.pathSeparator}app.log',
    ];
    final String stamp = DateTime.now().toIso8601String();
    for (final String candidate in candidates) {
      try {
        final File file = File(candidate);
        await file.parent.create(recursive: true);
        // Probe the file, not just the folder: the install-time `log/` exists
        // even for a user who cannot write into Program Files, and a folder
        // that merely exists would otherwise swallow every line silently.
        await file.writeAsString(
          '[$stamp][INFO] 日志开始：$candidate\n',
          mode: FileMode.append,
          flush: true,
        );
        _path = candidate;
        _ready = true;
        break;
      } on Object {
        // Try the next location.
      }
    }
  }

  static String? _exeLogPath() {
    try {
      final String dir = File(Platform.resolvedExecutable).parent.path;
      return '$dir${Platform.pathSeparator}log${Platform.pathSeparator}app.log';
    } on Object {
      return null;
    }
  }

  static String? _appDataLogPath() {
    final String? appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      return null;
    }
    return '$appData${Platform.pathSeparator}XnX Player'
        '${Platform.pathSeparator}log${Platform.pathSeparator}app.log';
  }

  static void info(String message) => _write('INFO', message);

  static void warn(String message) => _write('WARN', message);

  static void error(String message, [Object? error, StackTrace? stack]) {
    final StringBuffer buffer = StringBuffer(message);
    if (error != null) {
      buffer.write('：$error');
    }
    _write('ERROR', buffer.toString());
    if (stack != null) {
      // One line per frame keeps the file readable with a plain editor.
      for (final String line in stack.toString().split('\n')) {
        if (line.trim().isEmpty) {
          continue;
        }
        _write('ERROR', '  $line');
      }
    }
  }

  static void _write(String level, String message) {
    final String? path = _path;
    if (!_ready || path == null) {
      return;
    }
    final String stamp = DateTime.now().toIso8601String();
    final String line = '[$stamp][$level] $message\n';
    // Serialize writes: concurrent `append` calls would otherwise interleave
    // and truncate each other's lines.
    _tail = _tail.then((_) async {
      try {
        final File file = File(path);
        if (await file.exists() && await file.length() > _maxBytes) {
          await file.writeAsString('[$stamp][INFO] 日志已滚动\n');
        }
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } on Object {
        // Logging is a courtesy; ignore every failure.
      }
    });
  }
}
