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
///
/// This is the *Now Playing screen* (`concepts/player.cpp:53-56`), where a
/// 46 px play button is drawn as a circle on a full-bleed stage. A transport
/// that sits in a panel, a sheet or a video overlay is a different object with
/// its own numbers — see [PsControls].
abstract final class PsTransport {
  static const double playRadius = 46;
  static const double buttonRadius = 32;

  /// Icon line weight; the kit draws every glyph from shapes at this width.
  static const double iconStroke = 3.5;

  /// Vertical position of the row inside a 1080-tall player layout.
  static const double rowY = 888;
}

/// The transport as a reusable component: `MediaControlsStyle`
/// (`src/ui/components/media_controls.hpp:60-104`).
///
/// Where [PsTransport] describes one hand-composed screen, these are the rules
/// a player overlay follows wherever it is put — the small control bar under a
/// video, a sheet's player, the compact row in the control center. They differ
/// from the Now Playing screen on purpose: 56 px buttons instead of 64 px
/// circles, a 24 px thumb instead of a bare 9 px dot, and a 10 s skip rather
/// than the 15 s shoulder jump.
abstract final class PsControls {
  /// Between the bounds and the content.
  static const double padding = 22;

  static const double buttonSize = 56;
  static const double playSize = 68;
  static const double buttonGap = 12;

  /// The scrubber: 8 tall, a 24 px thumb at full focus, `skip_seconds` 10 on
  /// the rewind/forward buttons, and a volume bar 110 wide beside the button.
  static const double trackHeight = 8;
  static const double thumbSize = 24;
  static const double volumeWidth = 110;

  /// Between the artwork square and the text column (full layout).
  static const double artGap = 24;

  static const double titleSize = 28;
  static const double artistSize = 21;
  static const double timeSize = 21; // tabular digits, as in the scrubber

  /// Rewind / forward. Distinct from `PsSeek.jump`, which is the shoulder
  /// button: 10 s is a nudge, 15 s is a jump.
  static const double skipSeconds = 10;

  /// One press on the volume button while it is being adjusted. A 5 % step is
  /// 20 presses across the range — fine enough for a quiet night, coarse
  /// enough to reach the end without holding.
  static const double volumeStep = 0.05;
}

/// Seeking. These are behavioural, not cosmetic: the same numbers must hold
/// whether the user has a controller, a keyboard or a mouse wheel.
abstract final class PsSeek {
  /// Left/right on the focused timeline.
  static const double step = 5;

  /// A page-step from anywhere: shoulder buttons, PageUp/PageDown, Shift +
  /// arrow. `player.cpp:68` (`kSeekJump`). The player's OSD must use this and
  /// not a larger number of its own — it used to jump 30 s here while every
  /// other control said 15.
  static const double jump = 15;

  /// "Previous" restarts the item when it is already past this many seconds.
  static const double restartAfter = 3;

  /// Holding a direction on the scrubber seeks further each repeat: 5 s, then
  /// ×1.3 per repeat, capped at 60 s a step (`MediaControlsStyle::seek_growth`
  /// / `seek_max`, `media_controls.hpp:96-98`). Without the cap, a long hold
  /// crosses a two-hour film in a second and a half.
  static const double growth = 1.3;
  static const double max = 60;

  /// How far a single seek step may accelerate to after `n` holds.
  static double repeated(int holds) {
    double step = PsSeek.step;
    for (int i = 0; i < holds; i++) {
      step *= growth;
      if (step >= max) {
        return max;
      }
    }
    return step;
  }
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
