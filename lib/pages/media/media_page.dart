import 'package:material_ui/material_ui.dart';

import '../../design/ps_tokens.dart';
import '../../ui/core/focus_zone.dart';
import '../../ui/core/tv_focusable.dart';

/// Media hub. v1 shows the six source slots the player will support; the
/// adapters land in the next milestones behind the same cards.
class MediaPage extends StatelessWidget {
  const MediaPage({super.key});

  static const List<_SourceSlot> _slots = <_SourceSlot>[
    _SourceSlot('emby', Icons.dns_outlined, 'Emby / Jellyfin', '海报墙 · 续播 · 进度回写'),
    _SourceSlot('iptv', Icons.live_tv_outlined, 'IPTV 直播', 'm3u 订阅 · EPG 节目单'),
    _SourceSlot('local', Icons.folder_outlined, '本地文件夹', '扫描目录 · 记住进度'),
    _SourceSlot('openlist', Icons.cloud_outlined, 'OpenList', 'AList 网盘 · 直链'),
    _SourceSlot('webdav', Icons.storage_outlined, 'CloudDrive2', 'WebDAV · 远程挂载'),
    _SourceSlot('url', Icons.link_rounded, '直链播放', 'http / https / rtmp'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF11161F), PsColor.bgDeep],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          left: PsSpace.safeX,
          right: PsSpace.safeX,
          top: PsSpace.topBarHeight + 40,
          bottom: 160,
        ),
        children: <Widget>[
          const Text('媒体来源', style: PsType.page),
          const SizedBox(height: PsSpace.xs),
          const Text('接入服务器与网盘，统一成同一个媒体库。', style: PsType.body),
          const SizedBox(height: PsSpace.xl),
          FocusZone(
            id: 'sources',
            child: Wrap(
              spacing: PsSpace.md,
              runSpacing: PsSpace.md,
              children: <Widget>[
                for (final _SourceSlot slot in _slots) _SourceCard(slot: slot),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceSlot {
  const _SourceSlot(this.id, this.icon, this.title, this.subtitle);

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({required this.slot});

  final _SourceSlot slot;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: PsRadius.cardLarge,
      focusScale: 1.05,
      debugLabel: 'source:${widget.slot.id}',
      onFocused: (bool focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: PsMotion.base,
        curve: PsMotion.curve,
        width: 520,
        height: 168,
        padding: const EdgeInsets.all(PsSpace.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PsRadius.cardLarge),
          color: _focused ? PsColor.surfaceHigh : PsColor.surface,
          border: Border.all(color: PsColor.hairline),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x1AFFFFFF),
                border: Border.all(color: PsColor.hairline),
              ),
              child: Icon(widget.slot.icon, size: 30, color: PsColor.text),
            ),
            const SizedBox(width: PsSpace.lg),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.slot.title, style: PsType.card),
                  const SizedBox(height: 6),
                  Text(widget.slot.subtitle, style: PsType.micro),
                  const SizedBox(height: 10),
                  Text(
                    '即将接入',
                    style: PsType.micro.copyWith(fontSize: 14, color: PsColor.textFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
