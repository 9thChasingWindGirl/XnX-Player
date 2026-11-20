import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await windowManager.ensureInitialized();
    const WindowOptions options = WindowOptions(
      size: Size(1600, 900),
      minimumSize: Size(1024, 576),
      center: true,
      title: 'XnX Player',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () {
      unawaited(windowManager.show());
      unawaited(windowManager.focus());
    });
  } catch (_) {
    // Window management is a nicety; the app still runs if the plugin is
    // unavailable (for example in a headless smoke test).
  }

  _ensureInstallDirs();

  runApp(const XnXApp());
}

/// Creates the install-side directories up front instead of waiting for the
/// first writer.
///
/// Two reasons this runs at startup and ships as empty folders in the package:
/// the mpv log only exists if `log/` does (a user asked for a log file that
/// had never been written), and creating directories inside Program Files at
/// *write time* can fail under a standard token. The zip carries empty
/// `log/` and `updates/` so the permission-sensitive creation already
/// happened at install time; this is the portable-install fallback.
void _ensureInstallDirs() {
  try {
    final String dir = File(Platform.resolvedExecutable).parent.path;
    Directory('$dir${Platform.pathSeparator}log').createSync(recursive: true);
    Directory('$dir${Platform.pathSeparator}updates').createSync(recursive: true);
  } on Object {
    // Read-only install location: writers fall back to their own strategies
    // (mpv logs to %TEMP%, the updater reports the failure).
  }
}
