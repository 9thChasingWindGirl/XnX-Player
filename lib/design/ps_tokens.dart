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

/// Palette of the Plex-style home layout.
///
/// Kept next to the console tokens rather than folded into [PsColor]: the home
/// screen is deliberately denser and warmer than the PS5 stage, and mixing the
/// two would make every other page inherit the change. Values follow Plex's
/// neutral dark UI: near-black surfaces, a single amber accent, and white ink
/// that only reaches 90 % so dense text stays readable.
abstract final class PlexColor {
  static const Color bg = Color(0xFF141416);
  static const Color bgDeep = Color(0xFF0D0D0F);
  static const Color surface = Color(0xFF1F1F22);
  static const Color surfaceHigh = Color(0xFF2A2A2E);
  static const Color amber = Color(0xFFE5A00D);
  static const Color text = Color(0xFFF5F5F7);
  static const Color textDim = Color(0xFFB3B3B9);
  static const Color textFaint = Color(0xFF8A8A91);
  static const Color line = Color(0x24FFFFFF);
  static const Color scrim = Color(0xE60C0C0E);
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

  /// A focused card is drawn larger, and the reference bumps the corner with
  /// it: `aurora.cpp:503` rings the grown card at radius 30 where the resting
  /// card is 22. Growing the rectangle without growing the corner makes a big
  /// card look pinched.
  static const double cardFocused = 26;

  static const double cardLarge = 26;
  static const double hero = 36;
  static const double sheet = 44;
  static const double pill = 999;
}

/// Geometry of the focused control's ring.
///
/// The reference splits this into `focus_width` and `focus_gap`
/// (`theme.hpp:99-100`), but what it *draws* is what matters, and
/// `aurora.cpp:503` is explicit: `bordered_rect(ring.inset(-5), 30, …, 4, white)`
/// — a 4 px stroke, 5 px outside the card. The struct's default of 3 is what
/// other themes use, not what the home screen shows.
abstract final class PsFocus {
  static const double ringWidth = 4;

  /// Distance between the control's edge and the ring.
  static const double ringGap = 5;

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
  /// Resting cards cast nothing. `draw_card` only draws a shadow once
  /// `focus > 0.01` (`card.cpp:256`), and the home screen's shelf calls
  /// `list.image` with no shadow at all (`aurora.cpp:488`). We used to keep a
  /// 35 % / blur-20 drop "so the artwork does not look pasted on"; that is a
  /// taste call the reference does not make, and it made every card read as
  /// already half focused.
  static const List<BoxShadow> cardResting = <BoxShadow>[];

  /// A focused card on the stage floats high: `shadow({x, y+18, w, h}, 26,
  /// 34, black 0.6)` at `aurora.cpp:500`. The ring's own radius is passed
  /// separately (26 is the rounded-rect radius, not a blur).
  static const List<BoxShadow> cardFocused = <BoxShadow>[
    BoxShadow(
      color: Color(0x99000000),
      blurRadius: 34,
      offset: Offset(0, 18),
    ),
  ];

  /// A focused card *inside* a collection: the kit's generic card shadow,
  /// `{frame.x+4, y+10+8*focus, w-8, h}` blurred `22+16*focus` at 34 %
  /// (`card.cpp:258-261`). It is narrower than the card and sits slightly to
  /// the right because a focused card is lifted, and the light comes from the
  /// upper left of the set.
  static List<BoxShadow> cardLifted(double focus) {
    final double t = focus.clamp(0.0, 1.0).toDouble();
    return <BoxShadow>[
      BoxShadow(
        color: const Color(0xFF000000).withValues(alpha: 0.34 * t),
        blurRadius: 22 + 16 * t,
        offset: Offset(4, 10 + 8 * t),
      ),
    ];
  }

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
/// The tint that goes *on top* of the blur is not a blur — see [PsGlass].
abstract final class PsBlur {
  /// Hint bars, toasts.
  static const double subtle = 12;

