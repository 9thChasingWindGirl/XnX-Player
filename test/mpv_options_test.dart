import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/playback/mpv/mpv_options.dart';

void main() {
  group('buildMpvOptions', () {
    test('renders into the host window when wid is provided', () {
      final Map<String, String> options = buildMpvOptions(wid: 0x1A2B3C);

      expect(options['wid'], '${0x1A2B3C}');
      // The OSD is loaded with `load-script` after init so the app can verify
      // it; asking mpv to load it by path here would hide a wrong path.
      expect(options.containsKey('script'), isFalse);
      expect(options['vo'], 'gpu-next');
      expect(options['gpu-api'], 'd3d11');
      expect(options['hwdec'], 'auto-safe');
    });

    test('falls back to an own window when wid is unknown', () {
      final Map<String, String> options = buildMpvOptions();
      expect(options.containsKey('wid'), isFalse);
      expect(options.containsKey('script'), isFalse);
    });

    test('keeps the reference build HDR defaults', () {
      final Map<String, String> options = buildMpvOptions();
      expect(options['profile'], 'gpu-hq');
      expect(options['target-colorspace-hint'], 'auto');
      expect(options['hdr-compute-peak'], 'yes');
      expect(options['tone-mapping'], 'spline');
    });

    test('does not force bitstream passthrough by default', () {
      // Passthrough needs WASAPI exclusive mode, and a refused request takes
      // out the audio device entirely ("Failed to initialize audio driver
      // 'wasapi'"). Decoding everything is the safe default.
      final Map<String, String> options = buildMpvOptions();
      expect(options['audio-spdif'], '');
      expect(options['audio-device'], 'auto');
    });

    test('disables HDR passthrough on request', () {
      final Map<String, String> options = buildMpvOptions(
        settings: const MpvSettings(hdrPassthrough: false),
      );
      expect(options['target-colorspace-hint'], 'no');
    });

    test('applies the chosen quality profile without duplicate keys', () {
      final Map<String, String> fast = buildMpvOptions(
        settings: const MpvSettings(quality: VideoQuality.fast),
      );
      expect(fast['scale'], 'bilinear');

      final Map<String, String> high = buildMpvOptions(
        settings: const MpvSettings(quality: VideoQuality.high),
      );
      expect(high['scale'], 'ewa_lanczossharp');
    });

    test('never leaves duplicate options for the same key', () {
      final Map<String, String> options = buildMpvOptions();
      expect(options.keys.toSet().length, options.length);
    });
  });

  group('audio passthrough', () {
    test('maps the four steps the menu exposes', () {
      expect(audioSpdifValue(AudioPassthrough.all), 'ac3,eac3,dts,dts-hd,truehd');
      expect(audioSpdifValue(AudioPassthrough.dolby), 'ac3,eac3,truehd');
      expect(audioSpdifValue(AudioPassthrough.dts), 'dts,dts-hd');
      expect(audioSpdifValue(AudioPassthrough.off), '');
    });
  });
}
