import 'package:material_ui/material_ui.dart';

import '../core/strings.dart';
import '../data/models/media_item.dart';
import '../data/prefs.dart';
import '../data/sources/media_source.dart';
import '../design/ps_media.dart';
import '../design/ps_tokens.dart';
import '../pages/home/home_tile.dart';
import '../playback/mpv/hw_profile.dart';
import '../ui/core/focus_zone.dart';
import '../ui/core/tv_focusable.dart';
import '../ui/widgets/ps_button.dart';

/// Inline panels for the Control Center dock.
///
/// The console reference opens a small panel above the icon row instead of
/// navigating away, and that is the whole point of a control center: adjust
/// something and get back to what was on screen. Every panel here writes to the
/// same state the settings page writes to, so the two can never disagree.

// ---------------------------------------------------------------- frame

class CcPanelFrame extends StatelessWidget {
  const CcPanelFrame({
    super.key,
    required this.title,
    required this.hint,
    required this.child,
    this.count,
  });

  final String title;
  final String hint;
  final Widget child;

  /// How many things the panel is about. A `Panel` has a `header_slot` of 120
  /// for exactly this (`PanelStyle::header_slot`, `surface.hpp:105`), and a
  /// `SectionHeader` carries the same figure as a 28 px badge at 17 px type
  /// (`SectionHeaderStyle::count_height/count_size`, `surface.hpp:139-141`).
  /// A negative count hides it, as upstream's does.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final int? shown = count != null && count! >= 0 ? count : null;
    // A Panel with `surface: false` (`surface.hpp:113-115`): the surface is
    // already there — the dock's glass — and all this adds is the padding, the
    // title bar and the rule under it. It used to draw its own 95 % opaque
    // card on top of that glass, which is why the panel read as a second
    // object stuck onto the dock instead of a region of it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PsPanel.paddingX,
        PsPanel.paddingY,
        PsPanel.paddingX,
        PsPanel.paddingY,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(title, style: PsType.section.copyWith(fontSize: PsPanel.titleSize)),
              if (shown != null) ...<Widget>[
                const SizedBox(width: 12),
                _CountBadge(count: shown),
              ],
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  // `PanelStyle::subtitle_size` — 19, not a 15 px micro label.
                  style: PsType.label.copyWith(
                    fontSize: PsPanel.subtitleSize,
                    fontWeight: FontWeight.w400,
                    color: PsColor.textFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // `header_rule`: a hairline, not a shadow and not a gap. Drawn as a
          // box so the panel owes nothing to a Material ancestor.
          Container(height: 1, color: PsColor.hairline),
          const SizedBox(height: 14),
          // One zone for the whole panel: arrows move inside it, and the shell
          // can drop focus straight onto the first control with focusIn().
          Expanded(child: FocusZone(id: 'cc-panel', child: child)),
        ],
      ),
    );
  }
}

