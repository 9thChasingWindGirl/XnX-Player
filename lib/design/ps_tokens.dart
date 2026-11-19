import 'package:flutter/widgets.dart';

/// Design tokens, transcribed from the console reference measurements.
///
/// Layout constants come from the reference home screen (`kMargin 96`,
/// `kCard 196`, `kCardGap 26`, `kCardGrow 1.2`, `kShelfY 730`,
/// `kShelfPitch 304`); type sizes and motion feel come from its craft guide
/// (body 24..28, nothing readable under 20, tracked capitals 15..20 at 3..4,
/// hero 60..96, focus settles in 120..200 ms).
abstract final class PsColor {
  // Stage
  static const Color bgDeep = Color(0xFF05060C);
  static const Color bg = Color(0xFF0B0D16);

  // Surfaces
  static const Color surface = Color(0xFF1C1E24);
  static const Color surfaceHigh = Color(0xFF24262E);
  static const Color sheetTop = Color(0xFF2D2E33);
  static const Color sheetBottom = Color(0xFF191A22);

  // Type
  static const Color text = Color(0xFFFFFFFF);
  static const Color textDim = Color(0xB8FFFFFF);
  static const Color textFaint = Color(0x8AFFFFFF);
  static const Color textDisabled = Color(0x59FFFFFF);

  // Accents, used sparingly: one per region.
  static const Color accent = Color(0xFF0070CC);
  static const Color accentHover = Color(0xFF1EAEDB);
  static const Color plus = Color(0xFF6B37FF);
  static const Color star = Color(0xFFFFD166);

  // Lines & states
  static const Color hairline = Color(0x24FFFFFF);
  static const Color scrim = Color(0xF2000000);
  static const Color scrimSoft = Color(0x8A000000);
  static const Color danger = Color(0xFFFF5D6C);

  // Focus
  static const Color focusRing = Color(0xFFFFFFFF);
  static const Color focusGlow = Color(0x59FFFFFF);

  /// Deterministic artwork palettes: `[dark, mid, accent]`. Artwork is key art,
  /// so it is high saturation; the chrome on top of it stays monochrome.
  static const List<List<Color>> artPalette = <List<Color>>[
    <Color>[Color(0xFF101623), Color(0xFF26324A), Color(0xFF5B7FBF)],
    <Color>[Color(0xFF171021), Color(0xFF3A2A44), Color(0xFFA46BB8)],
    <Color>[Color(0xFF0C1717), Color(0xFF1F3B3A), Color(0xFF41B3A3)],
    <Color>[Color(0xFF18120A), Color(0xFF40331E), Color(0xFFC9963F)],
    <Color>[Color(0xFF12121F), Color(0xFF2B2C4A), Color(0xFF6E74D8)],
    <Color>[Color(0xFF170D10), Color(0xFF3B2429), Color(0xFFC05A6B)],
  ];

  static int _hash(String seed) {
    int hash = 0;
    for (int i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash;
  }

  static List<Color> artFor(String seed) => artPalette[_hash(seed) % artPalette.length];

  static Color artDark(String seed) => artFor(seed)[0];

  static Color artMid(String seed) => artFor(seed)[1];

  static Color artAccent(String seed) => artFor(seed)[2];
}

abstract final class PsSpace {
  /// Horizontal safe area at 1920x1080 (reference `kMargin`).
  static const double safeX = 96;

  /// Vertical safe area: text and focusables never cross it; scrims may.
  static const double safeY = 60;

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double huge = 64;

  /// Home shelf geometry (reference values).
  static const double tileSize = 196;
  static const double cardGap = 26;
  static const double cardGrow = 1.2;
  static const double shelfY = 730;
  static const double shelfPitch = 304;
  static const double shelfTitleOffset = 62;

  static const double railTitleGap = 20;
  static const double railGap = 16;

  /// Hero panel geometry.
  static const double heroArt = 440;
  static const double heroArtX = 1316;
  static const double heroArtY = 132;
  static const double heroTextWidth = 820;

  static const double topBarHeight = 96;
  static const double dockHeight = 132;

  /// Kept for older layouts that still reference them.
  static const double railHeight = 196;
  static const double heroHeight = 420;
}

abstract final class PsRadius {
  static const double card = 22;
  static const double cardLarge = 26;
  static const double hero = 36;
  static const double sheet = 44;
  static const double pill = 999;
}

/// Durations for one-shot transitions (routes, fades, panel slide). Continuous
/// motion is spring-driven and has no duration — see `ps_motion.dart`.
abstract final class PsMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration reveal = Duration(milliseconds: 260);
  static const Duration shineCycle = Duration(seconds: 7);

  static const Curve curve = Curves.easeInOut;
  static const Curve out = Curves.easeOutCubic;

  /// Seconds, for the `update(dt)` loops.
  static const double heroCrossFade = 0.42;
  static const double entrance = 0.6;
  static const double panel = 0.32;
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

  /// Hero title, 88 in the reference.
  static const TextStyle display = TextStyle(
    fontSize: 88,
    height: 1.02,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.2,
    color: PsColor.text,
  );

  /// Legacy hero size, used by secondary headers.
  static const TextStyle hero = TextStyle(
    fontSize: 72,
    height: 1.06,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.8,
    color: PsColor.text,
  );

  /// Page title.
  static const TextStyle page = TextStyle(
    fontSize: 56,
    height: 1.1,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.4,
    color: PsColor.text,
  );

  /// Shelf title, 24 in the reference.
  static const TextStyle section = TextStyle(
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: PsColor.text,
  );

  static const TextStyle stat = TextStyle(
    fontSize: 40,
    height: 1.1,
    fontWeight: FontWeight.w300,
    color: PsColor.text,
  );

  static const TextStyle card = TextStyle(
    fontSize: 24,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    color: PsColor.text,
  );

  /// Body copy, 26 in the reference.
  static const TextStyle body = TextStyle(
    fontSize: 26,
    height: 1.42,
    fontWeight: FontWeight.w400,
    color: PsColor.textDim,
  );

  static const TextStyle meta = TextStyle(
    fontSize: 26,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: PsColor.textDim,
  );

  static const TextStyle label = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: PsColor.text,
  );

  /// Tracked capitals that organise a screen without shouting.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 4,
    color: PsColor.text,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: PsColor.textFaint,
  );

  /// Small numbers that change while you watch them (timers, counters): fixed
  /// width keeps them from jittering.
  static const TextStyle numeral = TextStyle(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w400,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    color: PsColor.textDim,
  );
}
