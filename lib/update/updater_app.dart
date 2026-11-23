import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

/// 更新应用模式：主程序以 `--apply-update` 重启自身，这个极简窗口接管
/// 覆盖安装的全程——有进度、有结果、有错误，替代旧版静默的 PowerShell
/// 脚本（脚本任何一步抛错都是无声失败，用户只看到版本没变）。
///
/// 复制策略与旧脚本一致：清扫安装目录（保护数据/日志/updates），再从
/// payload 覆盖。差别是每一步都发生在 Dart 里：文件锁导致的失败会被
/// 捕获并显示在窗口上，而不是把脚本杀死在半路。
class UpdaterApp extends StatelessWidget {
  const UpdaterApp({
    super.key,
    required this.payloadDir,
    required this.dataDir,
    required this.keepData,
  });

  final String payloadDir;
  final String dataDir;
  final bool keepData;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0070CC)),
      home: _UpdaterPage(
        payloadDir: payloadDir,
        dataDir: dataDir,
        keepData: keepData,
      ),
    );
  }
}

class _UpdaterPage extends StatefulWidget {
  const _UpdaterPage({
    required this.payloadDir,
    required this.dataDir,
    required this.keepData,
  });

  final String payloadDir;
  final String dataDir;
  final bool keepData;

  @override
  State<_UpdaterPage> createState() => _UpdaterPageState();
}

class _UpdaterPageState extends State<_UpdaterPage> {
  String _status = '等待主程序退出…';
  double _progress = 0;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      // 旧进程刚调过 exit(0)，但状态保存、mpv 收尾需要一点时间；被锁定
      // 的文件会让清扫/复制半途而废，宁可多等一秒。
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await _swap();
      setState(() {
        _status = '更新完成，正在启动新版本…';
        _progress = 1;
        _done = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await _launchNewVersion();
      exit(0);
    } on Object catch (error) {
      setState(() => _error = '$error');
    }
  }

  Future<void> _swap() async {
    final Directory install =
        File(Platform.resolvedExecutable).parent;
    final String installPath = install.path;
    final String sep = Platform.pathSeparator;

    // 保护名单：数据目录、日志、更新缓存、安装记录不动；data-dir.txt
    // 记录数据位置，更新包里的那份只对全新解压有意义。数据目录在
    // %APPDATA% 之类的安装目录外时，没有段需要保护。
    final Set<String> protect = <String>{
      'updates',
      'log',
      'userdata',
      'data-dir.txt',
    };
    final String lowerInstall =
        installPath.endsWith(sep) ? installPath : '$installPath$sep';
    if (widget.dataDir.toLowerCase().startsWith(lowerInstall.toLowerCase())) {
      final String first = widget.dataDir
          .substring(lowerInstall.length)
          .split(RegExp(r'[\\/]'))
          .first;
      if (first.isNotEmpty) {
        protect.add(first.toLowerCase());
      }
    }

    // 1) 让出主程序 exe 的位置：Windows 允许对运行中的 exe 改名，不允许
    //    删除/覆盖——改名后新 exe 才能落位。新版本启动时清掉 .updating。
    final File selfExe = File(Platform.resolvedExecutable);
    final String oldExePath = '$installPath${sep}xnx_player.exe.updating';
    if (await selfExe.exists()) {
      await selfExe.rename(oldExePath);
    }

    // 2) 清扫安装目录（旧 exe 已让位，其余按保护名单跳过；个别锁定
    //    文件跳过不阻塞——复制阶段对它们会再试一次）。
    final List<FileSystemEntity> stale = <FileSystemEntity>[];
    await for (final FileSystemEntity entity in install.list()) {
      if (protect.contains(entity.uri.pathSegments.last.toLowerCase()) ||
          entity.path == oldExePath) {
        continue;
      }
      stale.add(entity);
    }
    for (final FileSystemEntity entity in stale) {
      try {
        await entity.delete(recursive: true);
      } on Object {
        // 锁定文件留给复制阶段报错——那里有可见的失败说明。
      }
    }

    // 3) 统计 payload 总字节，给进度条一个真实的分母。
    final List<File> files = <File>[];
    int totalBytes = 0;
    await for (final FileSystemEntity entity
        in Directory(widget.payloadDir).list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final String name = entity.uri.pathSegments.last;
      final String parent = entity.parent.uri.pathSegments.last;
      // 更新包里的 data-dir.txt 与缓存目录不属于安装目录。
      if (name == 'data-dir.txt' && entity.parent.path == widget.payloadDir) {
        continue;
      }
      if (parent == 'updates' || parent == 'log') {
        continue;
      }
      files.add(entity);
      totalBytes += entity.lengthSync();
    }

    // 4) 逐文件覆盖，按字节推进度条。
    int copied = 0;
    for (final File file in files) {
      final String relative = file.path.substring(widget.payloadDir.length + 1);
      final String target = '$installPath$sep$relative';
      await File(target).parent.create(recursive: true);
      try {
        await file.copy(target);
      } on Object {
        // 目标被锁（旧进程未完全退出）：改个名再复制。目标不存在时
        // 直接重抛——那才是真正的失败。
        if (await File(target).exists()) {
          await File(target).rename('$target.updating');
          await file.copy(target);
        } else {
          rethrow;
        }
      }
      copied += file.lengthSync();
      if (mounted) {
        setState(() {
          _status = '正在复制 ${relative.split(RegExp(r'[\\/]')).last}';
          _progress = totalBytes > 0 ? copied / totalBytes : 0;
        });
      }
    }

    // 5) 用户选了"不保留"：只清配置与库日志，数据目录本身留着。
    if (!widget.keepData && widget.dataDir.isNotEmpty) {
      for (final String name in <String>['state.json', 'library.log']) {
        final File file = File('${widget.dataDir}$sep$name');
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  Future<void> _launchNewVersion() async {
    final String exe =
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}xnx_player.exe';
    await Process.start(exe, <String>[], mode: ProcessStartMode.detached);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101318),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '正在更新 XnX Player',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFFFFF),
                ),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _error == null ? _progress : 0,
                  minHeight: 8,
                  backgroundColor: const Color(0x22FFFFFF),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF0070CC)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _error ?? _status,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: _error == null
                      ? const Color(0x99FFFFFF)
                      : const Color(0xFFF56C6C),
                ),
              ),
              if (_done) ...<Widget>[
                const SizedBox(height: 6),
                const Text(
                  '更新成功',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF67C23A),
                  ),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 14),
                // 失败不再静默：窗口停在这里，主程序没有被破坏——用户
                // 关闭后可以重试或手动检查。
                TextButton(
                  onPressed: () => exit(1),
                  child: const Text('关闭'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
