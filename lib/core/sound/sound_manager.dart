import 'package:flutter/services.dart';

import 'sound_cue.dart';
import 'wave_out.dart';

/// Plays interface cues. One instance, loaded once at startup.
///
/// The sound bank is a folder per set: `assets/audio/sfx/glass/focus_01.wav`,
/// `focus_02.wav`, and so on. Variations exist so a highlight that moves
/// quickly does not sound like a machine gun; they are picked in rotation.
///
/// Nothing here knows which widget asked. Screens call
/// `SoundManager.instance.play(SoundCue.select)` and stay ignorant of files,
/// formats and devices — the same separation the reference uses, and the reason
/// a second sound set is a folder rather than a refactor.
class SoundManager {
  SoundManager._();

  static final SoundManager instance = SoundManager._();

  /// Set false to mute everything. Persisted by the settings page.
  bool enabled = true;

  /// 0..1, applied on top of each cue's own gain.
  double volume = 0.7;

  /// Shortest gap between two of the same cue. A held direction key repeats
  /// every 50 ms; without this the focus tick would smear into a buzz.
  static const Duration _minGap = Duration(milliseconds: 40);

  final Map<SoundCue, List<PcmClip>> _bank = <SoundCue, List<PcmClip>>{};
  final Map<SoundCue, int> _rotation = <SoundCue, int>{};
  final Map<SoundCue, DateTime> _lastPlayed = <SoundCue, DateTime>{};

  bool _loaded = false;

  bool get isAvailable => _loaded && WaveOut.instance.isAvailable;

  /// Reads the bank off the asset bundle. Safe to call twice.
  ///
  /// Missing files are not an error: a set that does not record a cue simply
  /// stays silent for it, which is how the reference handles partial sets too.
  Future<void> load({SoundSet set = SoundSet.glass}) async {
    if (_loaded) {
      return;
    }
    _loaded = true;

    for (final SoundCue cue in SoundCue.values) {
      final String stem = soundCueName(cue);
      final List<PcmClip> clips = <PcmClip>[];
      for (int i = 1; i <= 3; i++) {
        final String number = i.toString().padLeft(2, '0');
        final String path = '$kSoundRoot/${soundSetName(set)}/${stem}_$number.wav';
        try {
          final ByteData data = await rootBundle.load(path);
          final PcmClip? clip = PcmClip.decode(data.buffer.asUint8List());
          if (clip != null) {
            clips.add(clip);
          }
        } on Object {
          // No variation with this number; stop after the first gap.
          break;
        }
      }
      if (clips.isNotEmpty) {
        _bank[cue] = clips;
      }
    }
  }

  /// Plays [cue], unless muted, not loaded, or the same cue fired within the
  /// last 40 ms.
  void play(SoundCue cue, {double gain = 1.0}) {
    if (!enabled || volume <= 0 || !isAvailable) {
      return;
    }
    final List<PcmClip>? clips = _bank[cue];
    if (clips == null || clips.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? last = _lastPlayed[cue];
    if (last != null && now.difference(last) < _minGap) {
      return;
    }
    _lastPlayed[cue] = now;

    final int index = (_rotation[cue] ?? 0) % clips.length;
    _rotation[cue] = index + 1;
    WaveOut.instance.play(clips[index], gain: (volume * gain).clamp(0.0, 1.0));
  }

  void dispose() {
    _bank.clear();
    WaveOut.instance.dispose();
    _loaded = false;
  }
}
