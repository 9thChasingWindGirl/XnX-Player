import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Minimal Windows audio out, built on `winmm`'s waveOut API.
///
/// Why not a package: this project has no audio dependency and does not want
/// one for fifteen 35–300 ms UI chimes, and why not `PlaySound`: it owns a
/// single channel, so a moving highlight would cut itself off instead of
/// layering. A small pool of waveOut voices is the smallest thing that behaves
/// like a UI.
///
/// The whole class disables itself if anything about the platform does not
/// match what it expects (struct layout, device open failure). That is
/// deliberate: a media player that cannot beep is a nuisance, a media player
/// that segfaults on startup is not shippable.

final class _WaveFormatEx extends Struct {
  @Uint16()
  external int wFormatTag;
  @Uint16()
  external int nChannels;
  @Uint32()
  external int nSamplesPerSec;
  @Uint32()
  external int nAvgBytesPerSec;
  @Uint16()
  external int nBlockAlign;
  @Uint16()
  external int wBitsPerSample;
  @Uint16()
  external int cbSize;
}

/// x64 layout is 48 bytes: lpData(8) lengths(8) user(8) flags(8) next(8)
/// reserved(8). Verified at runtime instead of assumed.
final class _WaveHdr extends Struct {
  external Pointer<Uint8> lpData;
  @Uint32()
  external int dwBufferLength;
  @Uint32()
  external int dwBytesRecorded;
  @UintPtr()
  external int dwUser;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwLoops;
  external Pointer<_WaveHdr> lpNext;
  @UintPtr()
  external int reserved;
}

typedef _OpenNative = Int32 Function(
    Pointer<IntPtr> handle, Uint32 device, Pointer<_WaveFormatEx> format,
    IntPtr callback, IntPtr instance, Uint32 flags);
typedef _OpenDart = int Function(
    Pointer<IntPtr> handle, int device, Pointer<_WaveFormatEx> format,
    int callback, int instance, int flags);

typedef _HeaderNative = Int32 Function(IntPtr handle, Pointer<_WaveHdr> header, Uint32 size);
typedef _HeaderDart = int Function(int handle, Pointer<_WaveHdr> header, int size);

typedef _HandleNative = Int32 Function(IntPtr handle);
typedef _HandleDart = int Function(int handle);

typedef _VolumeNative = Int32 Function(IntPtr handle, Uint32 volume);
typedef _VolumeDart = int Function(int handle, int volume);

/// Pre-decoded PCM: the bytes are ready to hand to the device untouched.
class PcmClip {
  const PcmClip({
    required this.bytes,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });

  final Uint8List bytes;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  /// Parses a RIFF/WAVE file. Returns null for anything it cannot play
  /// losslessly — the reference set is 48 kHz mono PCM16, and guessing at
  /// compressed audio here would be worse than silence.
  static PcmClip? decode(Uint8List file) {
    if (file.length < 12) {
      return null;
    }
    final ByteData view = ByteData.sublistView(file);
    if (view.getUint32(0, Endian.little) != 0x46464952) {
      return null; // 'RIFF'
    }
    if (view.getUint32(8, Endian.little) != 0x45564157) {
      return null; // 'WAVE'
    }

    int channels = 0;
    int rate = 0;
    int bits = 0;
    int format = 0;
    int? dataStart;
    int dataLength = 0;

    int offset = 12;
    while (offset + 8 <= file.length) {
      final int id = view.getUint32(offset, Endian.little);
      final int size = view.getUint32(offset + 4, Endian.little);
      final int body = offset + 8;
      if (body + size > file.length) {
        break;
      }
      if (id == 0x20746D66) {
        // 'fmt '
        format = view.getUint16(body, Endian.little);
        channels = view.getUint16(body + 2, Endian.little);
        rate = view.getUint32(body + 4, Endian.little);
        bits = view.getUint16(body + 14, Endian.little);
      } else if (id == 0x61746164) {
        // 'data'
        dataStart = body;
        dataLength = size;
      }
      offset = body + size + (size.isOdd ? 1 : 0);
    }

    if (dataStart == null || channels <= 0 || rate <= 0 || bits <= 0) {
      return null;
    }
    // 1 = PCM, 3 = IEEE float; waveOut plays PCM without a codec.
    if (format != 1) {
      return null;
    }
    return PcmClip(
      bytes: Uint8List.sublistView(file, dataStart, dataStart + dataLength),
      sampleRate: rate,
      channels: channels,
      bitsPerSample: bits,
    );
  }
}

