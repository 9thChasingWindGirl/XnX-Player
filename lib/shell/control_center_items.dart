import 'package:flutter/material.dart';

import '../core/strings.dart';

class CcItem {
  const CcItem({required this.id, required this.icon, required this.label});

  final String id;
  final IconData icon;
  final String label;
}

/// The eleven default Control Center entries, in PS5 order.
const List<CcItem> kControlCenterItems = <CcItem>[
  CcItem(id: 'home', icon: Icons.home_outlined, label: S.ccHome),
  CcItem(id: 'switcher', icon: Icons.grid_view_rounded, label: S.ccSwitcher),
  CcItem(id: 'notifications', icon: Icons.notifications_none, label: S.ccNotifications),
  CcItem(id: 'gamebase', icon: Icons.sports_esports_outlined, label: S.ccGameBase),
  CcItem(id: 'music', icon: Icons.music_note_outlined, label: S.ccMusic),
  CcItem(id: 'downloads', icon: Icons.download_outlined, label: S.ccDownloads),
  CcItem(id: 'sound', icon: Icons.volume_up_outlined, label: S.ccSound),
  CcItem(id: 'mic', icon: Icons.mic_none_rounded, label: S.ccMic),
  CcItem(id: 'accessories', icon: Icons.devices_other_outlined, label: S.ccAccessories),
  CcItem(id: 'profile', icon: Icons.person_outline_rounded, label: S.ccProfile),
  CcItem(id: 'power', icon: Icons.power_settings_new_rounded, label: S.ccPower),
];
