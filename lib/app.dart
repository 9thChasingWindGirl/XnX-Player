import 'package:material_ui/material_ui.dart';

import 'data/store.dart';
import 'design/ps_theme.dart';
import 'shell/shell_page.dart';
import 'ui/core/motion_clock.dart';

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
    AppStore.instance.addListener(_syncAccessibility);
    _syncAccessibility();
  }

  @override
  void dispose() {
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