/// One device voice: a handle, a reusable header and a buffer that grows to the
/// largest clip it has been asked to play.
class _Voice {
  _Voice(this.handle, this.header, this.capacity, this.sampleRate, this.channels, this.bits);

  final int handle;
  final Pointer<_WaveHdr> header;
  Pointer<Uint8> buffer;
  int capacity;

  /// The format the device was opened with. A voice can only play clips that
  /// match it.
  final int sampleRate;
  final int channels;
  final int bits;

  bool get isOpen => handle != 0;

  bool matches(PcmClip clip) =>
      sampleRate == clip.sampleRate && channels == clip.channels && bits == clip.bitsPerSample;
}

class WaveOut {
  WaveOut._() {
    _ready = _openLibrary();
  }

  static final WaveOut instance = WaveOut._();

  /// Six voices: enough for a focus tick plus a confirm plus a toast without
  /// cutting anything off, small enough that the device opens instantly.
  static const int _voiceCount = 6;

  DynamicLibrary? _lib;
  _OpenDart? _waveOutOpen;
  _HeaderDart? _waveOutPrepare;
  _HeaderDart? _waveOutUnprepare;
  _HeaderDart? _waveOutWrite;
  _HandleDart? _waveOutReset;
  _HandleDart? _waveOutClose;
  _VolumeDart? _waveOutSetVolume;

  final List<_Voice> _voices = <_Voice>[];
  int _cursor = 0;
  bool _ready = false;

  bool get isAvailable => _ready;

  bool _openLibrary() {
    if (!Platform.isWindows) {
      return false;
    }
    // waveOut insists on a 48-byte header on x64; if this Dart build lays the
    // struct out differently, writing through it would corrupt memory.
    if (sizeOf<_WaveHdr>() != 48) {
      return false;
    }
    try {
      final DynamicLibrary lib = DynamicLibrary.open('winmm.dll');
      _waveOutOpen = lib.lookupFunction<_OpenNative, _OpenDart>('waveOutOpen');
      _waveOutPrepare = lib.lookupFunction<_HeaderNative, _HeaderDart>('waveOutPrepareHeader');
      _waveOutUnprepare =
          lib.lookupFunction<_HeaderNative, _HeaderDart>('waveOutUnprepareHeader');
      _waveOutWrite = lib.lookupFunction<_HeaderNative, _HeaderDart>('waveOutWrite');
      _waveOutReset = lib.lookupFunction<_HandleNative, _HandleDart>('waveOutReset');
      _waveOutClose = lib.lookupFunction<_HandleNative, _HandleDart>('waveOutClose');
      _waveOutSetVolume = lib.lookupFunction<_VolumeNative, _VolumeDart>('waveOutSetVolume');
      _lib = lib;
      return true;
    } on Object {
      return false;
    }
  }

  /// Plays [clip] on the next free voice, stealing the least recently used one
  /// when all six are busy. UI sound effects are short; a stolen chime is
  /// better than a queue that falls behind the highlight.
  void play(PcmClip clip, {double gain = 1.0}) {
    if (!_ready || clip.bytes.isEmpty) {
      return;
    }
    final _Voice? voice = _nextVoice(clip);
    if (voice == null) {
      return;
    }

    final _HeaderDart? reset = _waveOutReset;
    final _HeaderDart? write = _waveOutWrite;
    final _HeaderDart? prepare = _waveOutPrepare;
    if (reset == null || write == null || prepare == null) {
      return;
    }

    // Stop whatever this voice was doing before overwriting its buffer.
    reset(voice.handle);

    voice.buffer.asTypedList(clip.bytes.length).setAll(0, clip.bytes);
    voice.header.ref.dwBufferLength = clip.bytes.length;
    prepare(voice.handle, voice.header, sizeOf<_WaveHdr>());
    _applyGain(voice, gain);
    write(voice.handle, voice.header, sizeOf<_WaveHdr>());
  }

