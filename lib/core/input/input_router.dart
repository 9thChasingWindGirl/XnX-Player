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

  /// When each held key went down, in microseconds on a monotonic clock.
  ///
  /// The OS tells us *that* a key repeated, never *how long* it has been down,
  /// and the two are not the same question: Windows lets the user stretch the
  /// repeat delay to a second, and a hold rule measured on repeat count would
  /// then fire at a different moment on every machine.
  final Map<int, int> _downAt = <int, int>{};
  final Stopwatch _clock = Stopwatch()..start();

  /// Set by the app to `TextEntry.active.value`. A text field owns the alphabet,
  /// so nothing but Back is routed while one is open. Indirection keeps this
  /// file free of any dependency on the UI layer.
  bool Function()? textEntryActive;

  /// Whether the focused item has a secondary action a held press could reach.
  ///
  /// The pad asks before deciding how a held confirm behaves: with nothing to
  /// disambiguate it fires on the way down instead of waiting for the release.
  /// Wired to [FocusNavigator.canLongPress] by the app, because a router must
  /// not import the focus tree.
  bool Function()? focusedHasLongPress;

  /// Pushes a press animation into the focused item, for devices that raise no
  /// widget-level down event. Wired to [FocusNavigator.pressFocused].
  void Function(bool down)? pressFocused;

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
    final int keyId = event.logicalKey.keyId;

    // Key-up is not routed: activation happens on release inside the focus
    // tree, and a layer that acted on down would otherwise act twice. The
    // timestamp still has to be dropped, or the next press would report a hold
    // that started before the previous release.
    if (event is KeyUpEvent) {
      _downAt.remove(keyId);
      return false;
    }

    final bool repeat = event is KeyRepeatEvent;
    final InputAction? action = Keymap.actionFor(event);
    final Duration held = _heldFor(keyId, repeat: repeat);

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
      return dispatch(InputIntent.rawKey(event, held: held));
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
        held: held,
        key: event,
      ),
    );
  }

  /// Time since [keyId] went down, and the bookkeeping that measurement needs.
  ///
  /// A repeat must not reset the clock — that would make a hold of any length
  /// look like a first press forever, and every hold rule would be dead.
  Duration _heldFor(int keyId, {required bool repeat}) {
    final int now = _clock.elapsedMicroseconds;
    final int? since = _downAt[keyId];
    if (since == null) {
      _downAt[keyId] = now;
      return Duration.zero;
    }
    if (!repeat) {
      // A fresh down for a key we still think is held: the matching key-up went
      // somewhere we did not see it (a focus change, a window switch). Trust
      // the new press over the stale record.
      _downAt[keyId] = now;
      return Duration.zero;
    }
    return Duration(microseconds: now - since);
  }
}
