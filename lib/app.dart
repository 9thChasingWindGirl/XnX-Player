import 'package:material_ui/material_ui.dart';

import 'core/input/gamepad.dart';
import 'core/input/input_router.dart';
import 'data/store.dart';
import 'design/ps_theme.dart';
import 'shell/shell_page.dart';
import 'ui/core/motion_clock.dart';
import 'ui/core/text_entry.dart';

class XnXApp extends StatefulWidget {
  const XnXApp({super.key});

  @override
  State<XnXApp> createState() => _XnXAppState();
}

class _XnXAppState extends State<XnXApp> {
  /// One clock for the whole application; every spring reads `dt` from it.
  late final MotionClock _clock = MotionClock();

  @override
  void initState() {
    super.initState();
    // One keyboard handler for the whole app, and only one. Screens subscribe
    // their own layer to it instead of each installing a global handler, which
    // made the dispatch order an accident of widget lifetime.
    final InputRouter router = InputRouter.instance;
    router.textEntryActive = () => TextEntry.active.value;
    router.install();
    // XInput is polled on its own timer: it is a device that reports state, not
    // events, and nothing else in the app can see it.
    GamepadPoller.instance.start();
    AppStore.instance.addListener(_syncAccessibility);
    _syncAccessibility();
  }

  @override
  void dispose() {
    GamepadPoller.instance.stop();
    InputRouter.instance.uninstall();
    AppStore.instance.removeListener(_syncAccessibility);
    _clock.dispose();
    super.dispose();
  }

  void _syncAccessibility() {
    _clock.reduceMotion = AppStore.instance.prefs.reduceMotion;
  }

  @override
  Widget build(BuildContext context) {
    return MotionScope(
      clock: _clock,
      child: MaterialApp(
        title: 'XnX Player',
        debugShowCheckedModeBanner: false,
        theme: buildPsTheme(),
        home: const ShellPage(),
      ),
    );
  }
}
