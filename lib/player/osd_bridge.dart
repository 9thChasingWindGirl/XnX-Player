import 'dart:async';
import 'dart:convert';

import '../playback/mpv/mpv_player.dart';

/// Bridges the Lua OSD's `script-message` events into Dart callbacks.
///
/// Lua sends one JSON object per event: `{"type":"back"}`,
/// `{"type":"seek","t":123.4}`, ... Keeping the transport dumb (a single JSON
/// string) means the Lua side can grow new actions without touching the FFI.
class OsdBridge {
  OsdBridge(this.player);

  final MpvPlayer player;

  StreamSubscription<MpvClientEvent>? _subscription;

  void Function()? onBack;
  void Function()? onTogglePause;
  void Function(double seconds)? onSeekRequest;
  void Function(int direction)? onChannelStep;
  void Function()? onFullscreen;

  void attach() {
    _subscription = player.clientEvents.listen(_handle);
  }

  void _handle(MpvClientEvent event) {
    if (event.name != 'xnx-event') {
      return;
    }
    final String? payload = event.payload;
    if (payload == null) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (decoded is! Map) {
      return;
    }
    final Object? type = decoded['type'];
    if (type is! String) {
      return;
    }

    switch (type) {
      case 'back':
        onBack?.call();
        break;
      case 'playPause':
        onTogglePause?.call();
        break;
      case 'fullscreen':
        onFullscreen?.call();
        break;
      case 'seek':
        final Object? target = decoded['t'];
        if (target is num) {
          onSeekRequest?.call(target.toDouble());
        }
        break;
      case 'channel':
        final Object? delta = decoded['delta'];
        if (delta is num) {
          onChannelStep?.call(delta.toInt());
        }
        break;
      default:
        break;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
