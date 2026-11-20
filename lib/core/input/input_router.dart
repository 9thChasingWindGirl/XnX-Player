import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'input_action.dart';
import 'keymap.dart';

/// Receives intents while it is on top of the stack. Return true when the
/// intent was acted on.
typedef InputHandler = bool Function(InputIntent intent);

/// Handle to one layer's place in the stack.
class InputSubscription {
  InputSubscription._(this._router, this.handler, this.name);

  final InputRouter _router;
  final InputHandler handler;
  final String name;
  bool _active = true;

  bool get active => _active;

  void cancel() {
    if (!_active) {
      return;
    }
    _active = false;
    _router._layers.remove(this);
  }
}

/// The one place that turns physical input into [InputIntent]s and hands them to
/// a stack of layers, topmost first.
///
/// Why a stack instead of five `HardwareKeyboard.addHandler` calls: the old
/// arrangement made the order an accident of `initState`, so which layer won a
/// key depended on widget lifetime. Back had to be spelled out again in every
/// new overlay. Here, whoever was pushed last gets first refusal, and "close the
/// thing that is on top" is one rule for the whole app.
///
/// Devices are kept apart on purpose:
/// * keyboard — auto-repeat belongs to the OS; we never synthesize it, we just
///   let [KeyRepeatEvent] through for actions that are allowed to repeat;
/// * gamepad — nothing repeats by itself, so [HeldRepeat] produces the 350ms /
///   110ms / 50ms cadence upstream uses;
/// * pointer — no repeat at all, and no "focus then confirm": a click acts on
///   the item under the cursor, and the highlight snaps rather than glides
///   because the cursor already shows where the user is aiming.
class InputRouter {
  InputRouter._();

  static final InputRouter instance = InputRouter._();

  /// The device that produced the most recent intent. Read by the highlight
  /// (snap vs glide) and by anything that wants to adapt.
  final ValueNotifier<InputDevice> device = ValueNotifier<InputDevice>(
    InputDevice.keyboard,
  );

  final List<InputSubscription> _layers = <InputSubscription>[];
  bool _installed = false;

  /// Set by the app to `TextEntry.active.value`. A text field owns the alphabet,
  /// so nothing but Back is routed while one is open. Indirection keeps this
  /// file free of any dependency on the UI layer.
  bool Function()? textEntryActive;

  List<InputSubscription> get layers => List<InputSubscription>.unmodifiable(_layers);

  /// Installs the single global keyboard handler. Idempotent.
  void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void uninstall() {
    if (!_installed) {
      return;
    }
    _installed = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  InputSubscription subscribe(InputHandler handler, {String name = ''}) {
    final InputSubscription subscription = InputSubscription._(this, handler, name);
    _layers.add(subscription);
    return subscription;
  }

  /// Records that the pointer is what the user last touched. Called from hover
  /// and from the player's pointer forwarding — no intent is dispatched, because
  /// a pointing device has nothing to "do" until it clicks.
  void notePointer() {
    if (device.value != InputDevice.pointer) {
      device.value = InputDevice.pointer;
    }
  }

  void noteGamepad() {
    if (device.value != InputDevice.gamepad) {
      device.value = InputDevice.gamepad;
    }
  }

  /// Topmost layer first. Returns true when someone acted on it.
  bool dispatch(InputIntent intent) {
    if (device.value != intent.device) {
      device.value = intent.device;
    }
    for (int i = _layers.length - 1; i >= 0; i--) {
      if (_layers[i].handler(intent)) {
        return true;
      }
    }
    return false;
  }

  bool _textEntryOwnsKeys() => textEntryActive?.call() ?? false;

  bool _onKey(KeyEvent event) {
    // Key-up is not routed: activation happens on release inside the focus
    // tree, and a layer that acted on down would otherwise act twice.
    if (event is KeyUpEvent) {
      return false;
    }
    final bool repeat = event is KeyRepeatEvent;
    final InputAction? action = Keymap.actionFor(event);

    if (_textEntryOwnsKeys() && action != InputAction.back) {
      // A caret is on screen. Back is the only thing it cannot use itself; the
      // rest belongs to the field, including the repeat events its own caret
      // handling expects.
      return false;
    }

    if (action == null) {
      // Keys we have no opinion about — digits, brackets, media keys. The player
      // forwards its own keymap to the OSD and must keep seeing them, so they
      // travel as raw events with a null action.
      if (repeat) {
        return false;
      }
      return dispatch(InputIntent.rawKey(event));
    }

    if (repeat && !action.repeats) {
      // Swallow nothing, claim nothing: Enter held down must not confirm twice,
      // and it must not look "unhandled" either — returning false simply ends
      // the chain, which is what the old per-page handlers did.
      return false;
    }

    return dispatch(
      InputIntent.action(
        action,
        device: InputDevice.keyboard,
        repeat: repeat,
        key: event,
      ),
    );
  }
}
