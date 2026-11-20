import 'package:flutter/services.dart';

/// What a device asked the UI to do, independent of which device asked.
///
/// Everything in the app speaks this vocabulary, so a screen never learns that
/// a gamepad exists — and, just as important, a keyboard never inherits the
/// rules of a thumbstick. The two halves of that sentence are the whole point:
/// an action carried by different devices is *not* the same event.
enum InputAction {
  navigateUp,
  navigateDown,
  navigateLeft,
  navigateRight,

  /// Activate the focused thing. Keyboard reaches this through the focus tree
  /// (Enter/Space), mouse through a direct tap on the item, gamepad here.
  confirm,

  /// Dismiss whatever is topmost.
  back,

  /// The secondary "more" affordance of the focused item.
  contextMenu,

  /// Left/right nudge inside one focused control (a slider, a volume row).
  /// Separate from [navigateLeft]/[navigateRight], which move focus.
  adjustBack,
  adjustForward,

  /// Whole-page jumps: L1/R1 on a pad, PageUp/PageDown on a keyboard.
  pagePrev,
  pageNext,

  /// Big jumps inside a long list: triggers on a pad, none on a keyboard.
  jumpPrev,
  jumpNext,

  playPause,
  seekBack,
  seekForward,
  seekJumpBack,
  seekJumpForward,
  volumeUp,
  volumeDown,
  mute,

  fullscreen,
  search,
  openFile,

  /// Raise/lower the dock (Tab on a keyboard, X on a pad).
  toggleDock,
}

extension InputActionNature on InputAction {
  /// Whether holding the source down should keep firing the action.
  ///
  /// Only continuous actions repeat. Confirming, going back and opening a menu
  /// must never repeat: a held Enter that fires twice reads as a double tap and
  /// can skip a screen or two of navigation.
  bool get repeats => switch (this) {
    InputAction.navigateUp ||
    InputAction.navigateDown ||
    InputAction.navigateLeft ||
    InputAction.navigateRight ||
    InputAction.adjustBack ||
    InputAction.adjustForward ||
    InputAction.pagePrev ||
    InputAction.pageNext ||
    InputAction.jumpPrev ||
    InputAction.jumpNext ||
    InputAction.seekBack ||
    InputAction.seekForward ||
    InputAction.seekJumpBack ||
    InputAction.seekJumpForward ||
    InputAction.volumeUp ||
    InputAction.volumeDown => true,
    _ => false,
  };
}

/// Which physical thing produced an intent.
enum InputDevice {
  keyboard,

  /// Mouse, trackpad, pen: anything that points at a coordinate.
  pointer,

  gamepad,
}

extension InputDeviceNature on InputDevice {
  /// A pointing device already shows where the user is aiming, so the UI must
  /// not add motion of its own: the focus ring snaps instead of gliding, and a
  /// click acts on the item under the cursor rather than "focus, then confirm".
  bool get points => this == InputDevice.pointer;

  /// Devices that navigate by discrete steps and therefore need a hint that the
  /// highlight travelled between two items.
  bool get steps => this == InputDevice.keyboard || this == InputDevice.gamepad;
}

/// One request from one device.
///
/// [action] is null for keyboard events that have no logical meaning in our
/// vocabulary (digits, brackets, the media keys). They are still delivered,
/// because the player forwards its own keymap to the OSD and would otherwise
/// lose every key the shell does not care about — but a screen that only cares
/// about actions can ignore them.
class InputIntent {
  const InputIntent.action(
    this.action, {
    required this.device,
    this.repeat = false,
    this.key,
  });

  const InputIntent.rawKey(KeyEvent this.key, {this.repeat = false})
    : action = null,
      device = InputDevice.keyboard;

  final InputAction? action;
  final InputDevice device;

  /// True when the device is repeating a hold: OS auto-repeat for a keyboard,
  /// a synthesized cadence for a gamepad. A tap is never a repeat.
  final bool repeat;

  /// The original key event, when a keyboard produced this. Never set by a pad
  /// or a pointer: those have no key identity to preserve.
  final KeyEvent? key;

  @override
  String toString() {
    final String what = action?.name ?? 'raw ${key?.logicalKey.keyId}';
    return 'InputIntent($what${repeat ? ' repeat' : ''} via ${device.name})';
  }
}
