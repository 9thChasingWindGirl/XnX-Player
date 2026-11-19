import 'package:flutter/widgets.dart';

/// PlayStation 5 system UI design tokens.
///
/// Single source of truth for every visual constant in the app. Derived from
/// the PS5 home screen / Control Center: a dark stage with high-saturation key
/// art, and monochrome chrome (white / greys) on top. Blue is reserved for the
/// primary call to action only.
abstract final class PsColor {
  // Stage
  static const Color bgDeep = Color(0xFF07080D);
  static const Color bg = Color(0xFF0E1018);

  // Surfaces
  static const Color surface = Color(0xFF1C1E24);
  static const Color surfaceHigh = Color(0xFF24262E);
  static const Color sheetTop = Color(0xFF2D2E33);
  static const Color sheetBottom = Color(0xFF191A22);

  // Type
  static const Color text = Color(0xFFFFFFFF);
  static const Color textDim = Color(0x99FFFFFF);
  static const Color textFaint = Color(0x59FFFFFF);
  static const Color textDisabled = Color(0x59FFFFFF);

  // Accents (used sparingly)
  static const Color accent = Color(0xFF0070CC);
  static const Color accentHover = Color(0xFF1EAEDB);
  static const Color plus = Color(0xFF6B37FF);

  // Lines & states
  static const Color hairline = Color(0x1FFFFFFF);
  static const Color scrim = Color(0xE6000000);
  static const Color scrimSoft = Color(0x80000000);
  static const Color danger = Color(0xFFFF5D6C);

  // Focus
  static const Color focusRing = Color(0xFFFFFFFF);
  static const Color focusGlow = Color(0x59FFFFFF);

  /// Deterministic gradient pairs for artwork placeholders, so a title always
  /// keeps the same colour across launches.
  static const List<List<Color>> artPalette = <List<Color>>[
    <Color>[Color(0xFF26324A), Color(0xFF101623)],
    <Color>[Color(0xFF3A2A44), Color(0xFF171021)],
    <Color>[Color(0xFF1F3B3A), Color(0xFF0C1717)],
    <Color>[Color(0xFF40331E), Color(0xFF18120A)],
    <Color>[Color(0xFF2B2C4A), Color(0xFF12121F)],
    <Color>[Color(0xFF3B2429), Color(0xFF170D10)],
  ];

  static List<Color> artFor(String seed) {
    var hash = 0;
    for (var i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return artPalette[hash % artPalette.length];
  }
}

abstract final class PsSpace {
  /// Horizontal safe area at 1920x1080.
  static const double safeX = 96;

  /// Vertical safe area at 1920x1080.
  static const double safeY = 54;

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double huge = 64;

  static const double railGap = 16;
  static const double railTitleGap = 20;

  /// Home hub geometry (1920x1080 reference).
  static const double tileSize = 200;
  static const double railHeight = 200;
  static const double heroHeight = 420;
  static const double dockHeight = 132;

  static const double topBarHeight = 96;
}

abstract final class PsRadius {
  static const double card = 14;
  static const double cardLarge = 18;
  static const double sheet = 24;
  static const double pill = 999;
}

abstract final class PsMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration reveal = Duration(milliseconds: 260);
  static const Duration shineCycle = Duration(seconds: 7);

  static const Curve curve = Curves.easeInOut;
  static const Curve out = Curves.easeOutCubic;
}

abstract final class PsType {
  static const List<String> fontFallback = <String>[
    'Segoe UI Variable Display',
    'Segoe UI',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans SC',
  ];

  static const TextStyle hero = TextStyle(
    fontSize: 56,
    height: 1.14,
    fontWeight: FontWeight.w300,
    letterSpacing: 0.4,
    color: PsColor.text,
  );

  static const TextStyle page = TextStyle(
    fontSize: 40,
    height: 1.2,
    fontWeight: FontWeight.w300,
    letterSpacing: 0.3,
    color: PsColor.text,
  );

  static const TextStyle section = TextStyle(
    fontSize: 28,
    height: 1.28,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    color: PsColor.text,
  );

  static const TextStyle card = TextStyle(
    fontSize: 24,
    height: 1.33,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    color: PsColor.text,
  );

  static const TextStyle body = TextStyle(
    fontSize: 20,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: PsColor.textDim,
  );

  static const TextStyle label = TextStyle(
    fontSize: 18,
    height: 1.33,
    fontWeight: FontWeight.w400,
    color: PsColor.text,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: PsColor.textDim,
  );
}
