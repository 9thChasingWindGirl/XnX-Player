import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'held_repeat.dart';
import 'input_action.dart';
import 'input_router.dart';

/// `XINPUT_GAMEPAD`. 12 bytes, 2-byte alignment, nested inside [_XInputState].
final class _XInputGamepad extends Struct {
  @Uint16()
  external int buttons;
  @Uint8()
  external int leftTrigger;
  @Uint8()
  external int rightTrigger;
  @Int16()
  external int thumbLX;
  @Int16()
  external int thumbLY;
  @Int16()
  external int thumbRX;
  @Int16()
  external int thumbRY;
}

/// `XINPUT_STATE`. 16 bytes. XInput writes all 16, so a smaller Dart struct
/// would be a buffer overflow — [GamepadPoller.start] refuses to run unless
/// `sizeOf` agrees with the header.
final class _XInputState extends Struct {
  @Uint32()
  external int packet;

  external _XInputGamepad pad;
}

typedef _GetStateNative = Uint32 Function(Uint32 index, Pointer<_XInputState> state);
typedef _GetStateDart = int Function(int index, Pointer<_XInputState> state);

/// XInput button bits, in the `wButtons` word.
abstract final class _Pad {
  static const int dpadUp = 0x0001;
  static const int dpadDown = 0x0002;
  static const int dpadLeft = 0x0004;
  static const int dpadRight = 0x0008;
  static const int start = 0x0010;
  static const int lb = 0x0100;
  static const int rb = 0x0200;
  static const int a = 0x1000;
  static const int b = 0x2000;
  static const int x = 0x4000;
  static const int y = 0x8000;
}

/// Reads a Windows gamepad and emits logical actions.
///
/// Deliberately separate from the keyboard path:
/// * directions repeat here ([HeldRepeat]) instead of coming from the OS;
/// * the stick is analog, so it needs a radial deadzone and a dominant axis, not
///   four independent key presses;
/// * a disconnect is not a button press. It stops the polling state instead of
///   firing something the user never asked for.
///
/// Everything is fail-safe: no XInput DLL, no pad, or an unexpected struct size
/// only sets [lastError], and the app keeps running without a gamepad.
class GamepadPoller {
  GamepadPoller._();

  static final GamepadPoller instance = GamepadPoller._();

  static const Duration _interval = Duration(milliseconds: 16);

  /// Radial deadzone, fraction of full deflection, as upstream
  /// (`InputSettings::stick_deadzone`).
  static const double _deadzone = 0.16;

  /// Triggers report 0..255; past this they count as pressed.
  static const int _triggerThreshold = 60;

  static const double _stickFull = 32767;

  _GetStateDart? _getState;
  Pointer<_XInputState>? _state;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  double _lastMicros = 0;

  int _slot = 0;
  int _idleTicks = 0;
  bool _connected = false;
  int _buttons = 0;

  final HeldRepeat _nav = HeldRepeat();
  final HeldRepeat _jump = HeldRepeat();

  /// Circle confirms and cross goes back, the way a Japanese-layout player
  /// expects. Off by default; a settings row can flip it.
  bool swapConfirm = false;

  bool get connected => _connected;

  /// Why the poller is not running, if it is not.
  String? lastError;

  bool get running => _timer != null;

