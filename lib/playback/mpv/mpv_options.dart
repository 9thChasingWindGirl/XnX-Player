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
    // Off by default, like the reference build: interpolation plus
    // display-resample needs a spare GPU and a working audio clock, and when
    // either is missing the picture stalls on its first frame. Opt-in.
    this.smoothMotion = false,
    this.audioPassthrough = AudioPassthrough.off,
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
        // Plain ewa_lanczos: the gpu-next backend has no libplacebo analog for
        // `ewa_lanczossoft` and logs a mapping failure for it.
        'cscale': 'ewa_lanczos',
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
///
/// The OSD Lua is deliberately *not* passed as `script=`: a missing or wrong
/// path there is silent, and the result is a player with no UI. The app loads
/// it with `load-script` after init and checks `script-list`.
Map<String, String> buildMpvOptions({
  MpvSettings settings = const MpvSettings(),
  int? wid,
  String? logFile,
  String? watchLaterDir,
  String? screenshotDir,
}) {
  final Map<String, String> options = <String, String>{
    // Isolate from any user mpv configuration: the player owns every setting.
    'config': 'no',
    'load-scripts': 'yes',
    'osc': 'no',
    'osd-level': '1',
    'osd-bar': 'no',
    'osd-on-seek': 'no',
    // Keys are handled by Flutter (and by our Lua OSD), so mpv's built-in
    // bindings must not fight the focus engine for arrows and space.
    'input-default-bindings': 'no',
    'input-vo-keyboard': 'yes',
    'input-gamepad': 'no',
    'cursor-autohide': '1000',
    'idle': 'yes',
    // keep-open keeps the last frame and the video window alive after EOF;
    // without it the surface is torn down and the app flashes black.
    'keep-open': 'yes',
    // force-window=immediate creates the child window before the first frame,
    // which is what lets the host measure and fit it immediately.
    'force-window': 'immediate',
    'terminal': 'no',
    'msg-level': 'all=info',
    // The app owns resume state (`AppStore.remember`), so mpv must not also
    // write watch-later files and race with it.
    'save-position-on-quit': 'no',

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
    'audio-device': 'auto',
    'audio-channels': 'auto-safe',
    'audio-pitch-correction': 'yes',
    'volume': '${settings.volume}',
    'volume-max': '130',
    'audio-spdif': audioSpdifValue(settings.audioPassthrough),
    'audio-file-auto': 'fuzzy',

    // Cache / network
    'cache': 'yes',
    'demuxer-max-bytes': '512MiB',
    'demuxer-max-back-bytes': '128MiB',
    'demuxer-readahead-secs': '60',
    'network-timeout': '30',
    // Mirrors the reference build: streamed pages still go through yt-dlp when
    // it is available; without it mpv simply plays the direct URL.
    'ytdl': 'yes',
    'ytdl-format': 'bestvideo+bestaudio/best',

    // Subtitles
    'sub-auto': 'fuzzy',
    'sub-file-paths': 'subs;subtitles;字幕',
    'slang': 'chi,zh,zh-CN,zh-Hans,chs,sc,eng,en',
    'alang': 'chi,zh,zh-CN,zh-Hans,chs,sc,jpn,ja,eng,en',
    'sub-font-size': '42',
    'sub-border-size': '2.5',
    'sub-shadow-offset': '1',
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
  if (logFile != null) {
    options['log-file'] = logFile;
  }
  if (watchLaterDir != null) {
    options['watch-later-directory'] = watchLaterDir;
  }
  if (screenshotDir != null) {
    options['screenshot-directory'] = screenshotDir;
  }

  return options;
}
