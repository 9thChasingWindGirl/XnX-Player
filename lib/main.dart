import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'core/app_version.dart';
import 'core/strings.dart';
import 'update/update_service.dart';
import 'update/updater_app.dart';

Future<void> main(List<String> argv) async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app's own log comes up before anything that can fail: a launch that
  // dies in the window manager or never reaches the player has to leave a
  // trace, not just the playback log mpv writes later.
  await AppLog.init();
  S.appVersion = resolveAppVersion();

  // 更新应用模式：主程序下载完更新包后以 --apply-update 重启自身，这个
  // 进程就是"更新程序"——可视化进度与结果，替代静默的 PowerShell 脚本。
  final int applyIndex = argv.indexOf('--apply-update');
  if (applyIndex >= 0 && applyIndex + 1 < argv.length) {
    String dataDir = '';
    bool keepData = true;
    for (int i = 0; i < argv.length; i++) {
      if (argv[i] == '--data-dir' && i + 1 < argv.length) {
        dataDir = argv[++i];
      }
      if (argv[i] == '--keep-data' && i + 1 < argv.length) {
        keepData = argv[++i] == 'true';
      }
    }
    final String payloadDir = argv[applyIndex + 1];
    AppLog.info('更新程序启动：payload=$payloadDir keepData=$keepData');
    try {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: Size(520, 240),
          minimumSize: Size(520, 240),
          center: true,
          title: 'XnX 更新程序',
          titleBarStyle: TitleBarStyle.normal,
        ),
        () {
          unawaited(windowManager.show());
          unawaited(windowManager.focus());
        },
      );
    } on Object catch (error, stack) {
      AppLog.error('更新窗口初始化失败', error, stack);
    }
    runApp(UpdaterApp(
      payloadDir: payloadDir,
      dataDir: dataDir,
      keepData: keepData,
    ));
    return;
  }

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
    AppLog.info('主窗口已创建');
  } on Object catch (error, stack) {
    // Window management is a nicety; the app still runs if the plugin is
    // unavailable (for example in a headless smoke test).
    AppLog.error('窗口初始化失败', error, stack);
  }

  _ensureInstallDirs();
  // 上一轮更新留下的下载缓存与失败残骸（旧脚本、.updating 残留 exe）在
  // 这里清掉——更新成功与否，updates/ 都不该堆历史版本。
  UpdateService.pruneUpdateCache();

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
