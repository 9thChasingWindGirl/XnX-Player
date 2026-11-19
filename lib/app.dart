import 'package:flutter/material.dart';

import 'design/ps_theme.dart';
import 'shell/shell_page.dart';

class XnXApp extends StatelessWidget {
  const XnXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XnX Player',
      debugShowCheckedModeBanner: false,
      theme: buildPsTheme(),
      home: const ShellPage(),
    );
  }
}
