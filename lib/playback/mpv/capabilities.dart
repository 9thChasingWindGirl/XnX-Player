/// Decisions about what the machine in front of us can actually do.
///
/// The previous build switched features on and hoped: bitstream passthrough,
/// HDR output and hardware decoding were all requested blindly, so a refusal
/// from the driver looked like a broken player. These helpers keep the decision
/// out of the widget layer so it can be unit-tested, and so the answer the
/// player reached can be shown to the user instead of living in a log.
library;

/// Audio devices that can carry a bitstream or a multichannel PCM stream.
///
/// WASAPI passthrough needs an endpoint that accepts compressed formats, which
/// in practice means HDMI/DisplayPort into a receiver or TV — a laptop's
/// speakers or a USB headset will refuse it and take the whole audio chain down
/// with them.
const List<String> _bitstreamDevices = <String>[
  'hdmi',
  'displayport',
  'display port',
  'spdif',
  's/pdif',
  'optical',
  'nvidia high definition audio',
  'amd high definition audio',
  'intel(r) display audio',
  'receiver',
  'avr',
  'home theater',
  '家庭影院',
  '功放',
];

bool deviceSupportsBitstream(String? deviceName) {
  final String name = (deviceName ?? '').toLowerCase();
  if (name.isEmpty) {
    return false;
  }
  return _bitstreamDevices.any(name.contains);
}

/// Whether mpv is currently rendering an HDR signal rather than tone mapping
/// into SDR.
///
/// `video-out-params` is what the video output settled on, so this is the only
/// reliable answer to "did HDR passthrough actually happen" — the source
/// colours alone say nothing about the display.
bool isHdrOutput(String? primaries, String? gamma) {
  final String p = (primaries ?? '').toLowerCase();
  final String g = (gamma ?? '').toLowerCase();
  return p.contains('bt.2020') && (g == 'pq' || g == 'hlg');
}

/// Whether an audio format is a compressed bitstream that only appears when the
/// endpoint really accepted passthrough.
///
/// `audio-out-params/format` is the ground truth: asking WASAPI for Dolby
/// passthrough and getting back `float` means it refused and mpv decoded.
bool isBitstreamFormat(String? format) {
  final String f = (format ?? '').toLowerCase();
  if (f.isEmpty) {
    return false;
  }
  const List<String> bitstreams = <String>[
    'ac3',
    'eac3',
    'ac-3',
    'truehd',
    'mlp',
    'dts',
    'atmos',
  ];
  return bitstreams.any(f.contains);
}

/// True when the source carries an HDR or Dolby Vision transfer.
bool isHdrSource(String? gamma) {
  final String g = (gamma ?? '').toLowerCase();
  return g == 'pq' || g == 'hlg';
}

/// Dolby Vision profile 8 keeps an HDR10 base layer, so it plays as HDR10 with
/// the RPU refining it. Profile 5 is IPTPQc2 and only looks right when the
/// dynamic metadata is applied — mpv/libplacebo does that on `gpu-next`, but
/// not on plain `gpu`.
bool dolbyVisionNeedsGpuNext(String? primaries) =>
    (primaries ?? '').toLowerCase().contains('dolbyvision');

/// Human-readable summary of the decode path, for the diagnostics panel.
String describeHwdec(String? current, String? requested) {
  if (current != null && current.isNotEmpty && current != 'no') {
    return current;
  }
  if (requested == 'no') {
    return '软件解码（已在设置里关闭硬件解码）';
  }
  return '软件解码（硬解未能启用，已自动回退）';
}
