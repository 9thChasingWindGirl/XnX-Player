import 'dart:async';

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

  runApp(const XnXApp());
}
