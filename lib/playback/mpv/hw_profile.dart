/// A persisted snapshot of what this machine's display and audio endpoints can
/// actually do, mirroring the "identify the hardware once, reuse the answer"
/// pattern of the reference player's config assistant.
///
/// The probe (`_probeCapabilities` in the player page) learns the truth from
/// live mpv properties; this file only holds the persisted facts and the two
/// startup decisions derived from them, as pure functions so CI can unit-test
/// them headlessly.
library;

import 'capabilities.dart';
import 'mpv_options.dart';

class HardwareProfile {
  const HardwareProfile({
    this.audioDeviceName = '',
    this.bitstreamCapable = false,
    this.hdrDisplay = false,
    this.savedAt = 0,
  });

  factory HardwareProfile.fromJson(Map<String, dynamic> json) {
    return HardwareProfile(
      audioDeviceName: json['audioDeviceName'] as String? ?? '',
      bitstreamCapable: json['bitstreamCapable'] as bool? ?? false,
      hdrDisplay: json['hdrDisplay'] as bool? ?? false,
      savedAt: json['savedAt'] as int? ?? 0,
    );
  }

  final String audioDeviceName;
  final bool bitstreamCapable;
  final bool hdrDisplay;
  final int savedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'audioDeviceName': audioDeviceName,
        'bitstreamCapable': bitstreamCapable,
        'hdrDisplay': hdrDisplay,
        'savedAt': savedAt,
      };
}

/// What the initial `audio-spdif` option should be at player start.
///
/// Only enable passthrough at init when a previous session proved this exact
/// endpoint accepts a bitstream. Unknown hardware starts with it off and lets
/// the runtime probe re-enable it — a blind request costs the whole audio
/// chain on endpoints that refuse exclusive mode.
AudioPassthrough initialPassthrough(HardwareProfile? profile, AudioPassthrough wanted) {
  if (profile == null || !profile.bitstreamCapable) {
    return AudioPassthrough.off;
  }
  return wanted;
}

/// What the initial HDR handling should be at player start.
///
/// A persisted probe that saw an SDR-only display keeps the player from
/// requesting HDR output it can only tone map anyway; unknown displays keep
/// the user's setting.
bool initialHdrPassthrough(HardwareProfile? profile, bool wanted) {
  if (profile == null || profile.hdrDisplay) {
    return wanted;
  }
  return false;
}

/// Builds the profile to persist after a probe pass.
///
/// When the user asked for passthrough, [passthroughLive] (a bitstream format
/// in `audio-out-params/format`) is the only honest answer. When they did not,
/// fall back to the endpoint-name heuristic so the profile still has signal.
HardwareProfile profileFromProbe({
  String? audioDeviceName,
  required bool passthroughRequested,
  required bool passthroughLive,
  required bool hdrOutput,
  required int nowMs,
}) {
  return HardwareProfile(
    audioDeviceName: audioDeviceName ?? '',
    bitstreamCapable:
        passthroughRequested ? passthroughLive : deviceSupportsBitstream(audioDeviceName),
    hdrDisplay: hdrOutput,
    savedAt: nowMs,
  );
}
