import 'package:flutter/services.dart';

import '../core/input/input_action.dart';

/// Maps Flutter key identities onto the key names the Lua OSD understands.
///
/// The lookup is keyed by [LogicalKeyboardKey.keyId], **not** by `debugName`:
/// `debugName` is documented as "null in release mode", so a player that relied
/// on it would accept no keys at all in the build we ship. `keyId` is a stable
/// compile-time constant (the Unicode code point for printable keys, an offset
/// namespace for the rest).
///
/// The OSD (`assets/mpv/player_osd.lua`) parses strings like `space`,
/// `shift+left` and `alt+n`; this is the only place that knows both lexicons.
abstract final class OsdKeys {
  const OsdKeys._();

  static final Map<int, String> _named = <int, String>{
    LogicalKeyboardKey.space.keyId: 'space',
    LogicalKeyboardKey.arrowLeft.keyId: 'left',
    LogicalKeyboardKey.arrowRight.keyId: 'right',
    LogicalKeyboardKey.arrowUp.keyId: 'up',
    LogicalKeyboardKey.arrowDown.keyId: 'down',
    LogicalKeyboardKey.escape.keyId: 'esc',
    LogicalKeyboardKey.enter.keyId: 'enter',
    LogicalKeyboardKey.numpadEnter.keyId: 'enter',
    LogicalKeyboardKey.tab.keyId: 'tab',
    LogicalKeyboardKey.backspace.keyId: 'bs',
    LogicalKeyboardKey.pageUp.keyId: 'pageup',
    LogicalKeyboardKey.pageDown.keyId: 'pagedown',
    LogicalKeyboardKey.bracketLeft.keyId: '[',
    LogicalKeyboardKey.bracketRight.keyId: ']',
    LogicalKeyboardKey.comma.keyId: 'comma',
    LogicalKeyboardKey.period.keyId: 'period',
    LogicalKeyboardKey.minus.keyId: '-',
    LogicalKeyboardKey.equal.keyId: '=',
    LogicalKeyboardKey.f6.keyId: 'f6',
    LogicalKeyboardKey.f7.keyId: 'f7',
    LogicalKeyboardKey.f8.keyId: 'f8',
    LogicalKeyboardKey.f9.keyId: 'f9',
    LogicalKeyboardKey.f10.keyId: 'f10',
    LogicalKeyboardKey.f11.keyId: 'f11',
    LogicalKeyboardKey.f12.keyId: 'f12',
    LogicalKeyboardKey.digit1.keyId: '1',
    LogicalKeyboardKey.digit2.keyId: '2',
    LogicalKeyboardKey.digit3.keyId: '3',
    LogicalKeyboardKey.digit4.keyId: '4',
    LogicalKeyboardKey.digit5.keyId: '5',
    LogicalKeyboardKey.digit6.keyId: '6',
    LogicalKeyboardKey.digit7.keyId: '7',
    LogicalKeyboardKey.digit8.keyId: '8',
    LogicalKeyboardKey.digit9.keyId: '9',
    LogicalKeyboardKey.keyA.keyId: 'a',
    LogicalKeyboardKey.keyB.keyId: 'b',
    LogicalKeyboardKey.keyC.keyId: 'c',
    LogicalKeyboardKey.keyD.keyId: 'd',
    LogicalKeyboardKey.keyE.keyId: 'e',
    LogicalKeyboardKey.keyF.keyId: 'f',
    LogicalKeyboardKey.keyG.keyId: 'g',
    LogicalKeyboardKey.keyH.keyId: 'h',
    LogicalKeyboardKey.keyI.keyId: 'i',
    LogicalKeyboardKey.keyJ.keyId: 'j',
    LogicalKeyboardKey.keyK.keyId: 'k',
    LogicalKeyboardKey.keyL.keyId: 'l',
    LogicalKeyboardKey.keyM.keyId: 'm',
    LogicalKeyboardKey.keyN.keyId: 'n',
    LogicalKeyboardKey.keyO.keyId: 'o',
    LogicalKeyboardKey.keyP.keyId: 'p',
    LogicalKeyboardKey.keyQ.keyId: 'q',
    LogicalKeyboardKey.keyR.keyId: 'r',
    LogicalKeyboardKey.keyS.keyId: 's',
    LogicalKeyboardKey.keyT.keyId: 't',
    LogicalKeyboardKey.keyU.keyId: 'u',
    LogicalKeyboardKey.keyV.keyId: 'v',
    LogicalKeyboardKey.keyW.keyId: 'w',
    LogicalKeyboardKey.keyX.keyId: 'x',
    LogicalKeyboardKey.keyY.keyId: 'y',
    LogicalKeyboardKey.keyZ.keyId: 'z',
  };

  /// The OSD name for an action that did *not* come from a keyboard.
  ///
  /// A pad has no keys, so it cannot use [compose]; this is the small subset of
  /// the OSD's vocabulary that a pad can reach. Keys keep their own rich map on
  /// purpose — folding `[`, `]`, digits and `alt+n` into actions would lose them.
  static String? nameForAction(InputAction action) => switch (action) {
    InputAction.navigateUp => 'up',
    InputAction.navigateDown => 'down',
    InputAction.navigateLeft => 'left',
    InputAction.navigateRight => 'right',
    InputAction.adjustBack => 'left',
    InputAction.adjustForward => 'right',
    InputAction.confirm => 'enter',
    InputAction.back => 'esc',
    // The pad has no Tab, so the secondary button (Y) raises the chrome instead;
    // inside a menu `tab` closes it, which is the same thing.
    InputAction.contextMenu => 'tab',
    InputAction.toggleDock => 'tab',
    InputAction.playPause => 'space',
    InputAction.seekBack => 'left',
    InputAction.seekForward => 'right',
    InputAction.seekJumpBack => 'shift+left',
    InputAction.seekJumpForward => 'shift+right',
    InputAction.jumpPrev => 'shift+left',
    InputAction.jumpNext => 'shift+right',
    InputAction.pagePrev => 'pageup',
    InputAction.pageNext => 'pagedown',
    InputAction.volumeUp => 'up',
    InputAction.volumeDown => 'down',
    InputAction.mute => 'm',
    InputAction.fullscreen => 'f11',
    _ => null,
  };

  /// The OSD name for one physical key, ignoring modifiers.
  ///
  /// Returns null for keys the OSD has no opinion about, which lets the caller
  /// leave the event alone for the rest of the app.
  static String? base(LogicalKeyboardKey key) => _named[key.keyId];

  /// `shift+left`, `alt+n`, `space` — exactly what the Lua handler parses.
  static String? compose(LogicalKeyboardKey key, {bool shift = false, bool alt = false}) {
    final String? name = base(key);
    if (name == null) {
      return null;
    }
    if (!shift && !alt) {
      return name;
    }
    final StringBuffer buffer = StringBuffer();
    if (alt) {
      buffer.write('alt+');
    }
    if (shift) {
      buffer.write('shift+');
    }
    buffer.write(name);
    return buffer.toString();
  }
}
