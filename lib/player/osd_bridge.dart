import 'dart:async';
import 'dart:convert';

import '../playback/mpv/mpv_player.dart';

/// Bridges the Lua OSD's `script-message` events into Dart callbacks.
///
/// Lua sends one JSON object per event: `{"type":"back"}`,
/// `{"type":"seek","t":123.4}`, ... Keeping the transport dumb (a single JSON
/// string) means the Lua side can grow new actions without touching the FFI.
///
/// The bridge is deliberately one-way in each direction:
/// * Lua → Dart for things only Flutter can do (leave the player, exit fullscreen).
/// * Dart → Lua for input forwarding, because the Flutter view and mpv's child
///   window take turns owning the keyboard.
class OsdBridge {
  OsdBridge(this.player);

  final MpvPlayer player;

  StreamSubscription<MpvClientEvent>? _subscription;

  void Function()? onBack;
  void Function()? onTogglePause;
  void Function(double seconds)? onSeekRequest;
  void Function(int direction)? onChannelStep;
  void Function()? onFullscreen;

  /// The OSD asked for a file dialog (external subtitles). Only Flutter can
  /// open one, so it comes back here.
  void Function()? onLoadSubtitle;

  /// Fired for every decoded payload, before the typed callbacks. Used as a
  /// heartbeat: if the OSD answers a forwarded key, Flutter knows the script
  /// is alive and must not apply its own fallback.
  void Function(Map<Object?, Object?> payload)? onEvent;

  void attach() {
    _subscription = player.clientEvents.listen(_handle);
  }

  /// Sends a command to the OSD (`{"cmd": ...}`).
  void send(Map<String, Object?> payload) => player.sendScriptMessage(payload);

  /// Forwards one key, e.g. `space`, `shift+left`, `alt+n`.
  void sendKey(String name) => player.sendKey(name);

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
    onEvent?.call(decoded);

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
      case 'subtitle':
        onLoadSubtitle?.call();
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
        // 'ui', 'ack' and anything the OSD adds later are heartbeat-only.
        break;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
