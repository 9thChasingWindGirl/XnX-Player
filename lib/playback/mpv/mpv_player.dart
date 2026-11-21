import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'libmpv.dart';

class MpvTrack {
  const MpvTrack({
    required this.id,
    required this.type,
    this.title,
    this.lang,
    this.codec,
    this.selected = false,
  });

  final int id;

  /// `video` / `audio` / `sub`.
  final String type;
  final String? title;
  final String? lang;
  final String? codec;
  final bool selected;
}

/// A message sent by the Lua OSD through `script-message`.
class MpvClientEvent {
  const MpvClientEvent(this.name, this.args);

  final String name;
  final List<String> args;

  String? get payload => args.isEmpty ? null : args.first;
}

class MpvViewState {
  const MpvViewState({
    this.position = 0,
    this.duration = 0,
    this.paused = false,
    this.buffering = false,
    this.seeking = false,
    this.eof = false,
    this.volume = 80,
    this.muted = false,
    this.tracks = const <MpvTrack>[],
    this.videoCodec,
    this.hwdec,
    this.containerFps,
  });

  final double position;
  final double duration;
  final bool paused;
  final bool buffering;
  final bool seeking;
  final bool eof;
  final double volume;
  final bool muted;
  final List<MpvTrack> tracks;
  final String? videoCodec;
  final String? hwdec;
  final double? containerFps;

  bool get hasDuration => duration > 0;

  MpvViewState copyWith({
    double? position,
    double? duration,
    bool? paused,
    bool? buffering,
    bool? seeking,
    bool? eof,
    double? volume,
    bool? muted,
    List<MpvTrack>? tracks,
    String? videoCodec,
    String? hwdec,
    double? containerFps,
  }) {
    return MpvViewState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      paused: paused ?? this.paused,
      buffering: buffering ?? this.buffering,
      seeking: seeking ?? this.seeking,
      eof: eof ?? this.eof,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      tracks: tracks ?? this.tracks,
      videoCodec: videoCodec ?? this.videoCodec,
      hwdec: hwdec ?? this.hwdec,
      containerFps: containerFps ?? this.containerFps,
    );
  }
}

/// High-level wrapper around one libmpv instance.
///
/// The native handle is created on the platform thread; events are pumped back
/// into the Dart isolate through `mpv_set_wakeup_callback` +
/// `NativeCallable.listener`, so there is no polling thread and no manual
/// message port bookkeeping.
class MpvPlayer {
  MpvPlayer();

  static const Map<String, int> _observedProperties = <String, int>{
    'time-pos': mpvFormatDouble,
    'duration': mpvFormatDouble,
    'pause': mpvFormatFlag,
    'seeking': mpvFormatFlag,
    'paused-for-cache': mpvFormatFlag,
    'eof-reached': mpvFormatFlag,
    'volume': mpvFormatDouble,
    'mute': mpvFormatFlag,
    'track-list': mpvFormatNode,
    'video-codec': mpvFormatString,
    'hwdec-current': mpvFormatString,
    'container-fps': mpvFormatDouble,
  };

  final ValueNotifier<MpvViewState> state = ValueNotifier<MpvViewState>(const MpvViewState());
  final StreamController<MpvClientEvent> _clientEvents = StreamController<MpvClientEvent>.broadcast();
  final StreamController<bool> _fileLoaded = StreamController<bool>.broadcast();

  /// Last few lines mpv emitted at the requested message level. Surfaced in the
  /// player's diagnostics panel so a black screen turns into a readable error
  /// instead of a guessing game.
  final List<String> _logs = <String>[];
  final ValueNotifier<int> logRevision = ValueNotifier<int>(0);

  /// Set when mpv reports a failed load (`mpv_end_file_reason` = error).
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  static const int _maxLogLines = 60;

  Pointer<Void>? _handle;
  NativeCallable<Void Function(Pointer<Void>)>? _wakeup;
  bool _disposed = false;
  bool _initialized = false;

  Stream<MpvClientEvent> get clientEvents => _clientEvents.stream;

  Stream<bool> get onFileLoaded => _fileLoaded.stream;

  bool get isInitialized => _initialized;

  /// Immutable snapshot of the buffered mpv log lines.
  List<String> get logs => List<String>.unmodifiable(_logs);

  LibMpv get _mpv => LibMpv.instance;

