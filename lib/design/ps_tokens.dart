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

  /// Outcomes a component reports (toasts, scan progress, destructive rows).
  /// Values are the reference kit's defaults (`theme.hpp:84-86`); `danger` is
  /// deliberately ours, see `docs/DESIGN_TOKENS.md` §7.
  static const Color success = Color(0xFF30A46C);
  static const Color warning = Color(0xFFF5A524);

  /// Text drawn on an accent-filled control.
  static const Color onAccent = Color(0xFFFFFFFF);

  /// The hairline of light along a glass panel's edge (the kit's `light`
  /// token, `aurora.cpp:521`): white at 22 %.
  static const Color glassEdge = Color(0x38FFFFFF);

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

/// Geometry of the focused control's ring.
///
/// The reference kit splits this into `focus_width` and `focus_gap`
/// (`theme.hpp:99-100`); keeping both named here means the ring can be tuned in
/// one place instead of in each focusable.
abstract final class PsFocus {
  static const double ringWidth = 2.5;

  /// Distance between the control's edge and the ring. Matches the kit's
  /// `focus_gap` of 4.
  static const double ringGap = 4;

  static const double glowWidth = 8;
  static const double glowBlur = 8;

  /// The stage's single gliding ring is bolder than an item's own fallback
  /// ring: the eye has to be able to follow it across the room.
  static const double glideGlowWidth = 14;
  static const double glideGlowBlur = 16;
}

/// Shadows, by what the surface is doing.
///
/// Craft guide §5: a focused card floats (offset 10..26, softness 30..46);
/// resting cards have none or a very faint one. A modal sheet floats higher
/// than a card, which is why it has its own entry rather than a scale factor.
abstract final class PsElevation {
  static const List<BoxShadow> cardResting = <BoxShadow>[
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 24,
      offset: Offset(0, 14),
    ),
  ];

  static const List<BoxShadow> cardFocused = <BoxShadow>[
    BoxShadow(
      color: Color(0x8C000000),
      blurRadius: 26,
      offset: Offset(0, 18),
    ),
  ];

  /// Overlays and the detail sheet.
  static const List<BoxShadow> sheet = <BoxShadow>[
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 60,
      offset: Offset(0, 20),
    ),
  ];

  /// Hero artwork: it is lit by its own colour and casts a long drop. The glow
  /// uses the artwork's accent, not one global highlight colour.
  static List<BoxShadow> heroGlow(Color accent) {
    return <BoxShadow>[
      BoxShadow(color: accent.withValues(alpha: 0.30), blurRadius: 60, spreadRadius: 6),
      BoxShadow(
        color: const Color(0xFF000000).withValues(alpha: 0.55),
        blurRadius: 36,
        offset: const Offset(0, 26),
      ),
    ];
  }
}

/// Blur radii for translucent panels.
///
/// Full-screen multi-layer blur is the fastest way to lose frames on Windows;
/// only modal surfaces get one, and these are the only three sizes in use.
abstract final class PsBlur {
  /// Hint bars, toasts.
  static const double subtle = 12;

  /// The control center's dock and its panels.
  static const double panel = 24;

  /// Dialogs and the search sheet, which sit over the whole scene.
  static const double dialog = 28;

  /// How much of the panel's own tint is laid over the blurred copy.
  static const double glassTint = 0.62;
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

  // ---- spring presets ----
  //
  // Every moving thing is a spring chasing a target; what differs is how fast.
  // The craft guide's bands are: focus 18..22, panels and sheets 12..14,
  // colour 4..6. Naming them keeps the bands from drifting apart per widget.
  static const double springFocus = 20;
  static const double springPanel = 13;
  static const double springPalette = 5;

  /// Large, soft travel: layout re-centring, artwork that follows the state.
  static const double springSoft = 10;

  // ---- one-shot timing ----
  //
  // Arrivals start fast and stop soft (cubic/quint out); departures are shorter
  // and use cubic in, so closing never feels slower than opening.
  static const double staggerStep = 0.04;
  static const double arrive = 0.35;
  static const double depart = 0.22;
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