  /// The control center's dock and its panels.
  static const double panel = 24;

  /// Dialogs and the search sheet, which sit over the whole scene.
  static const double dialog = 28;
}

/// What a floating surface is made of.
///
/// Every overlay in the kit — a dialog, a sheet, a toast, a bubble — goes
/// through one function, `draw_overlay_panel` (`overlay.cpp:219-250`):
/// blur the screen behind (`list.glass`), cover it with the theme's surface
/// colour made opaque and then laid down at `tint`, and close the edge with a
/// stroke no thinner than 1.5 in the theme's outline. A sheet also lays a
/// scrim over the whole screen behind it.
///
/// The dock cannot copy that literally: `list.glass` both blurs *and* darkens
/// the scene as it captures it, and Flutter's [BackdropFilter] only blurs. So
/// the dock uses [dockTintTop] → [dockTintBottom], a higher opacity of the page
/// colour, to do the darkening the glass pass would have done. That is a
/// measured deviation, not a guess: see `docs/DESIGN_TOKENS.md` §12.
abstract final class PsGlass {
  /// A frosted panel: dialog, sheet, toast (`OverlayStyle::frost`, 0.55).
  static const double tint = 0.55;

  /// The home screen's detail drawer, tinted with the artwork
  /// (`aurora.cpp:519`): the panel is readable over a bright still.
  static const double sheetTint = 0.62;

  /// How much the screen behind a sheet is darkened (`SheetStyle::scrim`).
  static const double scrim = 0.50;

  /// Minimum stroke on a glass edge (`max(theme.border, 1.5)`).
  static const double edgeWidth = 1.5;

  /// The control center dock, top to bottom. Blur alone cannot hide playback
  /// behind it, so it is the page colour at 62 → 78 % rather than surface at
  /// 55 %. Both values were already in `control_center.dart`; they live here
  /// now so the dock and its panels cannot drift apart.
  static const double dockTintTop = 0.62;
  static const double dockTintBottom = 0.78;
}

/// Sizes of a group of content and the rows inside it.
///
/// `PanelStyle` (`surface.hpp:99-125`) and `ListViewStyle` (`list.hpp:32-37`).
/// The panel numbers are used; the row numbers are kept next to them because
/// the control center compresses its rows and must say by how much.
abstract final class PsPanel {
  /// Between the panel's edge and its content.
  static const double paddingX = 24;
  static const double paddingY = 20;

  static const double titleSize = 24;
  static const double subtitleSize = 19;

  /// A list's header, a row, and the room inside a row.
  static const double headerHeight = 52;

  /// 76 in the kit. A control-center panel is 420 tall; after its padding and
  /// header bar 76 leaves four rows and no slack for a fifth, so ours is 68
  /// with an 8 px gap — the same 76 pitch, a shorter row. See
  /// `docs/DESIGN_TOKENS.md` §12.
  static const double rowHeight = 68;
  static const double rowGap = 8;

  /// Between the panel's edge and its rows.
  static const double rowInset = 26;
}

/// How a piece of content behaves, as opposed to how it looks.
///
/// `CardLook` (`card.h:47-88`): the knobs every collection shares. Ours were
/// scattered across the tile, the dock card and the search result, and three
/// of them disagreed with the reference.
abstract final class PsCard {
  /// Full focus. The home shelf grows 20 % (`kCardGrow`, `aurora.cpp:44`) —
  /// that is the stage's own language, chosen because a shelf of covers has
  /// room to breathe. A card *inside a collection* (dock, grid, search) grows
  /// 6 %, and it is this number the kit defaults to.
  static const double focusScale = 1.06;

  /// A focused card rises this many pixels. `card_lift` returns
  /// `look.lift * focus` (`card.cpp:151-153`), so the ring travels with it.
  static const double lift = 6;

  /// A press pushes the card back in by this much (`press_scale = 0.04`).
  static const double pressScale = 0.04;