  void start({
    required Map<String, String> options,
    String? logFile,
    String logLevel = 'info',
  }) {
    if (_handle != null) {
      throw StateError('mpv already started');
    }
    final Pointer<Void> handle = _mpv.create();
    if (handle.address == 0) {
      throw StateError('mpv_create() 失败：libmpv 版本不匹配或内存不足。');
    }
    _handle = handle;

    try {
      if (logFile != null) {
        _setOption('log-file', logFile);
      }
      options.forEach(_setOption);
      final int rc = _mpv.initialize(handle);
      if (rc < 0) {
        throw StateError('mpv_initialize 失败：${_mpv.errorText(rc)}');
      }
      _initialized = true;
    } catch (_) {
      _mpv.terminateDestroy(handle);
      _handle = null;
      _initialized = false;
      rethrow;
    }

    _mpv.setWakeupCallback(handle, _listener().nativeFunction, nullptr);
    _observe();
    _requestLogs(logLevel);
  }

  void _requestLogs(String level) {
    final Pointer<Void>? handle = _handle;
    if (handle == null) {
      return;
    }
    final Pointer<Utf8> levelPtr = level.toNativeUtf8();
    try {
      _mpv.requestLogMessages(handle, levelPtr);
    } finally {
      calloc.free(levelPtr);
    }
  }

  NativeCallable<Void Function(Pointer<Void>)> _listener() {
    return _wakeup ??= NativeCallable<Void Function(Pointer<Void>)>.listener(_onWakeup);
  }

  void _onWakeup(Pointer<Void> context) {
    _drain();
  }

  void _setOption(String name, String value) {
    final Pointer<Void>? handle = _handle;
    if (handle == null) {
      return;
    }
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> valuePtr = value.toNativeUtf8();
    try {
      _mpv.setOptionString(handle, namePtr, valuePtr);
    } finally {
      calloc.free(namePtr);
      calloc.free(valuePtr);
    }
  }

  void _observe() {
    final Pointer<Void>? handle = _handle;
    if (handle == null) {
      return;
    }
    _observedProperties.forEach((String name, int format) {
      final Pointer<Utf8> namePtr = name.toNativeUtf8();
      try {
        _mpv.observeProperty(handle, 0, namePtr, format);
      } finally {
        calloc.free(namePtr);
      }
    });
  }

  void _drain() {
    final Pointer<Void>? handle = _handle;
    if (handle == null || _disposed) {
      return;
    }
    for (int guard = 0; guard < 512; guard++) {
      final Pointer<MpvEvent> event = _mpv.waitEvent(handle, 0);
      if (event.address == 0) {
        return;
      }
      final MpvEvent value = event.ref;
      if (value.eventId == mpvEventNone) {
        return;
      }
      _handleEvent(value);
    }
  }

  void _handleEvent(MpvEvent event) {
    switch (event.eventId) {
      case mpvEventPropertyChange:
        _handlePropertyChange(event);
        break;
      case mpvEventFileLoaded:
        if (!_fileLoaded.isClosed) {
          _fileLoaded.add(true);
        }
        break;
      case mpvEventEndFile:
        _handleEndFile(event);
        break;
      case mpvEventLogMessage:
        _handleLogMessage(event);
        break;
      case mpvEventClientMessage:
        _handleClientMessage(event);
        break;
      case mpvEventShutdown:
        break;
      default:
        break;
    }
  }

  void _handleEndFile(MpvEvent event) {
    state.value = state.value.copyWith(eof: true, buffering: false);
    if (event.data.address == 0) {
      return;
    }
    final MpvEventEndFile end = event.data.cast<MpvEventEndFile>().ref;
    if (end.error < 0) {
      lastError.value = '${_mpv.errorText(end.error)} (${end.error})';
    }
  }

  void _handleLogMessage(MpvEvent event) {
    if (event.data.address == 0) {
      return;
    }
    final MpvEventLogMessage message = event.data.cast<MpvEventLogMessage>().ref;
    final StringBuffer buffer = StringBuffer();
    if (message.prefix.address != 0) {
      buffer.write('[');
      buffer.write(message.prefix.toDartString());
      buffer.write('] ');
    }
    if (message.text.address != 0) {
      buffer.write(message.text.toDartString().trimRight());
    }
    final String line = buffer.toString();
    if (line.isEmpty) {
      return;
    }
    _logs.add(line);
    if (_logs.length > _maxLogLines) {
      _logs.removeRange(0, _logs.length - _maxLogLines);
    }
    logRevision.value = logRevision.value + 1;
  }

  void _handlePropertyChange(MpvEvent event) {
    if (event.data.address == 0) {
      return;
    }
    final MpvEventProperty property = event.data.cast<MpvEventProperty>().ref;
    if (property.name.address == 0) {
      return;
    }
    _applyProperty(property.name.toDartString(), LibMpv.readProperty(property));
  }

  void _handleClientMessage(MpvEvent event) {
    if (event.data.address == 0) {
      return;
    }
    final MpvEventClientMessage message = event.data.cast<MpvEventClientMessage>().ref;
    final List<String> args = <String>[];
    for (int i = 0; i < message.numArgs; i++) {
      final Pointer<Utf8> arg = message.args[i];
      if (arg.address == 0) {
        continue;
      }
      args.add(arg.toDartString());
    }
    if (args.isEmpty || _clientEvents.isClosed) {
      return;
    }
    _clientEvents.add(MpvClientEvent(args.first, args.sublist(1)));
  }

