import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xnx_player/ui/core/focus_memory.dart';
import 'package:xnx_player/ui/core/focus_navigator.dart';
import 'package:xnx_player/ui/core/focus_zone.dart';
import 'package:xnx_player/ui/core/tv_focusable.dart';

/// A column of focusable items laid out like a rail, so ids and geometry are
/// both real rather than mocked. Wrapped in an app because focus needs a root
/// scope to attach to.
Widget _rail(List<String?> ids) {
  return MaterialApp(
    home: FocusZone(
      id: 'test-rail',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final String? id in ids)
            TvFocusable(
              focusId: id,
              child: const SizedBox(width: 100, height: 40),
            ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() {
    FocusRegistry.instance.reset();
    FocusMemory.instance.clear();
  });
  tearDown(FocusRegistry.instance.reset);

  group('registry addresses', () {
    testWidgets('an id resolves to its entry', (WidgetTester tester) async {
      await tester.pumpWidget(_rail(<String?>['a', 'b']));

      final FocusEntry? entry = FocusRegistry.instance.entryById('b');
      expect(entry, isNotNull);
      expect(entry!.zoneId, 'test-rail');
      expect(FocusRegistry.instance.entryById('nope'), isNull);
    });

    testWidgets('items without an id stay navigable but unaddressable',
        (WidgetTester tester) async {
      await tester.pumpWidget(_rail(<String?>[null, null]));

      expect(FocusRegistry.instance.entries, hasLength(2));
      expect(FocusRegistry.instance.entryById('a'), isNull);
      expect(FocusNavigator.focusFirst(), isTrue);
    });

    testWidgets('focusById only lands on something focusable',
        (WidgetTester tester) async {
      await tester.pumpWidget(_rail(<String?>['a', 'b']));

      expect(FocusNavigator.focusById('b'), isTrue);
      expect(FocusNavigator.focusById('missing'), isFalse);
    });
  });

  group('reindex', () {
    testWidgets('a recycled item moves its address, not its slot',
        (WidgetTester tester) async {
      await tester.pumpWidget(_rail(<String?>['a', 'b']));
      final int orderBefore = FocusRegistry.instance.entries.last.order;

      // Same widget slot, different episode: the list rebuilds with new ids in
      // the same positions.
      await tester.pumpWidget(_rail(<String?>['c', 'd']));

      expect(FocusRegistry.instance.entryById('a'), isNull);
      expect(FocusRegistry.instance.entryById('c'), isNotNull);
      expect(FocusRegistry.instance.entries.last.order, orderBefore);
    });
  });

  group('memory', () {
    testWidgets('restore returns to the remembered id',
        (WidgetTester tester) async {
      await tester.pumpWidget(_rail(<String?>['a', 'b']));
      FocusMemory.instance.install();
      addTearDown(FocusMemory.instance.uninstall);

      FocusNavigator.focusById('a');
      await tester.pump();
      final FocusMark mark = FocusMemory.instance.mark();

      FocusNavigator.focusById('b');
      await tester.pump();

      expect(FocusMemory.instance.restore(mark), isTrue);
      await tester.pump();

      final FocusEntry? focused =
          FocusRegistry.instance.entryFor(FocusManager.instance.primaryFocus);
      expect(focused?.id, 'a');
    });

    testWidgets('a vanished id falls back to the zone, not to nothing',
        (WidgetTester tester) async {
      await tester.pumpWidget(_rail(<String?>['a', 'b']));
      FocusMemory.instance.install();
      addTearDown(FocusMemory.instance.uninstall);

      FocusNavigator.focusById('b');
      await tester.pump();
      final FocusMark mark = FocusMemory.instance.mark();

      // The title left the rail; its address is gone with it.
      await tester.pumpWidget(_rail(<String?>['a', 'c']));
      expect(FocusRegistry.instance.entryById('b'), isNull);

      expect(FocusMemory.instance.restore(mark), isTrue);
      await tester.pump();

      final FocusEntry? focused =
          FocusRegistry.instance.entryFor(FocusManager.instance.primaryFocus);
      expect(focused?.zoneId, 'test-rail');
    });
  });
}