  void start() {
    if (_timer != null || !Platform.isWindows) {
      return;
    }
    if (sizeOf<_XInputState>() != 16) {
      lastError = 'XINPUT_STATE 大小异常: ${sizeOf<_XInputState>()}';
      return;
    }
    try {
      // 1.4 is present on every supported Windows; 9_1_0 exists on all of them
      // as well and speaks the same XInputGetState signature.
      final DynamicLibrary lib = _open();
      _getState = lib.lookupFunction<_GetStateNative, _GetStateDart>('XInputGetState');
      _state = calloc<_XInputState>();
    } on Object catch (error) {
      lastError = 'XInput 不可用: $error';
      return;
    }
    _clock.start();
    _lastMicros = 0;
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  DynamicLibrary _open() {
    try {
      return DynamicLibrary.open('xinput1_4.dll');
    } on Object {
      return DynamicLibrary.open('xinput9_1_0.dll');
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    final Pointer<_XInputState>? state = _state;
    if (state != null) {
      calloc.free(state);
      _state = null;
    }
    _getState = null;
    _connected = false;
    _buttons = 0;
    _nav.reset();
    _jump.reset();
  }

  void _tick() {
    final _GetStateDart? getState = _getState;
    final Pointer<_XInputState>? state = _state;
    if (getState == null || state == null) {
      return;
    }

    final double now = _clock.elapsedMicroseconds.toDouble();
    final double dt = _lastMicros == 0 ? 0 : (now - _lastMicros) / 1000000;
    _lastMicros = now;

    // With no pad plugged in there is nothing to read at 60Hz: probe the four
    // slots about twice a second instead, which also keeps the CPU graph flat.
    if (!_connected) {
      _idleTicks += 1;
      if (_idleTicks % 30 != 1) {
        return;
      }
    }

    int code;
    try {
      code = getState(_slot, state);
    } on Object catch (error) {
      lastError = 'XInputGetState 失败: $error';
      stop();
      return;
    }

    if (code != 0) {
      // ERROR_DEVICE_NOT_CONNECTED for this slot. Try the next one; do not
      // report a "release" for a pad that simply vanished.
      if (_connected) {
        _connected = false;
        _buttons = 0;
        _nav.reset();
        _jump.reset();
      }
      _slot = (_slot + 1) % 4;
      return;
    }

    if (!_connected) {
      _connected = true;
      _buttons = 0;
      _nav.reset();
      _jump.reset();
      _lastMicros = 0;
      _idleTicks = 0;
    }
    _read(state.ref.pad, dt);
  }

  void _read(_XInputGamepad pad, double dt) {
    final int buttons = pad.buttons;
    final int pressed = buttons & ~_buttons;
    _buttons = buttons;

    // Edge-triggered actions: one press, one effect. These never repeat, which
    // is why they do not go through HeldRepeat.
    final bool swap = swapConfirm;
    _edge(pressed, _Pad.a, swap ? InputAction.back : InputAction.confirm);
    _edge(pressed, _Pad.b, swap ? InputAction.confirm : InputAction.back);
    _edge(pressed, _Pad.y, InputAction.contextMenu);
    _edge(pressed, _Pad.x, InputAction.toggleDock);
    _edge(pressed, _Pad.start, InputAction.playPause);
    _edge(pressed, _Pad.lb, InputAction.pagePrev);
    _edge(pressed, _Pad.rb, InputAction.pageNext);

    // One repeater for both D-pad and stick: switching from one to the other
    // mid-hold would otherwise read as a fresh press and step twice.
    final InputAction? nav = _heldNav(
      buttons,
      pad.thumbLX / _stickFull,
      pad.thumbLY / _stickFull,
    );
    final InputAction? navStep = _nav.step(nav, dt);
    if (navStep != null) {
      _emit(navStep, repeat: _nav.isRepeating);
    }

    // Triggers are analog, but the actions behind them are jumps: treat them as
    // buttons with the held cadence, the way upstream uses L2/R2.
    final InputAction? jump = pad.rightTrigger > _triggerThreshold
        ? InputAction.jumpNext
        : pad.leftTrigger > _triggerThreshold
        ? InputAction.jumpPrev
        : null;
    final InputAction? jumpStep = _jump.step(jump, dt);
    if (jumpStep != null) {
      _emit(jumpStep, repeat: _jump.isRepeating);
    }
  }

  /// D-pad wins over the stick; the stick is only read past a radial deadzone and
  /// then reduced to its dominant axis, so a diagonal push cannot produce two
  /// directions at once.
  InputAction? _heldNav(int buttons, double lx, double ly) {
    if ((buttons & _Pad.dpadUp) != 0) {
      return InputAction.navigateUp;
    }
    if ((buttons & _Pad.dpadDown) != 0) {
      return InputAction.navigateDown;
    }
    if ((buttons & _Pad.dpadLeft) != 0) {
      return InputAction.navigateLeft;
    }
    if ((buttons & _Pad.dpadRight) != 0) {
      return InputAction.navigateRight;
    }
    final double ax = lx.abs();
    final double ay = ly.abs();
    if (ax < _deadzone && ay < _deadzone) {
      return null;
    }
    if (ax > ay) {
      return lx > 0 ? InputAction.navigateRight : InputAction.navigateLeft;
    }
    // XInput's Y axis points up; our "down" is positive.
    return ly > 0 ? InputAction.navigateUp : InputAction.navigateDown;
  }

  void _edge(int pressed, int mask, InputAction action) {
    if ((pressed & mask) != 0) {
      _emit(action);
    }
  }

  void _emit(InputAction action, {bool repeat = false}) {
    InputRouter.instance.noteGamepad();
    InputRouter.instance.dispatch(
      InputIntent.action(action, device: InputDevice.gamepad, repeat: repeat),
    );
  }
}
