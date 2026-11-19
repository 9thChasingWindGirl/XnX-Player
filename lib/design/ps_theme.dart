import 'package:flutter/material.dart';

import 'ps_tokens.dart';

/// App-wide Material theme. Almost everything is drawn by hand, so the theme is
/// deliberately stripped down: no splash, no elevation tint, no ripple.
ThemeData buildPsTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: PsColor.bgDeep,
    canvasColor: PsColor.bgDeep,
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x00000000),
    focusColor: const Color(0x00000000),
    hoverColor: const Color(0x00000000),
    dividerColor: PsColor.hairline,
    colorScheme: const ColorScheme.dark(
      primary: PsColor.accent,
      secondary: PsColor.accentHover,
      surface: PsColor.surface,
      onSurface: PsColor.text,
      error: PsColor.danger,
    ),
  );
}