  /// The gradient a title laid *over* artwork sits on, black at 78 %
  /// (`CardLook::scrim`). Without it a white title on a bright poster is
  /// unreadable, which is why the reference never writes over art bare.
  static const double artScrim = 0.78;

  static const double titleSize = 24;
  static const double subtitleSize = 20;

  /// The inset of text written over the art (`CardLook::text_inset`).
  static const double textInset = 14;

  /// A short pill in the corner of the art ("4K", "NEW").
  static const double badgeSize = 16;

  /// The watched bar along the bottom of the art, and how far it stops short
  /// of the corners (`max(10, radius * 0.45)`, `card.cpp:300-305`).
  static const double progressHeight = 6;
  static const double progressInset = 10;

  /// Cards without the focus fade by this much; 0 is the kit's default.
  ///
  /// The home shelf does dim its neighbours, but that is a different knob:
  /// `aurora.cpp:487` draws an unfocused cover at `alpha 0.82`, i.e. 18 % wash
  /// applied by the *screen*, not by the card. Keeping the two separate is why
  /// this stays 0 while `PosterCard` still passes 0.18 down.
  static const double dim = 0;
}

/// Durations for one-shot transitions (routes, fades, panel slide). Continuous
/// motion is spring-driven and has no duration — see `ps_motion.dart`.
abstract final class PsMotion {
  static const Duration fast = Duration(milliseconds: 120);

  /// One card growing into focus. The craft guide's band is 120..200 ms; the
  /// short end keeps a held D-pad from feeling like it is dragging the artwork
  /// behind the ring.
  static const Duration grow = Duration(milliseconds: 160);

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

  // Every style states `decoration: none` explicitly. A Material/DevTools
  // default that carries an underline must never reach the hero copy — an
  // orange baseline line under every line reads as "the UI abuses underlines".
  // `copyWith` keeps this value unless a caller deliberately overrides it.

  /// Hero title, 88 in the reference.
  static const TextStyle display = TextStyle(
    fontSize: 88,
    height: 1.02,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.2,
    color: PsColor.text,
    decoration: TextDecoration.none,
  );

  /// Legacy hero size, used by secondary headers.
  static const TextStyle hero = TextStyle(
    fontSize: 72,
    height: 1.06,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.8,
    color: PsColor.text,
    decoration: TextDecoration.none,
  );

  /// Page title.
  static const TextStyle page = TextStyle(
    fontSize: 56,
    height: 1.1,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.4,
    color: PsColor.text,
    decoration: TextDecoration.none,
  );

  /// Shelf title, 24 in the reference.
  static const TextStyle section = TextStyle(
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: PsColor.text,
    decoration: TextDecoration.none,
  );

  static const TextStyle stat = TextStyle(
    fontSize: 40,
    height: 1.1,
    fontWeight: FontWeight.w300,
    color: PsColor.text,
    decoration: TextDecoration.none,
  );

  static const TextStyle card = TextStyle(
    fontSize: 24,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    color: PsColor.text,
    decoration: TextDecoration.none,
  );

  /// Body copy, 26 in the reference.
  static const TextStyle body = TextStyle(
    fontSize: 26,
    height: 1.42,
    fontWeight: FontWeight.w400,
    color: PsColor.textDim,
    decoration: TextDecoration.none,
  );

  static const TextStyle meta = TextStyle(
    fontSize: 26,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: PsColor.textDim,
    decoration: TextDecoration.none,
  );

  static const TextStyle label = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: PsColor.text,
    decoration: TextDecoration.none,
  );

  /// Tracked capitals that organise a screen without shouting.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 4,
    color: PsColor.text,
    decoration: TextDecoration.none,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: PsColor.textFaint,
    decoration: TextDecoration.none,
  );

  /// Small numbers that change while you watch them (timers, counters): fixed
  /// width keeps them from jittering.
  static const TextStyle numeral = TextStyle(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w400,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    color: PsColor.textDim,
    decoration: TextDecoration.none,
  );
}
