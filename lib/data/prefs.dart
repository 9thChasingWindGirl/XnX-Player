/// Playback preferences, persisted with the rest of the app state.
///
/// These are the knobs the reference player exposes in its function menu:
/// quality tier, HDR passthrough, motion smoothing, audio passthrough and
/// subtitle size. They map 1:1 onto mpv options in `mpv_options.dart`.
enum QualityPref { fast, balanced, high }

enum PassthroughPref { all, dolby, dts, off }

class PlaybackPrefs {
  const PlaybackPrefs({
    this.quality = QualityPref.balanced,
    // Bitstream passthrough needs a receiver that accepts the format and an
    // exclusive-mode audio device. Forcing it by default made WASAPI fail to
    // initialise on ordinary desktop outputs, which costs all audio, so it is
    // opt-in from 设置 → 播放.
    this.passthrough = PassthroughPref.off,
    this.hdrPassthrough = true,
    // Off by default: interpolation + display-resample needs a spare GPU and a
    // live audio clock to work, and costs frames when either is missing.
    this.smoothMotion = false,
    this.volume = 80,
    this.deband = false,
    this.reduceMotion = false,
    this.subtitleSize = 42,
    this.skipIntro = false,
    this.hardwareDecoding = true,
    // Off by default: dropping straight into fullscreen on every play is
    // jarring when the user only wanted a window, and there was previously no
    // way back out except leaving the player entirely.
    this.startFullscreen = false,
    // Interface cues: on by default at a level that sits under the content.
    this.soundEnabled = true,
    this.soundVolume = 70,
  });

  final QualityPref quality;
  final PassthroughPref passthrough;
  final bool hdrPassthrough;
  final bool smoothMotion;
  final int volume;
  final bool deband;
  final bool reduceMotion;
  final int subtitleSize;
  final bool skipIntro;
  final bool hardwareDecoding;
  final bool startFullscreen;

  /// Interface sound effects (`lib/core/sound`). Separate from [volume], which
  /// is the video's own level.
  final bool soundEnabled;
  final int soundVolume;

  PlaybackPrefs copyWith({
    QualityPref? quality,
    PassthroughPref? passthrough,
    bool? hdrPassthrough,
    bool? smoothMotion,
    int? volume,
    bool? deband,
    bool? reduceMotion,
    int? subtitleSize,
    bool? skipIntro,
    bool? hardwareDecoding,
    bool? startFullscreen,
    bool? soundEnabled,
    int? soundVolume,
  }) {
    return PlaybackPrefs(
      quality: quality ?? this.quality,
      passthrough: passthrough ?? this.passthrough,
      hdrPassthrough: hdrPassthrough ?? this.hdrPassthrough,
      smoothMotion: smoothMotion ?? this.smoothMotion,
      volume: volume ?? this.volume,
      deband: deband ?? this.deband,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      subtitleSize: subtitleSize ?? this.subtitleSize,
      skipIntro: skipIntro ?? this.skipIntro,
      startFullscreen: startFullscreen ?? this.startFullscreen,
      hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      soundVolume: soundVolume ?? this.soundVolume,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'quality': quality.name,
        'passthrough': passthrough.name,
        'hdrPassthrough': hdrPassthrough,
        'smoothMotion': smoothMotion,
        'volume': volume,
        'deband': deband,
        'reduceMotion': reduceMotion,
        'subtitleSize': subtitleSize,
        'skipIntro': skipIntro,
        'startFullscreen': startFullscreen,
        'hardwareDecoding': hardwareDecoding,
        'soundEnabled': soundEnabled,
        'soundVolume': soundVolume,
      };

  static PlaybackPrefs fromJson(Map<String, dynamic> json) {
    return PlaybackPrefs(
      quality: QualityPref.values.firstWhere(
        (QualityPref value) => value.name == json['quality'],
        orElse: () => QualityPref.balanced,
      ),
      passthrough: PassthroughPref.values.firstWhere(
        (PassthroughPref value) => value.name == json['passthrough'],
        orElse: () => PassthroughPref.off,
      ),
      hdrPassthrough: json['hdrPassthrough'] as bool? ?? true,
      smoothMotion: json['smoothMotion'] as bool? ?? true,
      volume: (json['volume'] as num?)?.toInt() ?? 80,
      deband: json['deband'] as bool? ?? false,
      reduceMotion: json['reduceMotion'] as bool? ?? false,
      subtitleSize: (json['subtitleSize'] as num?)?.toInt() ?? 42,
      skipIntro: json['skipIntro'] as bool? ?? false,
      startFullscreen: json['startFullscreen'] as bool? ?? false,
      hardwareDecoding: json['hardwareDecoding'] as bool? ?? true,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      soundVolume: (json['soundVolume'] as num?)?.toInt() ?? 70,
    );
  }

  String get qualityLabel => switch (quality) {
        QualityPref.fast => '流畅',
        QualityPref.balanced => '均衡',
        QualityPref.high => '高质量',
      };

  String get passthroughLabel => switch (passthrough) {
        PassthroughPref.all => '全部直通',
        PassthroughPref.dolby => '仅 Dolby',
        PassthroughPref.dts => '仅 DTS',
        PassthroughPref.off => '关闭',
      };
}
