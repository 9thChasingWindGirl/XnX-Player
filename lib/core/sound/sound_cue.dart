/// What happened, not which file plays.
///
/// Ported from ps5-homebrew-ui's `audio/cues.hpp`, trimmed to the cues a media
/// centre actually raises: the reference defines 43, of which 15 are interface
/// events and the remaining 28 belong to games.
///
/// The split matters. A screen asks for [SoundCue.select]; the sound set
/// decides how "select" sounds. That is what lets the whole app be re-voiced
/// later by dropping in a different folder, and it is why no widget ever names
/// a `.wav` file.
enum SoundCue {
  /// The highlight moved. Fires constantly, so it is the shortest.
  focus,

  /// Confirm.
  select,

  /// Cancel, or leave a surface.
  back,

  /// Switched tab, page or filter.
  tab,

  /// Entered a screen or opened a drawer.
  open,

  /// A dialog or the pause menu appeared.
  modalOpen,

  /// ... and went away.
  modalClose,

  /// A switch flipped.
  toggle,

  /// A slider or stepper moved one step.
  slider,

  /// Refused: edge of a list, invalid input.
  error,

  /// Toast, achievement.
  notify,

  /// Started something big.
  launch,

  /// The app (or a design) opened.
  welcome,

  /// Back into the content.
  resume,

  /// Settings stored.
  saved,
}

/// A family of recordings that belong together.
///
/// Only one ships today — `glass`, described upstream as "soft, airy, tuned
/// chimes" and used by ProsperoEden. Keeping the enum means adding `paper`
/// ("warm, wooden, tactile") later is a folder plus one line.
enum SoundSet {
  glass,
}

/// The file-name stem for a cue: `focus_01.wav` is `focus`.
String soundCueName(SoundCue cue) {
  return switch (cue) {
    SoundCue.focus => 'focus',
    SoundCue.select => 'select',
    SoundCue.back => 'back',
    SoundCue.tab => 'tab',
    SoundCue.open => 'open',
    SoundCue.modalOpen => 'modal_open',
    SoundCue.modalClose => 'modal_close',
    SoundCue.toggle => 'toggle',
    SoundCue.slider => 'slider',
    SoundCue.error => 'error',
    SoundCue.notify => 'notify',
    SoundCue.launch => 'launch',
    SoundCue.welcome => 'welcome',
    SoundCue.resume => 'resume',
    SoundCue.saved => 'saved',
  };
}

String soundSetName(SoundSet set) {
  return switch (set) {
    SoundSet.glass => 'glass',
  };
}

/// `assets/audio/sfx/glass/` — one folder per set, `<cue>_NN.wav` inside.
const String kSoundRoot = 'assets/audio/sfx';
