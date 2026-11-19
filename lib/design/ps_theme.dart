import 'package:material_ui/material_ui.dart';

import 'ps_tokens.dart';

/// App-wide Material theme. Almost everything is drawn by hand, so the theme is
/// deliberately stripped down to the four values the framework actually reads
/// during layout: the colour scheme, the two canvas colours and the hairline.
///
/// Keeping it minimal is also a portability guard — the framework keeps pruning
/// legacy [ThemeData] fields (ripple factories, Material 2 toggles), and none of
/// those matter here because the UI never uses [InkWell].
ThemeData buildPsTheme() {
  return ThemeData(
    colorScheme: const ColorScheme.dark(
      primary: PsColor.accent,
      secondary: PsColor.accentHover,
      surface: PsColor.surface,
      onSurface: PsColor.text,
      error: PsColor.danger,
    ),
    scaffoldBackgroundColor: PsColor.bgDeep,
    canvasColor: PsColor.bgDeep,
    dividerColor: PsColor.hairline,
  );
}
