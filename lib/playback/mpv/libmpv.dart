import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'mpv_dll.dart';

// mpv_format
const int mpvFormatNone = 0;
const int mpvFormatString = 1;
const int mpvFormatOsdString = 2;
const int mpvFormatFlag = 3;
const int mpvFormatInt64 = 4;
const int mpvFormatDouble = 5;
const int mpvFormatNode = 6;
const int mpvFormatNodeArray = 7;
const int mpvFormatNodeMap = 8;

// mpv_event_id (only the ones we act on)
const int mpvEventNone = 0;
const int mpvEventShutdown = 1;
const int mpvEventLogMessage = 2;
const int mpvEventEndFile = 7;
const int mpvEventFileLoaded = 8;
const int mpvEventClientMessage = 16;
const int mpvEventVideoReconfig = 17;
const int mpvEventSeek = 20;
const int mpvEventPlaybackRestart = 21;
const int mpvEventPropertyChange = 22;

final class MpvEvent extends Struct {
  @Int32()
  external int eventId;

  @Int32()
  external int error;

  @Uint64()
  external int replyUserdata;

  external Pointer<Void> data;
}

final class MpvEventProperty extends Struct {
  external Pointer<Utf8> name;

  @Int32()
  external int format;

  external Pointer<Void> data;
}

final class MpvEventClientMessage extends Struct {
  @Int32()
  external int numArgs;

  external Pointer<Pointer<Utf8>> args;
}

final class MpvEventEndFile extends Struct {
  @Int32()
  external int reason;

  @Int32()
  external int error;

  @Int64()
  external int playlistEntryId;

  @Int64()
  external int playlistInsertId;

  @Int32()
  external int playlistInsertNumEntries;
}

final class MpvEventLogMessage extends Struct {
  external Pointer<Utf8> prefix;
  external Pointer<Utf8> level;
  external Pointer<Utf8> text;

  @Int32()
  external int logLevel;
}

final class MpvNodeUnion extends Union {
  external Pointer<Utf8> string;

  @Int32()
  external int flag;

  @Int64()
  external int int64;

  @Double()
  external double doubleValue;

  external Pointer<MpvNodeList> list;
}

final class MpvNode extends Struct {
  external MpvNodeUnion data;

  @Int32()
  external int format;
}

final class MpvNodeList extends Struct {
  @Int32()
  external int num;

  external Pointer<MpvNode> values;

  external Pointer<Pointer<Utf8>> keys;
}

/// Thin, hand-written binding to the libmpv client API.
///
/// Only the entry points the player uses are bound. Symbols are resolved lazily
/// at first use, so a stale DLL surfaces as a Dart exception instead of a crash.
class LibMpv {
  LibMpv._(this._lib);

  static LibMpv? _instance;

  static LibMpv get instance => _instance ??= LibMpv._(MpvDll.open());

  final DynamicLibrary _lib;

  late final Pointer<Void> Function() create =
      _lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('mpv_create');

  late final int Function(Pointer<Void>) initialize =
      _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('mpv_initialize');

  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) setOptionString =
      _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('mpv_set_option_string');

  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) setPropertyString =
      _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('mpv_set_property_string');

  late final Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>) getPropertyString =
      _lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('mpv_get_property_string');

  late final int Function(Pointer<Void>, int, Pointer<Utf8>, int) observeProperty =
      _lib.lookupFunction<Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>, Int32),
          int Function(Pointer<Void>, int, Pointer<Utf8>, int)>('mpv_observe_property');

  late final Pointer<MpvEvent> Function(Pointer<Void>, double) waitEvent =
      _lib.lookupFunction<Pointer<MpvEvent> Function(Pointer<Void>, Double),
          Pointer<MpvEvent> Function(Pointer<Void>, double)>('mpv_wait_event');

  late final void Function(
    Pointer<Void>,
    Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
    Pointer<Void>,
  ) setWakeupCallback = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<Void Function(Pointer<Void>)>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<Void Function(Pointer<Void>)>>, Pointer<Void>)>(
    'mpv_set_wakeup_callback',
  );

  late final int Function(Pointer<Void>, Pointer<Pointer<Utf8>>) command =
      _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>),
          int Function(Pointer<Void>, Pointer<Pointer<Utf8>>)>('mpv_command');

  late final int Function(Pointer<Void>, int, Pointer<Pointer<Utf8>>) commandAsync =
      _lib.lookupFunction<Int32 Function(Pointer<Void>, Uint64, Pointer<Pointer<Utf8>>),
          int Function(Pointer<Void>, int, Pointer<Pointer<Utf8>>)>('mpv_command_async');

  late final void Function(Pointer<Void>) terminateDestroy =
      _lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('mpv_terminate_destroy');

  late final Pointer<Utf8> Function(int) errorString =
      _lib.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('mpv_error_string');

  late final void Function(Pointer<Void>) free =
      _lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('mpv_free');

  late final int Function(Pointer<Void>, Pointer<Utf8>) requestLogMessages =
      _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>)>('mpv_request_log_messages');

  String errorText(int code) {
    final Pointer<Utf8> text = errorString(code);
    if (text.address == 0) {
      return 'mpv error $code';
    }
    return text.toDartString();
  }

  /// Converts an `mpv_node` into plain Dart maps / lists / scalars.
  static Object? nodeToDart(Pointer<MpvNode> node, [int depth = 0]) {
    if (node.address == 0) {
      return null;
    }
    return _nodeValue(node.ref, depth);
  }

  static Object? _nodeValue(MpvNode value, int depth) {
    if (depth > 8) {
      return null;
    }
    switch (value.format) {
      case mpvFormatString:
      case mpvFormatOsdString:
        if (value.data.string.address == 0) {
          return null;
        }
        return value.data.string.toDartString();
      case mpvFormatFlag:
        return value.data.flag != 0;
      case mpvFormatInt64:
        return value.data.int64;
      case mpvFormatDouble:
        return value.data.doubleValue;
      case mpvFormatNodeArray:
      case mpvFormatNodeMap:
        return _nodeList(value.data.list, depth);
      default:
        return null;
    }
  }

  static Object? _nodeList(Pointer<MpvNodeList> pointer, int depth) {
    if (pointer.address == 0) {
      return null;
    }
    final MpvNodeList list = pointer.ref;
    final List<Object?> items = <Object?>[];
    for (int i = 0; i < list.num; i++) {
      items.add(_nodeValue(list.values[i], depth + 1));
    }
    if (list.keys.address == 0) {
      return items;
    }
    final Map<String, Object?> map = <String, Object?>{};
    for (int i = 0; i < list.num; i++) {
      final Pointer<Utf8> key = list.keys[i];
      if (key.address == 0) {
        continue;
      }
      map[key.toDartString()] = items[i];
    }
    return map;
  }

  /// Reads an observed property value according to its announced format.
  static Object? readProperty(MpvEventProperty property) {
    final Pointer<Void> data = property.data;
    if (data.address == 0) {
      return null;
    }
    switch (property.format) {
      case mpvFormatString:
        return data.cast<Pointer<Utf8>>().value.toDartString();
      case mpvFormatFlag:
        return data.cast<Int32>().value != 0;
      case mpvFormatInt64:
        return data.cast<Int64>().value;
      case mpvFormatDouble:
        return data.cast<Double>().value;
      case mpvFormatNode:
        return nodeToDart(data.cast<MpvNode>());
      default:
        return null;
    }
  }
}
