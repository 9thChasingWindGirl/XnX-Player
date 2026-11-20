import 'package:material_ui/material_ui.dart';

import '../core/strings.dart';

/// What activating a dock entry does.
///
/// This is deliberately a closed enum instead of "switch on the id in the
/// shell": the previous version routed by string id, and six of the eleven
/// entries quietly fell through to whatever case happened to be nearby — 声音
/// and 麦克风 both landed on the settings tab, 通知 / 游戏基地 / 周边设备 did
/// nothing at all.
enum CcKind { tab, search, panel }

/// The inline panels the dock can show. Adding an entry here forces
/// `_panelFor` in the shell to handle it, so a panel cannot ship unhandled.
enum CcPanelId { recent, notifications, sources, sound, subtitle, picture, profile, power }

class CcItem {
  const CcItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.kind,
    this.tabIndex = 0,
    this.panel,
  }) : assert(kind != CcKind.panel || panel != null);

  final String id;
  final IconData icon;
  final String label;
  final CcKind kind;

  /// Only meaningful for [CcKind.tab].
  final int tabIndex;

  /// Only meaningful for [CcKind.panel].
  final CcPanelId? panel;
}

/// The dock entries, left to right.
///
/// The order keeps the console reference's rhythm (home at the far left, power
/// at the far right) while the contents map one-to-one onto player functions:
/// resume, notifications, search, library, sources, audio, subtitles, picture,
/// profile, power.
const List<CcItem> kControlCenterItems = <CcItem>[
  CcItem(
    id: 'home',
    icon: Icons.home_outlined,
    label: S.ccHome,
    kind: CcKind.tab,
    tabIndex: 0,
  ),
  CcItem(
    id: 'recent',
    icon: Icons.history_rounded,
    label: S.ccRecent,
    kind: CcKind.panel,
    panel: CcPanelId.recent,
  ),
  CcItem(
    id: 'notifications',
    icon: Icons.notifications_none,
    label: S.ccNotifications,
    kind: CcKind.panel,
    panel: CcPanelId.notifications,
  ),
  CcItem(
    id: 'search',
    icon: Icons.search_rounded,
    label: S.ccSearch,
    kind: CcKind.search,
  ),
  CcItem(
    id: 'library',
    icon: Icons.video_library_outlined,
    label: S.ccLibrary,
    kind: CcKind.tab,
    tabIndex: 1,
  ),
  CcItem(
    id: 'sources',
    icon: Icons.cloud_outlined,
    label: S.ccSources,
    kind: CcKind.panel,
    panel: CcPanelId.sources,
  ),
  CcItem(
    id: 'sound',
    icon: Icons.volume_up_outlined,
    label: S.ccSound,
    kind: CcKind.panel,
    panel: CcPanelId.sound,
  ),
  CcItem(
    id: 'subtitle',
    icon: Icons.subtitles_outlined,
    label: S.ccSubtitle,
    kind: CcKind.panel,
    panel: CcPanelId.subtitle,
  ),
  CcItem(
    id: 'picture',
    icon: Icons.tune_rounded,
    label: S.ccPicture,
    kind: CcKind.panel,
    panel: CcPanelId.picture,
  ),
  CcItem(
    id: 'profile',
    icon: Icons.person_outline_rounded,
    label: S.ccProfile,
    kind: CcKind.panel,
    panel: CcPanelId.profile,
  ),
  CcItem(
    id: 'power',
    icon: Icons.power_settings_new_rounded,
    label: S.ccPower,
    kind: CcKind.panel,
    panel: CcPanelId.power,
  ),
];

/// Looks up an item by id, returning null instead of guessing.
CcItem? ccItemById(String id) {
  for (final CcItem item in kControlCenterItems) {
    if (item.id == id) {
      return item;
    }
  }
  return null;
}
