/// Media-center tokens: the part the reference kit does not cover.
///
/// The kit is a console UI toolkit plus a *music* player. A home media center
/// adds a video timeline, transport controls, a detail sheet with credits and a
/// queue — none of which exist upstream in a form we can transcribe. The values
/// here are lifted from the two closest reference designs instead of being
/// invented:
///
/// * `concepts/player.cpp` — the "Now Playing" design: scrubber, transport row,
///   frosted queue. Geometry at lines 53-82, scrubber drawing at 1018-1066.
/// * `concepts/aurora.cpp` — the home screen's detail sheet: lines 511-533.
/// * `concepts/aurora.cpp` — shelf and card geometry: lines 41-47 (already in
///   `ps_tokens.dart`, repeated here only where a video layout needs it).
///
/// Everything is a compile-time constant with no dependency, so the component
/// work in the roadmap's Phase 2/3 has one place to read the numbers from.
/// `docs/DESIGN_TOKENS.md` §5 explains each block.
library;

/// The video timeline. A media center's scrubber is the one control the player
/// touches most, so it has the most states: resting, focused, being dragged.
abstract final class PsScrubber {
  static const double trackRest = 8;
  static const double trackFocus = 12;

  static const double trackAlphaRest = 0.16;
  static const double trackAlphaFocus = 0.22;

  /// Glow under the played portion, in the accent colour.
  static const double glowBlurRest = 10;
  static const double glowBlurFocus = 18;
  static const double glowAlphaRest = 0.22;
  static const double glowAlphaFocus = 0.42;

  /// The thumb grows twice: once for focus, once more while dragging.
  static const double thumbRest = 9;
  static const double thumbFocus = 15;
  static const double thumbSeeking = 18;
  static const double thumbShadowAlpha = 0.45;
  static const double thumbShadowBlur = 10;
  static const double thumbShadowOffsetY = 4;

  /// Elapsed and total time, in the monospaced numeral style.
  static const double timeSize = 22;
  static const double timeOffsetY = 46;
  static const double timeCurrentAlpha = 0.86;
  static const double timeTotalAlpha = 0.60;

  /// The time bubble that rides above the thumb while dragging.
  static const double bubbleWidth = 88;
  static const double bubbleHeight = 36;
  static const double bubbleRadius = 18;
  static const double bubbleOffsetY = 66;
  static const double bubbleShadowBlur = 14;

  /// The bubble is clamped inside the track by this much, so it never half
  /// leaves the safe area at either end.
  static const double bubbleEdgeInset = 44;
}

/// Transport row: play/pause in the middle, the smaller controls around it.
abstract final class PsTransport {
  static const double playRadius = 46;
  static const double buttonRadius = 32;

  /// Icon line weight; the kit draws every glyph from shapes at this width.
  static const double iconStroke = 3.5;

  /// Vertical position of the row inside a 1080-tall player layout.
  static const double rowY = 888;
}

/// Seeking. These are behavioural, not cosmetic: the same numbers must hold
/// whether the user has a controller, a keyboard or a mouse wheel.
abstract final class PsSeek {
  /// Left/right on the focused timeline.
  static const double step = 5;

  /// A page-step from anywhere: shoulder buttons, PageUp/PageDown.
  static const double jump = 15;

  /// "Previous" restarts the item when it is already past this many seconds.
  static const double restartAfter = 3;
}

/// The detail sheet: artwork, eyebrow, title, two lines of synopsis, then the
/// facts row. Sits over the hero at the bottom of a 1080-tall screen.
abstract final class PsDetail {
  static const double width = 1680;
  static const double height = 500;
  static const double radius = 44;
  static const double pad = 56;

  static const double artSize = 300;
  static const double artRadius = 28;

  /// The blurred copy of the scene is tinted with the artwork's dark tone.
  static const double tintAlpha = 0.62;

  /// The one-pixel-of-light edge that makes a glass panel read as glass.
  static const double edgeWidth = 1.5;
  static const double edgeAlpha = 0.22;

  static const double eyebrowSize = 20;
  static const double eyebrowTracking = 4;
  static const double titleSize = 60;
  static const double bodySize = 25;
  static const double bodyLineHeight = 36;
  static const int bodyLines = 2;
}

/// The playback queue: real glass over the scene, sliding in from the right.
abstract final class PsQueue {
  static const double width = 420;
  static const double height = 856;
  static const double radius = 36;

  /// 96 from the right edge, matching the safe margin: 1920 - 96 - 420 = 1404.
  static const double top = 96;
  static const double headerToFirstRow = 104;
  static const double rowHeight = 66;
}
