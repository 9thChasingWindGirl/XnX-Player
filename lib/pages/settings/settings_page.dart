import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/prefs.dart';
import '../../data/store.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/motion_clock.dart';
import '../../ui/core/tv_focusable.dart';
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

  static String _channelLabel(UpdateChannel channel) => switch (channel) {
        UpdateChannel.stable => '正式版',
        UpdateChannel.beta => 'Beta',
        UpdateChannel.dev => 'Dev（未验证构建）',
      };

  Future<void> _cycleChannel(int direction) async {
    const List<UpdateChannel> values = UpdateChannel.values;
    final int index = values.indexOf(_channel);
    _channel = values[(index + direction + values.length) % values.length];
    _pending = null;
    setState(() {
      _updateStatus = '${_channelLabel(_channel)}：请重新检查更新';
    });
  }

  /// One row, two stages: first press checks the channel, the second installs
  /// what was found (or reports why it can't). Rollback candidates surface
  /// through the row below.
  Future<void> _checkOrInstall() async {
    if (_pending != null) {
      final UpdateCandidate candidate = _pending!;
      setState(() {
        _updateStatus = '正在下载并安装 ${candidate.version}…安装后会自动重启';
        _pending = null;
      });
      try {
        final String payload = await _updater.prepareInstall(candidate);
        await _updater.apply(payload);
      } on Object catch (error) {
        setState(() {
          _updateStatus = '安装失败：$error';
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
        setState(() {
          _updateStatus = '${_channelLabel(_channel)}：暂无可用构建';
        });
        return;
      }
      // 同版本且同通道类型不重复安装；正式版/beta 与 dev 之间允许换轨。
      if (!candidate.isPrerelease &&
          !isInstallable(candidate, S.appVersion) &&
          _channel == UpdateChannel.stable) {
        setState(() {
          _updateStatus = '已是最新：${candidate.version}';
        });
        return;
      }
      setState(() {
        _updateStatus = '${_channelLabel(_channel)}最新：${candidate.version}，再按一次安装';
        _pending = candidate;
      });
    } on Object catch (error) {
      setState(() {
        _updateStatus = '检查失败：$error';
      });
    }
  }

  Future<void> _rollBackTo(String version) async {
    final String target = _updater.installedVersions().firstWhere(
          (String v) => v == version,
          orElse: () => '',
        );
    if (target.isEmpty) {
      return;
    }
    setState(() {
      _updateStatus = '正在回退到 $version…完成后自动重启';
    });
    try {
      final String payload = await _updater.prepareInstalled(target);
      await _updater.apply(payload);
    } on Object catch (error) {
      setState(() {
        _updateStatus = '回退失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackPrefs prefs = _store.prefs;
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
              top: 110 + 14 * (1 - entrance),
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
              top: 226,
              width: 1180,
              height: 800,
              child: Opacity(
                opacity: entrance,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 80, right: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
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
                        label: S.skipIntro,
                        hint: '检测到片头标记时自动跳过',
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
                      _Row(
                        label: '更新通道',
                        hint: '当前版本 ${S.appVersion} · 正式版 / Beta（预留）/ Dev（beta 分支未验证构建）',
                        value: _channelLabel(_channel),
                        onAdjust: _cycleChannel,
                        onSelect: () => _cycleChannel(1),
                      ),
                      _Row(
                        label: _pending == null ? '检查更新' : '安装 ${_pending!.version}',
                        hint: _updateStatus,
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
              top: 236,
              width: 520,
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
