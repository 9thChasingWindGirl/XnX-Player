import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/shell/control_center_items.dart';

/// The dock used to route by string id inside a `switch`, and six of the eleven
/// entries fell through: 声音 and 麦克风 both landed on the settings tab, 通知 /
/// 游戏基地 / 周边设备 did nothing at all. These tests pin down the contract
/// that replaced it — every entry declares what it does, and every declared
/// panel is reachable from exactly one entry.
void main() {
  group('control center entries', () {
    test('ids are unique and stable enough to be used as keys', () {
      final Set<String> ids = <String>{};
      for (final CcItem item in kControlCenterItems) {
        expect(item.id, isNotEmpty);
        expect(ids.add(item.id), isTrue, reason: 'duplicate id: ${item.id}');
      }
    });

    test('every entry has exactly one behaviour', () {
      for (final CcItem item in kControlCenterItems) {
        switch (item.kind) {
          case CcKind.tab:
            expect(item.panel, isNull, reason: '${item.id} is a tab, not a panel');
            expect(item.tabIndex, inInclusiveRange(0, 2));
          case CcKind.search:
            expect(item.panel, isNull, reason: '${item.id} opens search');
          case CcKind.panel:
            expect(item.panel, isNotNull, reason: '${item.id} must name its panel');
        }
      }
    });

    test('no panel is orphaned and none is claimed twice', () {
      final Map<CcPanelId, String> owners = <CcPanelId, String>{};
      for (final CcItem item in kControlCenterItems) {
        final CcPanelId? panel = item.panel;
        if (panel == null) {
          continue;
        }
        expect(
          owners.containsKey(panel),
          isFalse,
          reason: '${panel.name} is claimed by ${owners[panel]} and ${item.id}',
        );
        owners[panel] = item.id;
      }
      for (final CcPanelId panel in CcPanelId.values) {
        expect(owners.containsKey(panel), isTrue, reason: '${panel.name} has no dock entry');
      }
    });

    test('lookup resolves known ids and refuses unknown ones', () {
      for (final CcItem item in kControlCenterItems) {
        expect(ccItemById(item.id)?.id, item.id);
      }
      expect(ccItemById('no-such-entry'), isNull);
    });

    test('entries that used to forward to settings now own a panel', () {
      // Regression guard for the original complaint: 声音 / 麦克风 both opened
      // 设置, so the label promised something the button did not do.
      for (final String id in <String>['sound', 'subtitle', 'picture', 'profile']) {
        final CcItem? item = ccItemById(id);
        expect(item, isNotNull, reason: '$id disappeared from the dock');
        expect(item!.kind, CcKind.panel);
      }
    });
  });
}
