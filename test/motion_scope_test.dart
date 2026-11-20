import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xnx_player/ui/core/focus_navigator.dart';
import 'package:xnx_player/ui/core/focus_zone.dart';
import 'package:xnx_player/ui/core/motion_clock.dart';
import 'package:xnx_player/ui/core/tv_focusable.dart';

/// Where the clock is required and where it is merely nice to have.
///
/// `TvFocusable` is mounted outside the app all the time — a widget test, a
/// golden, an isolated preview. Its per-frame publisher only keeps the gliding
/// ring welded to a rail that is scrolling, so without a clock the ring can
/// simply stop between frames; failing the build instead is what took down
/// `focus_memory_test` on CI. Screens, on the other hand, must not lose their
/// springs in silence, so the strict builder keeps throwing.
void main() {
  setUp(FocusRegistry.instance.reset);
  tearDown(FocusRegistry.instance.reset);

  testWidgets('a focusable outside the app still takes focus and builds',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TvFocusable(
            focusId: 'probe',
            onSelect: () {},
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    );

    expect(FocusNavigator.focusById('probe'), isTrue);
    // One frame to apply the focus change, a second for the focused branch —
    // the one that asks for a clock — to be built.
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(FocusRegistry.instance.entryById('probe')?.node.hasFocus, isTrue);
  });

  testWidgets('a screen that needs the clock fails instead of standing still',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MotionBuilder(builder: _nothing),
      ),
    );

    expect(tester.takeException(), isA<FlutterError>());
  });
}

Widget _nothing(BuildContext context, double dt) => const SizedBox.shrink();
