import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/app_paths.dart';
import '../../core/notice_center.dart';
import '../../core/input/input_action.dart';
import '../../core/input/input_router.dart';
import '../../core/strings.dart';
import '../../data/prefs.dart';
import '../../data/store.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/motion_clock.dart';
import '../../ui/core/text_entry.dart';
import '../../ui/core/tv_focusable.dart';
import '../../ui/core/tv_scale.dart';
import '../../ui/widgets/ps_button.dart';
import '../../update/update_channel.dart';
import '../../update/update_service.dart';

/// "Control Room": the settings screen.
///
/// Every row is one spring-highlight rectangle away from its neighbour, sliders
/// and steppers consume left/right themselves (so a D-pad can change a value
/// without leaving the row), and every change is written straight to
/// `state.json` — nothing is applied only at exit.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _age = 0;
  double _last = -1;

  UpdateChannel _channel = UpdateService.defaultChannel;
  String _updateStatus = '检查更新后在此显示结果';

  /// Last download fraction reported, used to throttle status repaints.
  double _downloadProgress = 0;
  UpdateCandidate? _pending;
  final UpdateService _updater = UpdateService();

  /// Rollback targets, read once. `installedVersions()` walks a directory on
  /// disk and this page rebuilds every frame (MotionBuilder), so calling it
  /// from `build` was both slow and — because the row ignored left/right — a
  /// control that showed a version you could not actually pick.
  List<String> _rollbackVersions = const <String>[];
  int _rollbackIndex = 0;

  @override
  void initState() {
    super.initState();
    _refreshRollbackVersions();
  }

  void _refreshRollbackVersions() {
    final List<String> versions = _updater.installedVersions();
    _rollbackVersions = versions;
    if (_rollbackIndex >= versions.length) {
      _rollbackIndex = 0;
    }
  }

  void _cycleRollback(int direction) {
    if (_rollbackVersions.isEmpty) {
      return;
    }
    final int next =
        (_rollbackIndex + direction + _rollbackVersions.length) % _rollbackVersions.length;
    setState(() => _rollbackIndex = next);
  }

  AppStore get _store => AppStore.instance;

  void _apply(PlaybackPrefs prefs) {
    _store.updatePrefs(prefs);
    setState(() {});
  }

  void _cycleQuality(int direction) {
    const List<QualityPref> values = QualityPref.values;
    final int index = values.indexOf(_store.prefs.quality);
    final int next = (index + direction + values.length) % values.length;
    _apply(_store.prefs.copyWith(quality: values[next]));
  }

  void _cyclePassthrough(int direction) {
    const List<PassthroughPref> values = PassthroughPref.values;
    final int index = values.indexOf(_store.prefs.passthrough);
    final int next = (index + direction + values.length) % values.length;
    _apply(_store.prefs.copyWith(passthrough: values[next]));
  }

  void _cycleProxy() {
    const List<String> modes = <String>['none', 'system', 'custom'];
    final int index = modes.indexOf(_store.prefs.networkProxyMode);
    final String next = modes[(index + 1) % modes.length];
    // updatePrefs pushes the choice into NetProxy, which both HTTP clients
    // consult — no separate apply step to forget.
    _apply(_store.prefs.copyWith(networkProxyMode: next));
  }

  Future<void> _editProxyAddress() async {
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _ProxyInputDialog(
        initial: _store.prefs.networkProxyAddress,
      ),
    );
    if (value == null) {
      return;
    }
    _apply(_store.prefs.copyWith(networkProxyAddress: value.trim()));
  }

  static String _channelLabel(UpdateChannel channel) => switch (channel) {
        UpdateChannel.stable => '正式版Stable',
        UpdateChannel.beta => '测试版Beta',
        UpdateChannel.dev => '开发者测试版Dev',
      };

  /// The key editor is a route: one owner for the text-input/focus flags, and
  /// closing it always restores whichever row opened it.
  Future<void> _openTmdbDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x88000000),
      builder: (BuildContext context) => _TmdbKeyDialog(
        initial: _store.tmdbKey,
        onSave: (String key) => unawaited(_store.setTmdbKey(key)),
      ),
    );
  }

  static String _maskKey(String key) {
    if (key.length <= 8) {
      return '••••';
    }
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  /// One prominent card for the metadata service. The whole card is the focus
  /// target — a nested PsButton would add a second, overlapping D-pad stop —
  /// and the pill on the right only mirrors what selecting the card does.
  Widget _metadataCard() {
    final String key = _store.tmdbKey;
    final bool configured = key.isNotEmpty;
    final String kind = key.startsWith('eyJ') ? 'v4 Bearer' : 'v3';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        radius: 16,
        onSelect: _openTmdbDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: PsColor.text.withValues(alpha: configured ? 0.07 : 0.045),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: PsColor.text.withValues(alpha: configured ? 0.18 : 0.07),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.movie_filter_rounded,
                size: 34,
                color: configured ? PsColor.text : PsColor.textFaint,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      S.tmdbApiKey,
                      style: PsType.label.copyWith(fontSize: 24, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      configured
                          ? '${S.tmdbConfigured} · $kind · ${_maskKey(key)}'
                          : S.tmdbNotConfigured,
                      style: PsType.micro.copyWith(
                        fontSize: 15,
                        color: configured ? PsColor.textDim : PsColor.textFaint,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      S.tmdbGuide,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PsType.micro.copyWith(fontSize: 14, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: PsColor.text.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(PsRadius.pill),
                  border: Border.all(color: PsColor.text.withValues(alpha: 0.18), width: 2),
                ),
                child: Text(
                  configured ? S.tmdbModify : S.tmdbSetUp,
                  style: PsType.meta.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One row, two stages: first press checks the channel, the second installs
  /// what was found (or reports why it can't). Rollback candidates surface
  /// through the row below.
  Future<void> _checkOrInstall() async {
    // Updating from a snapshot would unzip into `<snapshot>/updates/...` and
    // create yet another portable build. Refuse, and say which exe to launch.
    if (_updater.isSnapshotLaunch) {
      final String root = UpdateService.snapshotRoot() ?? AppPaths.installDir;
      setState(() {
        _updateStatus = '当前从更新备份目录启动，已停用应用内更新。'
            '请改从 $root 里的 xnx_player.exe 启动。';
      });
      return;
    }
    if (_pending != null) {
      final UpdateCandidate candidate = _pending!;
      // An installed copy must not be replaced by loose files: that leaves the
      // uninstall entry and shortcuts pointing at a version that is gone. Dev
      // nightlies ship no setup, so an installed copy simply cannot take them.
      if (_updater.installKind == InstallKind.installed &&
          !candidate.hasInstaller) {
        NoticeCenter.instance.publish(
          'update-check',
          '${candidate.version} 未提供安装包',
          body: '当前是安装版，只能通过安装包更新；请改用正式版或 beta 通道。',
          kind: NoticeKind.warning,
        );
        setState(() {
          _updateStatus = '该版本未提供安装包，安装版无法更新';
          _pending = null;
        });
        return;
      }
      // Exiting and restarting the app is not something to do silently: confirm
      // first, and on a portable layout ask whether the config survives.
      final _UpdateOptions? options = await showDialog<_UpdateOptions>(
        context: context,
        builder: (BuildContext context) => _UpdateConfirmDialog(
          version: candidate.version,
          portable: _updater.isPortable,
          installed: _updater.installKind == InstallKind.installed,
          hasInstaller: candidate.hasInstaller,
          dataDir: AppPaths.dataDir,
        ),
      );
      if (options == null || !mounted) {
        return;
      }
      setState(() {
        _pending = null;
        _downloadProgress = 0;
        _updateStatus = '正在下载 ${candidate.version}…';
      });
      // A download is the canonical live activity: one row that fills up,
      // visible from the top bar without opening settings.
      NoticeCenter.instance.activity('update-download', '正在下载 ${candidate.version}');
      void onProgress(int received, int total) {
        if (!mounted) {
          return;
        }
        final double fraction = total > 0 ? received / total : 0;
        NoticeCenter.instance.activity(
          'update-download',
          '正在下载 ${candidate.version}',
          progress: fraction,
          body: total > 0
              ? '${_megabytes(received)} / ${_megabytes(total)}'
              : _megabytes(received),
        );
        // The sink reports every chunk; repaint at 2 % steps instead.
        if (received != total && fraction - _downloadProgress < 0.02) {
          return;
        }
        _downloadProgress = fraction;
        setState(() {
          _updateStatus = total > 0
              ? '正在下载 ${candidate.version} '
                  '${(fraction * 100).round()}%'
                  '（${_megabytes(received)} / ${_megabytes(total)}）'
              : '正在下载 ${candidate.version}（${_megabytes(received)}）';
        });
      }

      try {
        if (options.useInstaller) {
          // Installed copies (and a portable copy that opted in) update
          // through the setup program: it is what keeps the uninstall entry
          // and shortcuts correct, and its wizard confirms the data folder.
          final String setup =
              await _updater.prepareInstaller(candidate, onProgress: onProgress);
          if (!mounted) {
            return;
          }
          NoticeCenter.instance.finish(
            'update-download',
            title: '正在启动安装程序 ${candidate.version}',
            body: '按向导完成安装，现有数据目录会被沿用',
          );
          setState(() => _updateStatus = '正在启动安装程序…');
          await _updater.applyInstaller(setup);
          return;
        }
        final String payload =
            await _updater.prepareInstall(candidate, onProgress: onProgress);
        if (!mounted) {
          return;
        }
        NoticeCenter.instance.finish(
          'update-download',
          title: '正在安装 ${candidate.version}',
          body: '程序即将关闭并重新启动',
        );
        setState(() => _updateStatus = '正在安装，程序即将重启…');
        await _updater.apply(payload, keepUserData: options.keepData);
      } on Object catch (error) {
        NoticeCenter.instance.finish(
          'update-download',
          title: '更新失败',
          body: '$error',
          kind: NoticeKind.error,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _updateStatus = '安装失败：$error';
          _downloadProgress = 0;
        });
      }
      return;
    }
    setState(() {
      _updateStatus = '正在检查 ${_channelLabel(_channel)}…';
    });
    try {
      final UpdateCandidate? candidate = await _updater.fetchLatest(_channel);
      if (candidate == null || candidate.assetUrl.isEmpty) {
        NoticeCenter.instance.publish(
          'update-check',
          '暂无可用构建',
          body: _channelLabel(_channel),
          kind: NoticeKind.warning,
        );
        setState(() {
          _updateStatus = '${_channelLabel(_channel)}：暂无可用构建';
        });
        return;
      }
      // 同版本且同通道类型不重复安装；正式版/beta 与 dev 之间允许换轨。
      if (!candidate.isPrerelease &&
          !isInstallable(candidate, S.appVersion) &&
          _channel == UpdateChannel.stable) {
        NoticeCenter.instance.publish(
          'update-check',
          '已是最新：${candidate.version}',
          kind: NoticeKind.success,
        );
        setState(() {
          _updateStatus = '已是最新：${candidate.version}';
        });
        return;
      }
      NoticeCenter.instance.publish(
        'update-check',
        '发现新版本 ${candidate.version}',
        body: '${_channelLabel(_channel)} · 再按「安装」开始下载',
        kind: NoticeKind.info,
      );
      setState(() {
        _updateStatus = '${_channelLabel(_channel)}最新：${candidate.version}，再按一次安装';
        _pending = candidate;
      });
    } on Object catch (error) {
      NoticeCenter.instance.publish(
        'update-check',
        '检查更新失败',
        body: '$error',
        kind: NoticeKind.error,
      );
      setState(() {
        _updateStatus = '检查失败：$error';
      });
    }
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Future<void> _rollBackTo(String version) async {
    if (_updater.isSnapshotLaunch) {
      setState(() {
        _updateStatus = '当前从更新备份目录启动，无法回退；请从主目录启动。';
      });
      return;
    }
    final String target = _updater.installedVersions().firstWhere(
          (String v) => v == version,
          orElse: () => '',
        );
    if (target.isEmpty) {
      return;
    }
    // A rollback exits and restarts too, so it deserves the same confirmation.
    final _UpdateOptions? options = await showDialog<_UpdateOptions>(
      context: context,
      builder: (BuildContext context) => _UpdateConfirmDialog(
        version: target,
        portable: _updater.isPortable,
        installed: false,
        hasInstaller: false,
        dataDir: AppPaths.dataDir,
        rollback: true,
      ),
    );
    if (options == null || !mounted) {
      return;
    }
    setState(() {
      _updateStatus = '正在回退到 $version…程序即将重启';
    });
    try {
      final String payload = await _updater.prepareInstalled(target);
      await _updater.apply(payload, keepUserData: options.keepData);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _updateStatus = '回退失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackPrefs prefs = _store.prefs;
    // TvScale already scales the whole stage; these are the same measurements
    // expressed in today's design-space size, so a wider/taller window gives
    // the columns more room instead of leaving them at fixed pixel widths.
    final double designW = TvScale.widthOf(context);
    final double designH = TvScale.heightOf(context);
    final double headerTop = designH * (110 / TvScale.designHeight);
    final double bodyTop = designH * (226 / TvScale.designHeight);
    final double bodyHeight = designH - bodyTop - designH * (70 / TvScale.designHeight);
    final double leftWidth = designW * (1180 / TvScale.designWidth);
    final double cardTop = designH * (236 / TvScale.designHeight);
    final double cardWidth = designW * (520 / TvScale.designWidth);
    return MotionBuilder(
      builder: (BuildContext context, double dt) {
        final MotionClock clock = MotionScope.of(context);
        if (clock.time != _last) {
          _last = clock.time;
          _age += clock.scaled(dt);
        }
        final double entrance = (_age / 0.45).clamp(0.0, 1.0).toDouble();

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned(
              left: PsSpace.safeX,
              top: headerTop + 14 * (1 - entrance),
              child: Opacity(
                opacity: entrance,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(S.tabSettings, style: PsType.page),
                    const SizedBox(height: 8),
                    Text(
                      '播放内核 mpv · gpu-next / D3D11',
                      style: PsType.micro.copyWith(fontSize: 16, letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: PsSpace.safeX,
              top: bodyTop,
              width: leftWidth,
              height: bodyHeight,
              child: Opacity(
                opacity: entrance,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 80, right: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _section(S.settingsMetadata),
                      _metadataCard(),
                      _section(S.settingsPlayback),
                      _Row(
                        label: S.quality,
                        hint: S.qualityHint,
                        value: prefs.qualityLabel,
                        onAdjust: _cycleQuality,
                        onSelect: () => _cycleQuality(1),
                      ),
                      _Row(
                        label: S.passthrough,
                        hint: S.passthroughHint,
                        value: prefs.passthroughLabel,
                        onAdjust: _cyclePassthrough,
                        onSelect: () => _cyclePassthrough(1),
                      ),
                      _Row(
                        label: S.volume,
                        hint: '按左右键调整，范围 0–130',
                        value: '${prefs.volume}',
                        onAdjust: (int direction) {
                          final int next = (prefs.volume + direction * 5).clamp(0, 130).toInt();
                          _apply(prefs.copyWith(volume: next));
                        },
                        bar: prefs.volume / 130,
                      ),
                      _section(S.settingsPicture),
                      _Row(
                        label: S.hdrPassthrough,
                        hint: S.hdrHint,
                        toggle: prefs.hdrPassthrough,
                        onSelect: () => _apply(prefs.copyWith(hdrPassthrough: !prefs.hdrPassthrough)),
                      ),
                      _Row(
                        label: S.smoothMotion,
                        hint: S.smoothMotionHint,
                        toggle: prefs.smoothMotion,
                        onSelect: () => _apply(prefs.copyWith(smoothMotion: !prefs.smoothMotion)),
                      ),
                      _Row(
                        label: S.deband,
                        hint: S.debandHint,
                        toggle: prefs.deband,
                        onSelect: () => _apply(prefs.copyWith(deband: !prefs.deband)),
                      ),
                      _section(S.settingsAudio),
                      _Row(
                        label: S.subtitleSize,
                        hint: '字幕渲染字号，42 为默认',
                        value: '${prefs.subtitleSize}',
                        onAdjust: (int direction) {
                          final int next =
                              (prefs.subtitleSize + direction * 2).clamp(30, 64).toInt();
                          _apply(prefs.copyWith(subtitleSize: next));
                        },
                        bar: (prefs.subtitleSize - 30) / 34,
                      ),
                      _section(S.settingsSystem),
                      _Row(
                        label: S.hardwareDecoding,
                        hint: S.hardwareHint,
                        toggle: prefs.hardwareDecoding,
                        onSelect: () =>
                            _apply(prefs.copyWith(hardwareDecoding: !prefs.hardwareDecoding)),
                      ),
                      _Row(
                        label: S.reduceMotion,
                        hint: S.reduceMotionHint,
                        toggle: prefs.reduceMotion,
                        onSelect: () => _apply(prefs.copyWith(reduceMotion: !prefs.reduceMotion)),
                      ),
                      _Row(
                        label: '界面音效',
                        hint: '移动、确认与返回的提示音，独立于视频音量',
                        toggle: prefs.soundEnabled,
                        onSelect: () =>
                            _apply(prefs.copyWith(soundEnabled: !prefs.soundEnabled)),
                      ),
                      if (prefs.soundEnabled)
                        _Row(
                          label: '音效音量',
                          hint: '${prefs.soundVolume}%',
                          value: '${prefs.soundVolume}%',
                          onAdjust: (int step) => _apply(
                            prefs.copyWith(
                              soundVolume: (prefs.soundVolume + step * 5).clamp(0, 100),
                            ),
                          ),
                          onSelect: null,
                        ),
                      _Row(
                        label: S.skipIntro,
                        hint: '片头标记、章节名与旁挂 .edl / comskip 里的片段自动跳过',
                        toggle: prefs.skipIntro,
                        onSelect: () => _apply(prefs.copyWith(skipIntro: !prefs.skipIntro)),
                      ),
                      _Row(
                        label: '进入播放时全屏',
                        hint: '关闭后以当前窗口播放，播放中可按 F11 切换',
                        toggle: prefs.startFullscreen,
                        onSelect: () =>
                            _apply(prefs.copyWith(startFullscreen: !prefs.startFullscreen)),
                      ),
                      _section('软件更新'),
                      _DropdownRow(
                        label: '更新通道',
                        hint: '当前版本 ${S.appVersion}\n'
                            '正式版Stable = main 正式 Release（便携版 zip + 安装包）· '
                            '测试版Beta = beta 预发布（便携版 zip + 安装包）· '
                            '开发者测试版Dev = beta 分支每次构建发布的 nightly 预发布（便携版 zip，无需 token）',
                        options: const <String>[
                          '正式版Stable',
                          '测试版Beta',
                          '开发者测试版Dev',
                        ],
                        selectedIndex: _channel.index,
                        onPick: (int index) {
                          setState(() {
                            _channel = UpdateChannel.values[index];
                            _pending = null;
                            _updateStatus = '${_channelLabel(_channel)}：请重新检查更新';
                          });
                        },
                      ),
                      _Row(
                        label: '网络代理',
                        hint: switch (prefs.networkProxyMode) {
                          'none' => '媒体库、TMDB 与更新下载全部直连',
                          'system' => '读取 Windows 系统代理设置；未配置时为直连',
                          'custom' => prefs.networkProxyAddress.isEmpty
                              ? '请再点一次设置代理地址，如 127.0.0.1:7890'
                              : '自定义代理：${prefs.networkProxyAddress}',
                          _ => '',
                        },
                        value: switch (prefs.networkProxyMode) {
                          'none' => '无代理',
                          'system' => '系统代理',
                          'custom' => '自定义',
                          _ => '系统代理',
                        },
                        onSelect: _cycleProxy,
                      ),
                      if (prefs.networkProxyMode == 'custom')
                        _Row(
                          label: '代理地址',
                          hint: '格式 host:port，例如 127.0.0.1:7890',
                          value: prefs.networkProxyAddress.isEmpty
                              ? '未设置'
                              : prefs.networkProxyAddress,
                          onSelect: () => unawaited(_editProxyAddress()),
                        ),
                      _Row(
                        label: _pending == null ? '检查更新' : '安装 ${_pending!.version}',
                        hint: _updater.isSnapshotLaunch
                            ? '当前从更新备份目录启动，更新已停用；'
                                '请改从主目录的 xnx_player.exe 启动'
                            : _updateStatus,
                        value: _pending == null ? null : '待安装',
                        onSelect: () => unawaited(_checkOrInstall()),
                      ),
                      if (_rollbackVersions.isNotEmpty)
                        _Row(
                          label: '版本回退',
                          hint: '回退到本机已保留的旧版本，用户配置不受影响',
                          value: _rollbackVersions[_rollbackIndex],
                          onAdjust: _cycleRollback,
                          onSelect: () => unawaited(
                            _rollBackTo(_rollbackVersions[_rollbackIndex]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: PsSpace.safeX,
              top: cardTop,
              width: cardWidth,
              child: Opacity(opacity: entrance, child: _KernelCard(prefs: prefs)),
            ),
          ],
        );
      },
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12, left: 4),
      child: Text(
        title,
        style: PsType.micro.copyWith(fontSize: 15, letterSpacing: 2.6, color: PsColor.textFaint),
      ),
    );
  }
}

/// A settings row whose value is picked from a small confirm card. The
/// inline expansion made the whole section jump every time it opened; the
/// card floats over everything instead, shows the three channels at once,
/// and closes on pick or on tap-outside.
class _DropdownRow extends StatefulWidget {
  const _DropdownRow({
    required this.label,
    required this.hint,
    required this.options,
    required this.selectedIndex,
    required this.onPick,
  });

  final String label;
  final String hint;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onPick;

  @override
  State<_DropdownRow> createState() => _DropdownRowState();
}

class _DropdownRowState extends State<_DropdownRow> {
  Future<void> _openPicker() async {
    final int? picked = await showDialog<int>(
      context: context,
      barrierColor: const Color(0x88000000),
      builder: (BuildContext context) => _ChannelPicker(
        options: widget.options,
        selectedIndex: widget.selectedIndex,
      ),
    );
    if (picked != null && picked != widget.selectedIndex) {
      widget.onPick(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TvFocusable(
            radius: 16,
            onSelect: _openPicker,
            child: Container(
              height: 96,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              decoration: BoxDecoration(
                color: PsColor.text.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: PsColor.text.withValues(alpha: 0.07)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.label,
                          style: PsType.label.copyWith(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // The hint carries two lines now: the running version,
                        // then what each channel means.
                        Text(
                          widget.hint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PsType.micro.copyWith(
                            fontSize: 15,
                            height: 1.35,
                            color: PsColor.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Text(
                    widget.options[widget.selectedIndex],
                    style: PsType.label.copyWith(
                      fontSize: 22,
                      color: PsColor.text.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 26,
                    color: PsColor.text.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
/// The floating confirm card: one column of options, the picked one ringed.
class _ChannelPicker extends StatelessWidget {
  const _ChannelPicker({required this.options, required this.selectedIndex});

  final List<String> options;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: const Color(0xEE141821),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 460,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: PsColor.text.withValues(alpha: 0.16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < options.length; i++)
                TvFocusable(
                  radius: 12,
                  autofocus: i == selectedIndex,
                  onSelect: () => Navigator.of(context).pop(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          i == selectedIndex
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 20,
                          color: i == selectedIndex
                              ? PsColor.accent
                              : PsColor.text.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          options[i],
                          style: PsType.label.copyWith(
                            fontSize: 21,
                            color: PsColor.text.withValues(
                              alpha: i == selectedIndex ? 1 : 0.74,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.hint,
    this.value,
    this.toggle,
    this.bar,
    this.onSelect,
    this.onAdjust,
  });

  final String label;
  final String hint;
  final String? value;
  final bool? toggle;
  final double? bar;
  final VoidCallback? onSelect;
  final ValueChanged<int>? onAdjust;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        radius: 16,
        onSelect: onSelect,
        onAdjust: onAdjust,
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: PsColor.text.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PsColor.text.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: PsType.label.copyWith(fontSize: 24, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PsType.micro.copyWith(fontSize: 15, color: PsColor.textFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              if (toggle != null) _Toggle(value: toggle!),
              if (value != null && toggle == null)
                Row(
                  children: <Widget>[
                    if (onAdjust != null)
                      Text('‹', style: PsType.page.copyWith(fontSize: 30, color: PsColor.textFaint)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 132,
                      child: Text(
                        value!,
                        textAlign: TextAlign.center,
                        style: PsType.meta.copyWith(
                          color: PsColor.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (onAdjust != null)
                      Text('›', style: PsType.page.copyWith(fontSize: 30, color: PsColor.textFaint)),
                  ],
                ),
              if (bar != null) ...<Widget>[
                const SizedBox(width: 28),
                SizedBox(
                  width: 300,
                  height: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ColoredBox(color: PsColor.text.withValues(alpha: 0.14)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: bar!.clamp(0.0, 1.0).toDouble(),
                          child: const ColoredBox(color: PsColor.text),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: PsMotion.fast,
      curve: PsMotion.curve,
      width: 78,
      height: 42,
      padding: const EdgeInsets.all(4),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PsRadius.pill),
        color: value ? PsColor.text.withValues(alpha: 0.26) : PsColor.text.withValues(alpha: 0.08),
        border: Border.all(color: PsColor.text.withValues(alpha: value ? 0.5 : 0.16), width: 1.5),
      ),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? PsColor.text : PsColor.text.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _KernelCard extends StatelessWidget {
  const _KernelCard({required this.prefs});

  final PlaybackPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: PsColor.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PsColor.text.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '当前输出',
            style: PsType.micro.copyWith(fontSize: 15, letterSpacing: 2.4),
          ),
          const SizedBox(height: 18),
          Text('gpu-next', style: PsType.stat.copyWith(fontSize: 32)),
          const SizedBox(height: 4),
          Text(
            prefs.hardwareDecoding ? 'D3D11 · 硬件解码' : 'D3D11 · 软件解码',
            style: PsType.meta.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 22),
          const Divider(color: PsColor.hairline, height: 1),
          const SizedBox(height: 22),
          _kv('画质', prefs.qualityLabel),
          _kv('HDR', prefs.hdrPassthrough ? '直通' : '色调映射'),
          _kv('音频', prefs.passthroughLabel),
          _kv('运动', prefs.smoothMotion ? '插帧平滑' : '原始帧率'),
          const SizedBox(height: 18),
          Text(
            '设置会立即写入 state.json，并在下一次起播时生效。',
            style: PsType.micro.copyWith(fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(key, style: PsType.micro.copyWith(fontSize: 16)),
          Text(value, style: PsType.label.copyWith(fontSize: 18)),
        ],
      ),
    );
  }
}

/// Modal key editor. While it is open a text field owns the keyboard, so the
/// router is told to forward everything except Back to the caret — the same
/// contract the add-source sheet uses.
/// What the install confirmation decided. A null dialog result means cancel.
class _UpdateOptions {
  const _UpdateOptions({required this.keepData, required this.useInstaller});

  final bool keepData;

  /// Route the update through the setup program instead of unzipping in place.
  /// Forced on for an installed copy; optional for a portable one.
  final bool useInstaller;
}

/// "Install update X" — the step that used to be a silent exit and restart.
class _UpdateConfirmDialog extends StatefulWidget {
  const _UpdateConfirmDialog({
    required this.version,
    required this.portable,
    required this.installed,
    required this.hasInstaller,
    required this.dataDir,
    this.rollback = false,
  });

  /// The version being installed (or rolled back to).
  final String version;

  /// True when the data folder lives inside the install folder: the only
  /// layout the in-place swap can damage, and the only one worth asking about.
  final bool portable;

  /// True when this copy is managed by the setup program. Such a copy must
  /// update through it, or the uninstall entry and shortcuts go stale.
  final bool installed;

  /// Whether the candidate actually ships a setup exe.
  final bool hasInstaller;
  final String dataDir;

  /// A rollback swaps an already-extracted local build: there is no download
  /// and no data decision, so the dialog drops both.
  final bool rollback;

  @override
  State<_UpdateConfirmDialog> createState() => _UpdateConfirmDialogState();
}

class _UpdateConfirmDialogState extends State<_UpdateConfirmDialog> {
  bool _keepData = true;
  late bool _useInstaller = widget.installed;
  InputSubscription? _inputSub;

  @override
  void initState() {
    super.initState();
    _inputSub = InputRouter.instance.subscribe(_onIntent, name: 'update-confirm');
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    super.dispose();
  }

  bool _onIntent(InputIntent intent) {
    if (intent.action != InputAction.back) {
      return false;
    }
    Navigator.of(context).pop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: const Color(0xEE141821),
        borderRadius: BorderRadius.circular(PsRadius.sheet),
        child: Container(
          width: 820,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PsRadius.sheet),
            border: Border.all(color: PsColor.text.withValues(alpha: 0.16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('安装更新 ${widget.version}',
                  style: PsType.page.copyWith(fontSize: 36)),
              const SizedBox(height: 12),
              Text(
                '程序会立即关闭，新版本覆盖安装目录后自动重新启动。',
                style: PsType.body.copyWith(
                  fontSize: 18,
                  height: 1.6,
                  color: PsColor.text.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 22),
              if (widget.rollback)
                _UpdateNote('将用本机保留的 ${widget.version} 覆盖程序文件。'
                    '用户配置与数据目录不受影响。')
              else if (widget.installed)
                const _UpdateNote('将通过安装程序更新：程序关闭后由向导接管，'
                    '完成安装后自动重新启动。当前数据目录会被沿用。')
              else if (_useInstaller)
                _UpdateNote('将通过安装程序更新，并把便携版升级为安装版：'
                    '会注册卸载项与开始菜单快捷方式，数据目录保持 ${widget.dataDir}。')
              else if (widget.portable)
                _UpdateToggle(
                  checked: _keepData,
                  title: '保留用户数据',
                  body: '便携版的数据在程序目录内：\n${widget.dataDir}\n'
                      '取消勾选会删除配置（state.json），让新版本以全新状态启动。',
                  onTap: () => setState(() => _keepData = !_keepData),
                )
              else
                _UpdateNote('用户数据保存在 ${widget.dataDir}，更新不会改动它。'),
              if (!widget.rollback &&
                  !widget.installed &&
                  widget.hasInstaller) ...<Widget>[
                const SizedBox(height: 12),
                _UpdateToggle(
                  checked: _useInstaller,
                  title: '改用安装程序更新',
                  body: '把便携版切成安装版：注册卸载项与快捷方式，'
                      '数据目录不变。',
                  onTap: () => setState(() => _useInstaller = !_useInstaller),
                ),
              ],
              const SizedBox(height: 28),
              Row(
                children: <Widget>[
                  PsButton(
                    label: '取消',
                    onSelect: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  PsButton(
                    label: '开始更新',
                    primary: true,
                    onSelect: () => Navigator.of(context).pop(
                      _UpdateOptions(
                        keepData: _keepData,
                        useInstaller: _useInstaller,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grey line of explanation inside the update dialog.
class _UpdateNote extends StatelessWidget {
  const _UpdateNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: PsType.micro.copyWith(
        fontSize: 15,
        height: 1.55,
        color: PsColor.textFaint,
      ),
    );
  }
}

/// A checkable option row for the update dialog.
class _UpdateToggle extends StatelessWidget {
  const _UpdateToggle({
    required this.checked,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool checked;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: 12,
      onSelect: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: PsColor.text.withValues(alpha: 0.05),
          border: Border.all(
            color: checked
                ? PsColor.accent
                : PsColor.text.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  checked
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 22,
                  color: checked ? PsColor.accent : PsColor.textFaint,
                ),
                const SizedBox(width: 10),
                Text(title, style: PsType.body.copyWith(fontSize: 19)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: PsType.micro.copyWith(
                fontSize: 15,
                height: 1.55,
                color: PsColor.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Address for the "custom" proxy mode. Shared by every HTTP client.
class _ProxyInputDialog extends StatefulWidget {
  const _ProxyInputDialog({required this.initial});

  final String initial;

  @override
  State<_ProxyInputDialog> createState() => _ProxyInputDialogState();
}

class _ProxyInputDialogState extends State<_ProxyInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  InputSubscription? _inputSub;

  @override
  void initState() {
    super.initState();
    TextEntry.active.value = true;
    _inputSub =
        InputRouter.instance.subscribe(_onIntent, name: 'proxy-input');
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    TextEntry.active.value = false;
    _controller.dispose();
    super.dispose();
  }

  bool _onIntent(InputIntent intent) {
    if (intent.action != InputAction.back) {
      return false;
    }
    Navigator.of(context).pop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: const Color(0xEE141821),
        borderRadius: BorderRadius.circular(PsRadius.sheet),
        child: Container(
          width: 720,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PsRadius.sheet),
            border: Border.all(color: PsColor.text.withValues(alpha: 0.16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('自定义代理', style: PsType.page.copyWith(fontSize: 36)),
              const SizedBox(height: 10),
              Text(
                '格式 host:port，例如 127.0.0.1:7890。留空表示直连。',
                style: PsType.micro.copyWith(
                  fontSize: 16,
                  color: PsColor.textFaint,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                autofocus: true,
                cursorColor: PsColor.text,
                style: PsType.meta.copyWith(color: PsColor.text, fontSize: 24),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: PsColor.text.withValues(alpha: 0.06),
                  hintText: '127.0.0.1:7890',
                  hintStyle:
                      PsType.meta.copyWith(color: PsColor.textFaint, fontSize: 22),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: PsColor.text, width: 2),
                  ),
                ),
                onSubmitted: (String value) =>
                    Navigator.of(context).pop(value.trim()),
              ),
              const SizedBox(height: 28),
              Row(
                children: <Widget>[
                  PsButton(
                    label: '取消',
                    onSelect: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  PsButton(
                    label: '保存',
                    primary: true,
                    onSelect: () => Navigator.of(context).pop(_controller.text.trim()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TmdbKeyDialog extends StatefulWidget {
  const _TmdbKeyDialog({required this.initial, required this.onSave});

  final String initial;
  final ValueChanged<String> onSave;

  @override
  State<_TmdbKeyDialog> createState() => _TmdbKeyDialogState();
}

class _TmdbKeyDialogState extends State<_TmdbKeyDialog> {
  late final TextEditingController _key = TextEditingController(text: widget.initial);
  InputSubscription? _inputSub;
  String? _error;

  @override
  void initState() {
    super.initState();
    TextEntry.active.value = true;
    _inputSub = InputRouter.instance.subscribe(_onIntent, name: 'tmdb-key-dialog');
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    TextEntry.active.value = false;
    _key.dispose();
    super.dispose();
  }

  bool _onIntent(InputIntent intent) {
    if (intent.action != InputAction.back) {
      return false;
    }
    Navigator.of(context).pop();
    return true;
  }

  void _save() {
    final String value = _key.text.trim();
    if (value.isEmpty) {
      setState(() => _error = S.tmdbEmptyHint);
      return;
    }
    widget.onSave(value);
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onSave('');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: const Color(0xEE141821),
        borderRadius: BorderRadius.circular(PsRadius.sheet),
        child: Container(
          width: 900,
          padding: const EdgeInsets.all(44),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PsRadius.sheet),
            border: Border.all(color: PsColor.text.withValues(alpha: 0.16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(S.tmdbApiKey, style: PsType.page.copyWith(fontSize: 40)),
              const SizedBox(height: 10),
              Text(
                S.tmdbGuide,
                maxLines: 3,
                style: PsType.micro.copyWith(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _key,
                autofocus: true,
                cursorColor: PsColor.text,
                style: PsType.meta.copyWith(color: PsColor.text, fontSize: 24),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: PsColor.text.withValues(alpha: 0.06),
                  hintText: S.tmdbKeyHint,
                  hintStyle: PsType.meta.copyWith(color: PsColor.textFaint, fontSize: 22),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: PsColor.text, width: 2),
                  ),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_error!, style: PsType.label.copyWith(color: PsColor.danger)),
              ],
              const SizedBox(height: 28),
              Row(
                children: <Widget>[
                  PsButton(
                    label: S.tmdbSave,
                    icon: Icons.check_rounded,
                    primary: true,
                    width: 200,
                    onSelect: _save,
                  ),
                  const SizedBox(width: 16),
                  if (widget.initial.isNotEmpty)
                    PsButton(
                      label: S.tmdbClear,
                      icon: Icons.delete_outline_rounded,
                      width: 160,
                      onSelect: _clear,
                    ),
                  const SizedBox(width: 16),
                  PsButton(
                    label: S.tmdbCancel,
                    width: 160,
                    onSelect: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
