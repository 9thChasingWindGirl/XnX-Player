import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'core/input/gamepad.dart';
import 'core/input/input_router.dart';
import 'core/sound/sound_manager.dart';
import 'data/prefs.dart';
import 'data/store.dart';
import 'design/ps_theme.dart';
import 'shell/shell_page.dart';
import 'ui/core/focus_memory.dart';
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
    // Watches the focus owner so a page can come back to the item you left
    // without every surface having to snapshot it on the way out.
    FocusMemory.instance.install();
    // Decoding twenty short wavs off the bundle happens once; until it lands
    // the app is simply quiet, which is better than blocking first paint.
    unawaited(SoundManager.instance.load());
    AppStore.instance.addListener(_syncAccessibility);
    _syncAccessibility();
  }

  @override
  void dispose() {
    GamepadPoller.instance.stop();
    InputRouter.instance.uninstall();
    FocusMemory.instance.uninstall();
    AppStore.instance.removeListener(_syncAccessibility);
    SoundManager.instance.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _syncAccessibility() {
    final PlaybackPrefs prefs = AppStore.instance.prefs;
    _clock.reduceMotion = prefs.reduceMotion;
    SoundManager.instance.enabled = prefs.soundEnabled;
    SoundManager.instance.volume = (prefs.soundVolume / 100).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return MotionScope(
      clock: _clock,
      child: MaterialApp(
        title: 'XnX Player',
        debugShowCheckedModeBanner: false,
        theme: buildPsTheme(),
        // Global guard against stray text decorations. A widget that forgets
        // to set an explicit PsType style inherits DefaultTextStyle; if any
        // upstream theme ever carries an underline, it lands on every line of
        // copy as an orange rule. Merging `none` here makes that impossible
        // regardless of which style a leaf ends up using, while leaving every
        // explicit style (all PsType.*) untouched.
        builder: (BuildContext context, Widget? child) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const ShellPage(),
      ),
    );
  }
}