  void _applyProperty(String name, Object? value) {
    final MpvViewState current = state.value;
    switch (name) {
      case 'time-pos':
        if (value is num) {
          state.value = current.copyWith(position: value.toDouble());
        }
        break;
      case 'duration':
        if (value is num) {
          state.value = current.copyWith(duration: value.toDouble());
        }
        break;
      case 'pause':
        if (value is bool) {
          state.value = current.copyWith(paused: value);
        }
        break;
      case 'seeking':
        if (value is bool) {
          state.value = current.copyWith(seeking: value);
        }
        break;
      case 'paused-for-cache':
        if (value is bool) {
          state.value = current.copyWith(buffering: value);
        }
        break;
      case 'eof-reached':
        if (value is bool) {
          state.value = current.copyWith(eof: value);
        }
        break;
      case 'volume':
        if (value is num) {
          state.value = current.copyWith(volume: value.toDouble());
        }
        break;
      case 'mute':
        if (value is bool) {
          state.value = current.copyWith(muted: value);
        }
        break;
      case 'container-fps':
        if (value is num) {
          state.value = current.copyWith(containerFps: value.toDouble());
        }
        break;
      case 'video-codec':
        if (value is String) {
          state.value = current.copyWith(videoCodec: value);
        }
        break;
      case 'hwdec-current':
        if (value is String) {
          state.value = current.copyWith(hwdec: value);
        }
        break;
      case 'track-list':
        state.value = current.copyWith(tracks: _parseTracks(value));
        break;
      default:
        break;
    }
  }

  List<MpvTrack> _parseTracks(Object? value) {
    if (value is! List) {
      return const <MpvTrack>[];
    }
    final List<MpvTrack> tracks = <MpvTrack>[];
    for (final Object? entry in value) {
      if (entry is! Map) {
        continue;
      }
      final Object? id = entry['id'];
      final Object? type = entry['type'];
      if (id is! int || type is! String) {
        continue;
      }
      tracks.add(MpvTrack(
        id: id,
        type: type,
        title: entry['title'] is String ? entry['title'] as String : null,
        lang: entry['lang'] is String ? entry['lang'] as String : null,
        codec: entry['codec'] is String ? entry['codec'] as String : null,
        selected: entry['selected'] == true,
      ));
    }
    return tracks;
  }

  int command(List<String> args, {bool async = false}) {
    final Pointer<Void>? handle = _handle;
    if (handle == null) {
      return -1;
    }
    final Pointer<Pointer<Utf8>> argv = calloc<Pointer<Utf8>>(args.length + 1);
    final List<Pointer<Utf8>> allocated = <Pointer<Utf8>>[];
    try {
      for (int i = 0; i < args.length; i++) {
        final Pointer<Utf8> arg = args[i].toNativeUtf8();
        allocated.add(arg);
        argv[i] = arg;
      }
      argv[args.length] = nullptr.cast<Utf8>();
      return async ? _mpv.commandAsync(handle, 0, argv) : _mpv.command(handle, argv);
    } finally {
      for (final Pointer<Utf8> arg in allocated) {
        calloc.free(arg);
      }
      calloc.free(argv);
    }
  }

  void setProperty(String name, String value) {
    final Pointer<Void>? handle = _handle;
    if (handle == null) {
      return;
    }
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> valuePtr = value.toNativeUtf8();
    try {
      _mpv.setPropertyString(handle, namePtr, valuePtr);
    } finally {
      calloc.free(namePtr);
      calloc.free(valuePtr);
    }
  }

  /// Reads a property synchronously and returns it as a string.
  ///
  /// Only meant for the few checks that decide whether the video path is alive
  /// (`vo-configured`, `estimated-vf-fps`, `ao`...). These are cached values, so
  /// the call does not block on the playback thread.
  String? getProperty(String name) {
    final Pointer<Void>? handle = _handle;
    if (handle == null) {
      return null;
    }
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    Pointer<Utf8> value = nullptr;
    try {
      value = _mpv.getPropertyString(handle, namePtr);
      if (value == nullptr) {
        return null;
      }
      final String text = value.toDartString();
      return text.isEmpty ? null : text;
    } finally {
      if (value != nullptr) {
        _mpv.free(value.cast<Void>());
      }
      calloc.free(namePtr);
    }
  }

  /// Convenience wrapper for the numeric properties the health check needs.
  double? getPropertyNumber(String name) {
    final String? raw = getProperty(name);
    return raw == null ? null : double.tryParse(raw);
  }