  void _applyGain(_Voice voice, double gain) {
    final _VolumeDart? setVolume = _waveOutSetVolume;
    if (setVolume == null) {
      return;
    }
    final int level = (gain.clamp(0.0, 1.0) * 0xFFFF).round();
    setVolume(voice.handle, level | (level << 16));
  }

  static Pointer<_WaveFormatEx> _formatFor(PcmClip clip) {
    final Pointer<_WaveFormatEx> format = calloc<_WaveFormatEx>();
    final int blockAlign = clip.channels * clip.bitsPerSample ~/ 8;
    format.ref
      ..wFormatTag = 1
      ..nChannels = clip.channels
      ..nSamplesPerSec = clip.sampleRate
      ..nAvgBytesPerSec = clip.sampleRate * blockAlign
      ..nBlockAlign = blockAlign
      ..wBitsPerSample = clip.bitsPerSample
      ..cbSize = 0;
    return format;
  }

  _Voice? _nextVoice(PcmClip clip) {
    for (final _Voice voice in _voices) {
      if (voice.matches(clip) && voice.capacity >= clip.bytes.length) {
        return voice;
      }
    }
    if (_voices.length < _voiceCount) {
      final _Voice? created = _createVoice(clip);
      if (created != null) {
        _voices.add(created);
        return created;
      }
    }
    // Reuse the round-robin voice, growing its buffer if this clip is longer.
    if (_voices.isEmpty) {
      return null;
    }
    final _Voice voice = _voices[_cursor % _voices.length];
    _cursor++;
    // A voice opened at a different rate cannot play this clip: the device
    // would resample it into a wrong pitch. Skip rather than sound broken.
    if (!voice.matches(clip)) {
      return null;
    }
    if (voice.capacity < clip.bytes.length) {
      _waveOutUnprepare?.call(voice.handle, voice.header, sizeOf<_WaveHdr>());
      final Pointer<Uint8> bigger = calloc<Uint8>(clip.bytes.length);
      if (bigger == nullptr) {
        return null;
      }
      calloc.free(voice.buffer);
      voice.buffer = bigger;
      voice.capacity = clip.bytes.length;
      voice.header.ref
        ..lpData = bigger
        ..dwFlags = 0;
    }
    return voice;
  }

  _Voice? _createVoice(PcmClip clip) {
    final _OpenDart? open = _waveOutOpen;
    if (open == null) {
      return null;
    }
    final Pointer<IntPtr> handlePtr = calloc<IntPtr>();
    final Pointer<_WaveFormatEx> format = _formatFor(clip);
    try {
      final int result = open(handlePtr, 0, format, 0, 0, 0);
      if (result != 0) {
        return null;
      }
      final Pointer<_WaveHdr> header = calloc<_WaveHdr>();
      final Pointer<Uint8> buffer = calloc<Uint8>(clip.bytes.length);
      header.ref
        ..lpData = buffer
        ..dwBufferLength = 0
        ..dwFlags = 0
        ..dwLoops = 1;
      return _Voice(
        handlePtr.value,
        header,
        clip.bytes.length,
        clip.sampleRate,
        clip.channels,
        clip.bitsPerSample,
      );
    } finally {
      calloc.free(format);
      calloc.free(handlePtr);
    }
  }

  void dispose() {
    final _HeaderDart? unprepare = _waveOutUnprepare;
    final _HandleDart? close = _waveOutClose;
    for (final _Voice voice in _voices) {
      if (!voice.isOpen) {
        continue;
      }
      _waveOutReset?.call(voice.handle);
      unprepare?.call(voice.handle, voice.header, sizeOf<_WaveHdr>());
      close?.call(voice.handle);
      calloc.free(voice.buffer);
      calloc.free(voice.header);
    }
    _voices.clear();
    _ready = false;
    _lib = null;
  }
}
