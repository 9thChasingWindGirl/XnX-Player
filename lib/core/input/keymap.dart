import 'package:flutter/services.dart';

import 'input_action.dart';

/// Physical keys → logical actions.
///
/// Keyed by [LogicalKeyboardKey.keyId] and never by `debugName`: the latter is
/// documented as null in release builds, so a table built on it would accept no
/// keys in the build we ship.
///
/// This table is the *only* place that knows a key's identity. Screens ask for
/// actions; the player still gets the raw event as well, because the OSD has its
/// own (much larger) keymap and re-deriving it here would only lose keys.
abstract final class Keymap {
  const Keymap._();

  static final Map<int, InputAction> _bindings = <int, InputAction>{
    LogicalKeyboardKey.arrowUp.keyId: InputAction.navigateUp,
    LogicalKeyboardKey.arrowDown.keyId: InputAction.navigateDown,
    LogicalKeyboardKey.arrowLeft.keyId: InputAction.navigateLeft,
    LogicalKeyboardKey.arrowRight.keyId: InputAction.navigateRight,

    LogicalKeyboardKey.escape.keyId: InputAction.back,

    // Enter and Space are normally consumed by the focused widget before any of
    // this runs. They are mapped anyway so a screen with no focusable children
    // (the player, before its OSD is up) still gets a confirm.
    LogicalKeyboardKey.enter.keyId: InputAction.confirm,
    LogicalKeyboardKey.numpadEnter.keyId: InputAction.confirm,
    LogicalKeyboardKey.space.keyId: InputAction.confirm,
    LogicalKeyboardKey.contextMenu.keyId: InputAction.contextMenu,

    LogicalKeyboardKey.tab.keyId: InputAction.toggleDock,
    LogicalKeyboardKey.f1.keyId: InputAction.openFile,
    LogicalKeyboardKey.f11.keyId: InputAction.fullscreen,

    LogicalKeyboardKey.pageUp.keyId: InputAction.pagePrev,
    LogicalKeyboardKey.pageDown.keyId: InputAction.pageNext,
  };

  /// Ctrl/Meta combinations stay out of the plain table: Ctrl+Left must not move
  /// focus, and Windows uses plenty of Ctrl chords of its own.
  static InputAction? actionFor(KeyEvent event) {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final LogicalKeyboardKey key = event.logicalKey;

    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      if (key == LogicalKeyboardKey.keyF) {
        return InputAction.search;
      }
      if (key == LogicalKeyboardKey.keyO) {
        return InputAction.openFile;
      }
      return null;
    }
    if (key == LogicalKeyboardKey.slash) {
      return InputAction.search;
    }
    return _bindings[key.keyId];
  }
}
