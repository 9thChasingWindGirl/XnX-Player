import '../../data/models/media_item.dart';

/// A horizontal shelf on the home screen.
class HomeRow {
  const HomeRow({
    required this.id,
    required this.title,
    required this.items,
    this.itemSize = 200,
  });

  final String id;
  final String title;
  final List<MediaItem> items;
  final double itemSize;
}

/// Placeholder library used until the source adapters land. Everything here is
/// driven by the same [MediaItem] model the real backends will produce, so the
/// UI code does not change when Emby / IPTV / WebDAV plug in.
abstract final class DemoLibrary {
  static const MediaItem hero = MediaItem(
    id: 'demo::hero',
    title: '星际拾荒者',
    subtitle: '第二季 · 第六集 · 沙海之下',
    overview: '一支靠拆解废弃空间站为生的队伍，在环带边缘捡到了一段不属于任何已知文明的坐标。',
    meta: '2026 · 4K HDR · 58 分钟',
    progress: 0.42,
    badge: '4K HDR',
    kind: MediaKind.episode,
  );

  static List<HomeRow> rows() {
    return <HomeRow>[
      const HomeRow(
        id: 'continue',
        title: '继续观看',
        items: <MediaItem>[
          MediaItem(
            id: 'demo::c1',
            title: '星际拾荒者',
            subtitle: 'S02E06 · 沙海之下',
            progress: 0.42,
            meta: '4K HDR',
            kind: MediaKind.episode,
            badge: 'HDR',
          ),
          MediaItem(
            id: 'demo::c2',
            title: '长夜将尽',
            subtitle: 'S01E03 · 第七次校准',
            progress: 0.71,
            meta: '1080p',
            kind: MediaKind.episode,
          ),
          MediaItem(
            id: 'demo::c3',
            title: '潮汐协议',
            progress: 0.18,
            meta: '杜比视界',
            badge: 'DV',
          ),
          MediaItem(
            id: 'demo::c4',
            title: '玻璃航线',
            subtitle: '第 12 集',
            progress: 0.88,
            kind: MediaKind.episode,
          ),
        ],
      ),
      const HomeRow(
        id: 'recent',
        title: '最近添加',
        items: <MediaItem>[
          MediaItem(id: 'demo::r1', title: '环形废墟', meta: '2026 · 131 分钟', badge: '4K'),
          MediaItem(id: 'demo::r2', title: '雨季测绘', meta: '2025 · 112 分钟'),
          MediaItem(id: 'demo::r3', title: '无声频段', meta: '2026 · 8 集', kind: MediaKind.series),
          MediaItem(id: 'demo::r4', title: '北纬零度', meta: '2024 · 97 分钟'),
          MediaItem(id: 'demo::r5', title: '第二次日落', meta: '2026 · 2 小时 8 分', badge: 'HDR'),
          MediaItem(id: 'demo::r6', title: '沙漏城市', meta: '2023 · 104 分钟'),
        ],
      ),
      const HomeRow(
        id: 'local',
        title: '本地媒体库',
        items: <MediaItem>[
          MediaItem(
            id: 'demo::l1',
            title: '演示片段 · 1080p',
            subtitle: '本地文件',
            meta: 'H.264 · AAC',
            path: 'demo',
          ),
          MediaItem(
            id: 'demo::l2',
            title: '选择文件播放',
            subtitle: '支持 mkv / mp4 / ts',
            meta: '打开文件',
            path: 'open',
            badge: 'F1',
          ),
        ],
      ),
    ];
  }
}