/// A count on a title bar. `BadgeFill::tinted` at `Status::neutral`: a plate of
/// the text colour at 12 %, the figure in full text. It never takes the focus —
/// it is a fact, not a control.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PsColor.text.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PsRadius.pill),
      ),
      child: Text(
        '$count',
        style: PsType.label.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------- rows

/// One adjustable / toggleable line. Compact on purpose: a panel is 420px tall
/// and a slider plus three switches have to fit without scrolling.
class CcPanelRow extends StatelessWidget {
  const CcPanelRow({
    super.key,
    required this.label,
    this.hint,
    this.value,
    this.toggle,
    this.bar,
    this.onSelect,
    this.onAdjust,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final String? value;
  final bool? toggle;
  final double? bar;
  final VoidCallback? onSelect;
  final ValueChanged<int>? onAdjust;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PsPanel.rowGap),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: TvFocusable(
          radius: 14,
          enabled: enabled,
          onSelect: onSelect,
          onAdjust: onAdjust,
          child: Container(
            height: PsPanel.rowHeight,
            // The kit insets a row by 26 (`ListViewStyle::padding`). The row
            // height is the one number we shorten — see `PsPanel.rowHeight`.
            padding: const EdgeInsets.symmetric(horizontal: PsPanel.rowInset),
            decoration: BoxDecoration(
              color: PsColor.text.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PsType.label.copyWith(fontSize: 21),
                      ),
                      if (hint != null)
                        Text(
                          hint!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PsType.micro.copyWith(fontSize: 14),
                        ),
                    ],
                  ),
                ),
                if (bar != null) ...<Widget>[
                  const SizedBox(width: 18),
                  _CcBar(value: bar!),
                ],
                if (value != null) ...<Widget>[
                  const SizedBox(width: 18),
                  Text(
                    value!,
                    style: PsType.meta.copyWith(
                      fontSize: 22,
                      color: PsColor.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (toggle != null) ...<Widget>[
                  const SizedBox(width: 18),
                  _CcToggle(value: toggle!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CcBar extends StatelessWidget {
  const _CcBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    // The same track a transport uses: 8 tall, a rounded end, the unfilled
    // part at 16 % (`PsScrubber.trackRest` / `trackAlphaRest`, from
    // `player.cpp:1028`). A level bar and a timeline are the same object seen
    // from two screens.
    return SizedBox(
      width: 220,
      height: PsControls.trackHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PsControls.trackHeight / 2),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: PsColor.text.withValues(alpha: 0.16)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0).toDouble(),
              child: const ColoredBox(color: PsColor.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _CcToggle extends StatelessWidget {
  const _CcToggle({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: PsMotion.fast,
      curve: PsMotion.curve,
      width: 62,
      height: 34,
      padding: const EdgeInsets.all(4),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PsRadius.pill),
        color: PsColor.text.withValues(alpha: value ? 0.28 : 0.08),
        border: Border.all(color: PsColor.text.withValues(alpha: value ? 0.52 : 0.16), width: 1.5),
      ),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? PsColor.text : PsColor.text.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _CcEmpty extends StatelessWidget {
  const _CcEmpty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    // `EmptyStateStyle` (`stat.hpp:113-125`): a 96 px icon, a 30 px title, a
    // 22 px body, 16 between them. A 420-tall panel cannot hold 96 plus three
    // lines, so the icon comes down to 44 and the type to 24/17 — the same
    // order and the same gaps, one step smaller. Recorded in §12.
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 44, color: PsColor.textFaint),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: PsType.card.copyWith(fontSize: 24)),
              const SizedBox(height: 6),
              Text(body, style: PsType.body.copyWith(fontSize: 17, color: PsColor.textFaint)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- sound

class CcSoundPanel extends StatelessWidget {
  const CcSoundPanel({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.hw,
  });

  final PlaybackPrefs prefs;
  final ValueChanged<PlaybackPrefs> onChanged;
  final HardwareProfile hw;

  @override
  Widget build(BuildContext context) {
    final String device = hw.audioDeviceName.isEmpty
        ? '尚未记录输出设备（起播后自动探测）'
        : hw.audioDeviceName;
    return CcPanelFrame(
      title: S.ccSound,
      hint: '左右键调整音量；改动立即保存，下一次起播生效',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CcPanelRow(
            label: S.volume,
            hint: '起播音量 · 0 – 130',
            value: '${prefs.volume}',
            bar: prefs.volume / 130,
            onAdjust: (int direction) => onChanged(
              prefs.copyWith(
                volume: (prefs.volume + direction * 5).clamp(0, 130).toInt(),
              ),
            ),
          ),
          CcPanelRow(
            label: S.passthrough,
            hint: '需要功放接受原始码流；普通声卡请保持关闭',
            value: prefs.passthroughLabel,
            onAdjust: (int direction) => onChanged(
              prefs.copyWith(
                passthrough: _cycle<PassthroughPref>(
                  PassthroughPref.values,
                  prefs.passthrough,
                  direction,
                ),
              ),
            ),
            onSelect: () => onChanged(
              prefs.copyWith(
                passthrough: _cycle<PassthroughPref>(
                  PassthroughPref.values,
                  prefs.passthrough,
                  1,
                ),
              ),
            ),
          ),
          _CcNote(text: '输出：$device'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- subtitles

class CcSubtitlePanel extends StatelessWidget {
  const CcSubtitlePanel({super.key, required this.prefs, required this.onChanged});

  final PlaybackPrefs prefs;
  final ValueChanged<PlaybackPrefs> onChanged;

  @override
  Widget build(BuildContext context) {
    return CcPanelFrame(
      title: S.ccSubtitle,
      hint: '字号用于外挂与内封字幕；播放中按 F6 打开字幕菜单',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CcPanelRow(
            label: S.subtitleSize,
            hint: '30 – 64，默认 42',
            value: '${prefs.subtitleSize}',
            bar: (prefs.subtitleSize - 30) / 34,
            onAdjust: (int direction) => onChanged(
              prefs.copyWith(
                subtitleSize: (prefs.subtitleSize + direction * 2).clamp(30, 64).toInt(),
              ),
            ),
          ),
          CcPanelRow(
            label: S.skipIntro,
            hint: '有片头标记时自动跳过',
            toggle: prefs.skipIntro,
            onSelect: () => onChanged(prefs.copyWith(skipIntro: !prefs.skipIntro)),
          ),
          const _CcNote(text: '字幕轨、延迟与样式在播放器的 F6 面板里调整。'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- picture

class CcPicturePanel extends StatelessWidget {
  const CcPicturePanel({super.key, required this.prefs, required this.onChanged});

  final PlaybackPrefs prefs;
  final ValueChanged<PlaybackPrefs> onChanged;

  @override
  Widget build(BuildContext context) {
    return CcPanelFrame(
      title: S.ccPicture,
      hint: '作用于下一次起播；播放中的临时调整请用 F10 / 更多菜单',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CcPanelRow(
            label: S.quality,
            hint: '缩放算法与 gpu-hq 档位',
            value: prefs.qualityLabel,
            onAdjust: (int direction) => onChanged(
              prefs.copyWith(
                quality: _cycle<QualityPref>(QualityPref.values, prefs.quality, direction),
              ),
            ),
            onSelect: () => onChanged(
              prefs.copyWith(
                quality: _cycle<QualityPref>(QualityPref.values, prefs.quality, 1),
              ),
            ),
          ),
          CcPanelRow(
            label: S.hdrPassthrough,
            hint: '检出 SDR 显示器时会自动降级',
            toggle: prefs.hdrPassthrough,
            onSelect: () => onChanged(
              prefs.copyWith(hdrPassthrough: !prefs.hdrPassthrough),
            ),
          ),
          CcPanelRow(
            label: S.smoothMotion,
            hint: '插帧补偿 24p 抖动，吃 GPU',
            toggle: prefs.smoothMotion,
            onSelect: () => onChanged(prefs.copyWith(smoothMotion: !prefs.smoothMotion)),
          ),
          CcPanelRow(
            label: S.deband,
            hint: '消除暗部渐变的色带',
            toggle: prefs.deband,
            onSelect: () => onChanged(prefs.copyWith(deband: !prefs.deband)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- recent

class CcRecentPanel extends StatelessWidget {
  const CcRecentPanel({super.key, required this.items, required this.onPlay});

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onPlay;

  @override
  Widget build(BuildContext context) {
    return CcPanelFrame(
      title: S.ccRecent,
      count: items.length,
      hint: items.isEmpty ? '看过的东西会出现在这里' : '继续上次的进度，选中即播',
      child: items.isEmpty
          ? const _CcEmpty(
              icon: Icons.history_rounded,
              title: '还没有播放记录',
              body: '播放任意影片后，这里会列出最近看过的内容',
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              // These cards fill the viewport height, so their 3 % growth goes
              // outside the list; letting it paint keeps the focus lift from
              // being shaved into a cropped rectangle.
              clipBehavior: Clip.none,
              itemCount: items.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: 14),
              itemBuilder: (BuildContext context, int index) {
                return _RecentCard(item: items[index], onPlay: onPlay);
              },
            ),
    );
  }
}

/// One "continue watching" tile.
///
/// This used to be a bespoke card that painted a gradient from the item's
/// palette and nothing else — so the panel showed coloured rectangles for
/// titles that had a perfectly good poster on the shelf behind it, and it read
/// as a different product than the rest of the app. It is now the same
/// [PosterCard] every shelf uses: poster, scrim, badge, watched bar, focus
/// states. The only local decision left is the 2:3 box, because this panel is
/// short and wide and a poster is what belongs in it.
class _RecentCard extends StatefulWidget {
  const _RecentCard({required this.item, required this.onPlay});

  final MediaItem item;
  final ValueChanged<MediaItem> onPlay;

  @override
  State<_RecentCard> createState() => _RecentCardState();
}

class _RecentCardState extends State<_RecentCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The panel body is the height budget; a poster takes 2:3 of it and is
        // clamped so a tall window cannot turn the row into three banners.
        final double height = constraints.maxHeight;
        final double width = (height * 2 / 3).clamp(148.0, 232.0).toDouble();
        return TvFocusable(
          radius: PsRadius.card,
          focusedRadius: PsRadius.cardFocused,
          highlightScale: PsCard.focusScale,
          pressScale: PsCard.pressScale,
          showShine: false,
          onSelect: () => widget.onPlay(widget.item),
          onFocused: (bool focused) => setState(() => _focused = focused),
          debugLabel: 'cc-recent:${widget.item.id}',
          child: PosterCard(
            item: widget.item,
            width: width,
            height: height,
            focused: _focused,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- notifications

class CcNotificationsPanel extends StatelessWidget {
  const CcNotificationsPanel({
    super.key,
    required this.errors,
    required this.loading,
    required this.sourceCount,
    required this.onRefresh,
    required this.onClear,
  });

  final List<String> errors;
  final bool loading;
  final int sourceCount;
  final VoidCallback onRefresh;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final String health = errors.isEmpty ? '运行正常' : '${errors.length} 条错误';
    final String status = loading ? '正在刷新媒体来源…' : '$sourceCount 个来源已连接 · $health';
    return CcPanelFrame(
      title: S.ccNotifications,
      count: errors.length,
      hint: status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: errors.isEmpty
                ? const _CcEmpty(
                    icon: Icons.check_circle_outline_rounded,
                    title: '没有需要处理的通知',
                    body: '来源连接失败、更新结果会在这里列出',
                  )
                : ListView.builder(
                    itemCount: errors.length,
                    itemBuilder: (BuildContext context, int index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 20,
                              color: PsColor.danger,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                errors[index],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: PsType.micro.copyWith(
                                  fontSize: 15,
                                  color: PsColor.textDim,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              PsButton(label: '刷新媒体库', height: 52, onSelect: onRefresh),
              const SizedBox(width: 12),
              PsButton(
                label: '清空通知',
                height: 52,
                enabled: errors.isNotEmpty,
                onSelect: onClear,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- sources

class CcSourcesPanel extends StatelessWidget {
  const CcSourcesPanel({
    super.key,
    required this.sources,
    required this.onRefresh,
    required this.onAdd,
  });

  final List<SourceConfig> sources;
  final VoidCallback onRefresh;
  final VoidCallback onAdd;

  static String _kindLabel(SourceKind kind) => switch (kind) {
    SourceKind.emby => 'Emby',
    SourceKind.jellyfin => 'Jellyfin',
    SourceKind.iptv => 'IPTV',
    SourceKind.openlist => 'OpenList',
    SourceKind.webdav => 'WebDAV',
    SourceKind.local => '本地',
    SourceKind.directUrl => '直链',
  };

  @override
  Widget build(BuildContext context) {
    return CcPanelFrame(
      title: S.ccSources,
      hint: sources.isEmpty ? '还没有接入任何来源' : '${sources.length} 个来源 · 在媒体库页可编辑',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: sources.isEmpty
                ? const _CcEmpty(
                    icon: Icons.cloud_off_outlined,
                    title: '没有来源',
                    body: 'Emby / Jellyfin、IPTV、OpenList、WebDAV 或本地文件夹',
                  )
                : ListView.builder(
                    itemCount: sources.length,
                    itemBuilder: (BuildContext context, int index) {
                      final SourceConfig config = sources[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: config.enabled
                                    ? PsColor.text
                                    : PsColor.text.withValues(alpha: 0.3),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                config.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PsType.label.copyWith(fontSize: 19),
                              ),
                            ),
                            Text(
                              _kindLabel(config.kind),
                              style: PsType.micro.copyWith(fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              PsButton(label: '刷新', height: 52, onSelect: onRefresh),
              const SizedBox(width: 12),
              PsButton(label: '添加来源', height: 52, primary: true, onSelect: onAdd),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- profile

class CcProfilePanel extends StatelessWidget {
  const CcProfilePanel({
    super.key,
    required this.version,
    required this.sources,
    required this.media,
    required this.favorites,
    required this.onOpenSettings,
  });

  final String version;
  final int sources;
  final int media;
  final int favorites;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return CcPanelFrame(
      title: S.ccProfile,
      hint: '本机档案 · 无账号，全部数据保存在本机 state.json',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _Stat(label: '版本', value: version)),
              Expanded(child: _Stat(label: '来源', value: '$sources')),
              Expanded(child: _Stat(label: '媒体', value: '$media')),
              Expanded(child: _Stat(label: '收藏', value: '$favorites')),
            ],
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerLeft,
            child: PsButton(
              label: '打开设置',
              icon: Icons.settings_rounded,
              height: 52,
              onSelect: onOpenSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // `StatTileStyle` (`stat.hpp:21-24`): a 20 px label over a 48 px figure.
    // Ours was 14 over 30 — the label was unreadable a metre from the screen.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: PsType.label.copyWith(
            fontSize: 18,
            color: PsColor.textFaint,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(value, style: PsType.stat),
      ],
    );
  }
}

// ---------------------------------------------------------------- power

class CcPowerPanel extends StatelessWidget {
  const CcPowerPanel({
    super.key,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onMinimize,
    required this.onQuit,
  });

  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onMinimize;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return CcPanelFrame(
      title: S.ccPower,
      hint: '窗口与退出；播放进度已实时保存',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: PsButton(
              label: fullscreen ? '退出全屏' : '进入全屏',
              icon: Icons.fullscreen_rounded,
              height: 56,
              onSelect: onToggleFullscreen,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: PsButton(
              label: '最小化窗口',
              icon: Icons.minimize_rounded,
              height: 56,
              onSelect: onMinimize,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: PsButton(
              label: '退出 XnX Player',
              icon: Icons.power_settings_new_rounded,
              height: 56,
              primary: true,
              onSelect: onQuit,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- helpers

class _CcNote extends StatelessWidget {
  const _CcNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(text, style: PsType.micro.copyWith(fontSize: 14)),
    );
  }
}

/// Steps through [values] with wrap-around, which is what left/right on a
/// cycled setting has to do.
T _cycle<T>(List<T> values, T current, int direction) {
  final int index = values.indexOf(current);
  if (index < 0) {
    return values.first;
  }
  return values[(index + direction + values.length) % values.length];
}
