import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/playback/mpv/hw_profile.dart';
import 'package:xnx_player/playback/mpv/mpv_options.dart';

void main() {
  test('unknown profile keeps passthrough off no matter what was asked', () {
    expect(
      initialPassthrough(null, AudioPassthrough.all),
      AudioPassthrough.off,
    );
  });

  test('profile that failed the bitstream test keeps passthrough off', () {
    const HardwareProfile profile = HardwareProfile(
      audioDeviceName: 'speakers',
      bitstreamCapable: false,
      hdrDisplay: false,
    );
    expect(
      initialPassthrough(profile, AudioPassthrough.all),
      AudioPassthrough.off,
    );
  });

  test('proven bitstream endpoint enables the requested mode at start', () {
    const HardwareProfile profile = HardwareProfile(
      audioDeviceName: 'HDMI Output (AVR)',
      bitstreamCapable: true,
      hdrDisplay: true,
    );
    expect(
      initialPassthrough(profile, AudioPassthrough.dolby),
      AudioPassthrough.dolby,
    );
  });

  test('HDR request is suppressed on a display the probe saw as SDR-only', () {
    const HardwareProfile profile = HardwareProfile(
      audioDeviceName: 'speakers',
      bitstreamCapable: false,
      hdrDisplay: false,
    );
    expect(initialHdrPassthrough(profile, true), isFalse);
  });

  test('HDR request survives an unknown or HDR-capable display', () {
    const HardwareProfile hdr = HardwareProfile(
      audioDeviceName: 'HDMI Output',
      bitstreamCapable: true,
      hdrDisplay: true,
    );
    expect(initialHdrPassthrough(null, true), isTrue);
    expect(initialHdrPassthrough(hdr, true), isTrue);
    expect(initialHdrPassthrough(null, false), isFalse);
  });

  test('probe without a passthrough request falls back to the endpoint name', () {
    final HardwareProfile speakers = profileFromProbe(
      audioDeviceName: '扬声器 (Nahimic Easy Surround Device)',
      passthroughRequested: false,
      passthroughLive: false,
      hdrOutput: false,
      nowMs: 1000,
    );
    expect(speakers.bitstreamCapable, isFalse);

    final HardwareProfile avr = profileFromProbe(
      audioDeviceName: 'HDMI Output (AVR)',
      passthroughRequested: false,
      passthroughLive: false,
      hdrOutput: true,
      nowMs: 1000,
    );
    expect(avr.bitstreamCapable, isTrue);
    expect(avr.hdrDisplay, isTrue);
  });

  test('probe with a live passthrough records the honest answer', () {
    final HardwareProfile refused = profileFromProbe(
      audioDeviceName: 'HDMI Output (AVR)',
      passthroughRequested: true,
      passthroughLive: false,
      hdrOutput: false,
      nowMs: 1000,
    );
    expect(refused.bitstreamCapable, isFalse);

    final HardwareProfile accepted = profileFromProbe(
      audioDeviceName: 'HDMI Output (AVR)',
      passthroughRequested: true,
      passthroughLive: true,
      hdrOutput: true,
      nowMs: 1000,
    );
    expect(accepted.bitstreamCapable, isTrue);
  });

  test('profile round-trips through JSON', () {
    const HardwareProfile profile = HardwareProfile(
      audioDeviceName: 'HDMI Output (AVR)',
      bitstreamCapable: true,
      hdrDisplay: true,
      savedAt: 42,
    );
    final HardwareProfile restored = HardwareProfile.fromJson(profile.toJson());
    expect(restored.audioDeviceName, profile.audioDeviceName);
    expect(restored.bitstreamCapable, profile.bitstreamCapable);
    expect(restored.hdrDisplay, profile.hdrDisplay);
    expect(restored.savedAt, profile.savedAt);
  });
}
