import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/playback/mpv/capabilities.dart';

void main() {
  group('bitstream capability', () {
    test('accepts HDMI and receiver endpoints', () {
      expect(deviceSupportsBitstream('扬声器 (NVIDIA High Definition Audio)'), isTrue);
      expect(deviceSupportsBitstream('AMD High Definition Audio Device'), isTrue);
      expect(deviceSupportsBitstream('Realtek Digital Output (Optical)'), isTrue);
      expect(deviceSupportsBitstream('DENON AVR-X1600H (HDMI)'), isTrue);
    });

    test('rejects endpoints that cannot carry a bitstream', () {
      expect(deviceSupportsBitstream('扬声器 (Nahimic Easy Surround Device)'), isFalse);
      expect(deviceSupportsBitstream('Headphones (Realtek(R) Audio)'), isFalse);
      expect(deviceSupportsBitstream(null), isFalse);
      expect(deviceSupportsBitstream(''), isFalse);
    });
  });

  group('HDR detection', () {
    test('sees passthrough only when the output is PQ/HDR', () {
      expect(isHdrOutput('bt.2020', 'pq'), isTrue);
      expect(isHdrOutput('bt.2020', 'hlg'), isTrue);
      // Tone mapped into SDR: the source may be HDR, the output is not.
      expect(isHdrOutput('bt.709', 'srgb'), isFalse);
      expect(isHdrOutput('bt.2020', 'srgb'), isFalse);
      expect(isHdrOutput(null, null), isFalse);
    });

    test('recognises an HDR or Dolby Vision source', () {
      expect(isHdrSource('pq'), isTrue);
      expect(isHdrSource('hlg'), isTrue);
      expect(isHdrSource('bt.1886'), isFalse);
      expect(dolbyVisionNeedsGpuNext('dolbyvision'), isTrue);
      expect(dolbyVisionNeedsGpuNext('bt.2020'), isFalse);
    });
  });

  group('hwdec summary', () {
    test('reports the active hardware decoder', () {
      expect(describeHwdec('d3d11va', 'auto-safe'), 'd3d11va');
    });

    test('explains a software fallback', () {
      expect(describeHwdec('', 'auto-safe'), contains('硬解未能启用'));
      expect(describeHwdec(null, 'no'), contains('设置里关闭'));
    });
  });
}
