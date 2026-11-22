import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'core/app_version.dart';
import 'core/net_proxy.dart';
import 'core/strings.dart';
import 'core/window_sizing.dart';
import 'update/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app's own log comes up before anything that can fail: a launch that
  // dies in the window manager or never reaches the player has to leave a
  // trace, not just the playback log mpv writes later.
  await AppLog.init();
  S.appVersion = resolveAppVersion();
  AppLog.info('XnX Player ${S.appVersion} 启动 '
      '(${Platform.operatingSystem} ${Platform.operatingSystemVersion})');
  AppLog.info('可执行文件：${Platform.resolvedExecutable}');
  // A rollback snapshot is a complete portable build; launching it silently
  // relocates the install root and nests another app on every update.
  UpdateService.reportSnapshotLaunch();

  FlutterError.onError = (FlutterErrorDetails details) {
    AppLog.error('未捕获的界面异常', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLog.error('未捕获的异步异常', error, stack);
    return true;
  };

  try {
    await windowManager.ensureInitialized();
    // Fit the window to the display instead of assuming a 1080p monitor: on a
    // 1366x768 laptop a hard-coded 1600x900 starts off-screen, and a user can
    // drag any shape they like, which collapses the 16:9 OSD bottom band.
    Size startSize = WindowSizing.minimum;
    try {
      final Display display = await windowManager.getDisplay();
      startSize = WindowSizing.fit(Size(
        display.size.width.toDouble(),
        display.size.height.toDouble(),
      ));
    } on Object catch (error) {
      AppLog.warn('读取显示器尺寸失败，使用默认窗口：$error');
    }
    final WindowOptions options = WindowOptions(
      size: startSize,
      minimumSize: WindowSizing.minimum,
      center: true,
      title: 'XnX Player',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () {
      unawaited(windowManager.show());
      unawaited(windowManager.focus());
    });
    // Hard constraint: resizing keeps 16:9, the aspect the OSD is drawn in.
    // Maximize/fullscreen still work — those bypass the aspect lock.
    try {
      await windowManager.setAspectRatio(WindowSizing.aspect);
    } on Object catch (error) {
      AppLog.warn('设置窗口宽高比失败：$error');
    }
    AppLog.info('主窗口已创建：${startSize.width.toInt()}x${startSize.height.toInt()} '
        '（16:9，最小 ${WindowSizing.minimum.width.toInt()}x'
        '${WindowSizing.minimum.height.toInt()}）');
  } on Object catch (error, stack) {
    // Window management is a nicety; the app still runs if the plugin is
    // unavailable (for example in a headless smoke test).
    AppLog.error('窗口初始化失败', error, stack);
  }

  // Dart does not read the Windows proxy settings; resolve them once before
  // any HTTP client asks for a route.
  await NetProxy.detectSystem();

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
  } on Object catch (error) {
    // Read-only install location: writers fall back to their own strategies
    // (mpv logs to %TEMP%, the updater reports the failure).
    AppLog.warn('安装目录不可写，改用用户目录：$error');
  }
}
