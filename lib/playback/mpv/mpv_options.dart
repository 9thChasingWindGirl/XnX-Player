/// mpv option table mirroring the mpv-Yaozhi distribution's intent: gpu-next on
/// D3D11, hardware decoding, HDR passthrough driven by the display, audio
/// bitstream passthrough in four steps, and a small set of quality profiles.
///
/// Kept free of Flutter imports so it can be unit-tested headlessly in CI.
library;

enum VideoQuality { fast, balanced, high }

enum AudioPassthrough { all, dolby, dts, off }

class MpvSettings {
  const MpvSettings({
    this.quality = VideoQuality.balanced,
    this.hwdec = 'auto-safe',
    this.hdrPassthrough = true,
    this.smoothMotion = true,
    this.audioPassthrough = AudioPassthrough.all,
    this.deband = false,
    this.volume = 80,
  });

  final VideoQuality quality;
  final String hwdec;
  final bool hdrPassthrough;
  final bool smoothMotion;
  final AudioPassthrough audioPassthrough;
  final bool deband;
  final int volume;
}

const String _spdifAll = 'ac3,eac3,dts,dts-hd,truehd';
const String _spdifDolby = 'ac3,eac3,truehd';
const String _spdifDts = 'dts,dts-hd';

String audioSpdifValue(AudioPassthrough mode) {
  switch (mode) {
    case AudioPassthrough.all:
      return _spdifAll;
    case AudioPassthrough.dolby:
      return _spdifDolby;
    case AudioPassthrough.dts:
      return _spdifDts;
    case AudioPassthrough.off:
      return '';
  }
}

Map<String, String> qualityOptions(VideoQuality quality) {
  switch (quality) {
    case VideoQuality.fast:
      return <String, String>{
        'scale': 'bilinear',
        'cscale': 'bilinear',
        'dscale': 'bilinear',
        'dither-depth': 'no',
      };
    case VideoQuality.balanced:
      return <String, String>{
        'scale': 'spline36',
        'cscale': 'spline36',
        'dscale': 'mitchell',
      };
    case VideoQuality.high:
      return <String, String>{
        'scale': 'ewa_lanczossharp',
        'cscale': 'ewa_lanczossoft',
        'dscale': 'mitchell',
        'correct-downscaling': 'yes',
        'sigmoid-upscaling': 'yes',
      };
  }
}

/// Builds the full option set applied before `mpv_initialize`.
///
/// [wid] is the native window handle mpv renders into; when null mpv opens its
/// own window (used as a fallback if the host handle cannot be resolved).
Map<String, String> buildMpvOptions({
  required String osdScriptPath,
  MpvSettings settings = const MpvSettings(),
  int? wid,
  String? watchLaterDir,
  String? screenshotDir,
}) {
  final Map<String, String> options = <String, String>{
    // Isolate from any user mpv configuration: the player owns every setting.
    'config': 'no',
    'load-scripts': 'yes',
    'osc': 'no',
    'osd-level': '0',
    'osd-bar': 'no',
    'osd-on-seek': 'no',
    'input-default-bindings': 'yes',
    'input-vo-keyboard': 'yes',
    'input-gamepad': 'no',
    'cursor-autohide': '1000',
    'idle': 'yes',
    'keep-open': 'no',
    'terminal': 'no',
    'msg-level': 'all=warn',

    // Video output: gpu-next on D3D11 is what gives the reference build its
    // HDR handling; gpu-hq supplies the peak percentile / contrast recovery
    // values the Yaozhi build relies on.
    'vo': 'gpu-next',
    'gpu-api': 'd3d11',
    'gpu-context': 'auto',
    'profile': 'gpu-hq',
    'hwdec': settings.hwdec,
    'tone-mapping': 'spline',
    'target-peak': 'auto',
    'hdr-compute-peak': 'yes',
    'deband': settings.deband ? 'yes' : 'no',
    'video-sync': settings.smoothMotion ? 'display-resample' : 'audio',
    'interpolation': settings.smoothMotion ? 'yes' : 'no',
    'tscale': 'oversample',

    // Audio
    'audio-channels': 'auto-safe',
    'audio-pitch-correction': 'yes',
    'volume': '${settings.volume}',
    'volume-max': '130',
    'audio-spdif': audioSpdifValue(settings.audioPassthrough),

    // Cache / network
    'cache': 'yes',
    'demuxer-max-bytes': '512MiB',
    'demuxer-max-back-bytes': '128MiB',
    'demuxer-readahead-secs': '60',
    'network-timeout': '30',

    // Subtitles
    'sub-auto': 'fuzzy',
    'sub-file-paths': 'subs;subtitles;字幕',
    'slang': 'chi,zh,zh-CN,zh-Hans,chs,sc,eng,en',
    'alang': 'chi,zh,zh-CN,zh-Hans,chs,sc,jpn,ja,eng,en',
    'sub-font-size': '42',
    'sub-border-size': '2.5',
    'sub-ass-override': 'no',

    // Captures
    'screenshot-format': 'png',
    'screenshot-high-bit-depth': 'yes',
    'screenshot-template': '%f-%P',
  };

  if (settings.hdrPassthrough) {
    options['target-colorspace-hint'] = 'auto';
  } else {
    options['target-colorspace-hint'] = 'no';
  }

  options.addAll(qualityOptions(settings.quality));

  if (wid != null) {
    options['wid'] = '$wid';
  }
  if (osdScriptPath.isNotEmpty) {
    options['script'] = osdScriptPath;
  }
  if (watchLaterDir != null) {
    options['watch-later-directory'] = watchLaterDir;
  }
  if (screenshotDir != null) {
    options['screenshot-directory'] = screenshotDir;
  }

  return options;
}
