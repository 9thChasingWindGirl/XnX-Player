import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
  testWidgets('a focusable outside the app still takes focus and builds',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TvFocusable(
            autofocus: true,
            onSelect: () {},
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    );

    // A second frame so the focused branch — the one that asks for a clock —
    // is actually built.
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
  });

  testWidgets('a screen that needs the clock fails loudly instead of standing still',
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