  /// Convenience wrapper for boolean properties (`yes` / `no`).
  bool getPropertyFlag(String name) => getProperty(name) == 'yes';

  /// Whether a script with this file name is registered with mpv.
  ///
  /// `script-list` reports names without the `.lua` suffix, so both sides are
  /// normalised before comparing.
  bool scriptLoaded(String name) {
    final String? list = getProperty('script-list');
    if (list == null) {
      return false;
    }
    String bare(String s) => s.replaceAll('.lua', '').trim();
    return bare(list).contains(bare(name));
  }

  /// Loads a Lua script and returns mpv's verdict.
  ///
  /// `--script=` before init is silent when the path is wrong: mpv just has no
  /// script. Loading it afterwards through the command interface lets the
  /// caller check `script-list` and show a real error instead of a player with
  /// no UI.
  bool loadScript(String path) {
    final int rc = command(<String>['load-script', path]);
    if (rc < 0) {
      return false;
    }
    return scriptLoaded(path.split(RegExp(r'[\\/]')).last);
  }

  void load(String path, {Duration startAt = Duration.zero}) {
    final String options =
        'start=${(startAt.inMilliseconds / 1000).toStringAsFixed(3)}';
    command(<String>['loadfile', path, 'replace', '-1', options], async: true);
  }

  /// Loads [urls] as a playlist so "下一集" works without a second round-trip.
  ///
  /// Only the first entry honours [startAt]: resume points belong to the file
  /// the user actually clicked.
  void loadQueue(List<String> urls, {Duration startAt = Duration.zero}) {
    if (urls.isEmpty) {
      return;
    }
    final String options =
        'start=${(startAt.inMilliseconds / 1000).toStringAsFixed(3)}';
    command(<String>['loadfile', urls.first, 'replace', '-1', options], async: true);
    for (int i = 1; i < urls.length; i++) {
      command(<String>['loadfile', urls[i], 'append'], async: true);
    }
  }

  /// Sends a JSON command to the Lua OSD (`player-cmd`).
  ///
  /// The transport is a single JSON string on purpose: the Lua side can grow
  /// new verbs without touching the FFI surface.
  void sendScriptMessage(Map<String, Object?> payload) {
    command(<String>['script-message', 'player-cmd', jsonEncode(payload)], async: true);
  }

  /// Forwards one key to the OSD, which owns all playback actions.
  void sendKey(String name) {
    sendScriptMessage(<String, Object?>{'cmd': 'key', 'key': name});
  }

  /// Forwards one pointer event to the OSD.
  ///
  /// This exists because mpv cannot see the mouse here at all: the picture is a
  /// native child window owned by us, and Windows delivers the messages to the
  /// Flutter view. A session log contains no `[input]` line, so `mouse-pos`
  /// never changes and every hitbox the OSD draws is unreachable. Coordinates
  /// are normalized against the video area, leaving the 1920x1080 design space
  /// entirely to the Lua side — two places that both "know" the layout is one
  /// place too many.
  void sendMouse({
    required String ev,
    double? nx,
    double? ny,
    String? button,
    int? delta,
  }) {
    sendScriptMessage(<String, Object?>{
      'cmd': 'mouse',
      'ev': ev,
      if (nx != null) 'nx': nx,
      if (ny != null) 'ny': ny,
      if (button != null) 'button': button,
      if (delta != null) 'delta': delta,
    });
  }

  void showUi() {
    sendScriptMessage(<String, Object?>{'cmd': 'show'});
  }

  /// Repaints the OSD without changing whether it is visible.
  ///
  /// A window resize changes the frame the OSD is laid out in, but a paused
  /// player may not render a new frame on its own; this asks the Lua side to
  /// rebuild the overlay at the new size.
  void redrawOsd() {
    sendScriptMessage(<String, Object?>{'cmd': 'redraw'});
  }

  void togglePause() {
    command(<String>['cycle', 'pause']);
  }

  void seekBy(double seconds) {
    command(<String>['seek', seconds.toStringAsFixed(2), 'relative']);
  }

  void seekTo(double seconds) {
    command(<String>['seek', seconds.toStringAsFixed(2), 'absolute']);
  }

  void setVolume(double volume) {
    command(<String>['set', 'volume', volume.clamp(0, 130).toStringAsFixed(1)]);
  }

  void stop() {
    command(<String>['stop']);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final Pointer<Void>? handle = _handle;
    _handle = null;
    _initialized = false;
    if (handle != null) {
      _mpv.setWakeupCallback(handle, nullptr, nullptr);
      _mpv.terminateDestroy(handle);
    }
    _wakeup?.close();
    _wakeup = null;
    _clientEvents.close();
    _fileLoaded.close();
    lastError.dispose();
    logRevision.dispose();
    state.dispose();
  }
}
