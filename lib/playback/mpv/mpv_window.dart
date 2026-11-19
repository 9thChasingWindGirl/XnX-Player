import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// A plain rectangle in device pixels. Kept free of Flutter types so the whole
/// window layer can be unit-tested without a renderer.
class WindowBox {
  const WindowBox(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is WindowBox &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'WindowBox($left,$top ${width}x$height)';
}

class ChildWindow {
  const ChildWindow(this.handle, this.className, this.box);

  final int handle;
  final String className;
  final WindowBox box;

  @override
  String toString() => 'ChildWindow(0x${handle.toRadixString(16)} $className $box)';
}

final class _Rect extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int right;

  @Int32()
  external int bottom;
}

// --- Win32 signatures -------------------------------------------------------
//
// Every lookup below spells out the native signature *and* the Dart mirror.
// Handles travel as plain `int`; only the two string parameters and the rect
// out-pointer are typed, so mixing them up is a compile error rather than a
// crash at runtime.

typedef _EnumProcNative = Int32 Function(IntPtr hwnd, IntPtr param);

typedef _FindWindowNative = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _FindWindowDart = int Function(Pointer<Utf16>, Pointer<Utf16>);

// CreateWindowExW(dwExStyle, className, windowName, dwStyle, x, y, w, h,
//                 parent, menu, instance, param)  -> 12 arguments.
typedef _CreateWindowExNative = IntPtr Function(Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32,
    Int32, Int32, Int32, Int32, IntPtr, IntPtr, IntPtr, IntPtr);
typedef _CreateWindowExDart = int Function(
    int, Pointer<Utf16>, Pointer<Utf16>, int, int, int, int, int, int, int, int, int);

// MoveWindow(hwnd, x, y, w, h, repaint)  -> 6 arguments (the last one is BOOL,
// which is why the earlier 5-argument version failed to analyse).
typedef _MoveWindowNative = Int32 Function(IntPtr, Int32, Int32, Int32, Int32, Int32);
typedef _MoveWindowDart = int Function(int, int, int, int, int, int);

typedef _SetWindowPosNative = Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32);
typedef _SetWindowPosDart = int Function(int, int, int, int, int, int, int);

/// Win32 plumbing for hosting mpv inside our Flutter window.
///
/// Why a container window instead of passing the runner handle straight to mpv:
/// `wid` semantics differ between mpv builds — some create a *child* window
/// under the given handle, others draw into it directly. A container makes both
/// cases harmless: video can never land on the Flutter surface, and we always
/// have one rectangle we own and can move, hide and re-fit.
///
/// This mirrors Zerk Play 2.0's `VideoHost` (a method channel to
/// `windows/runner/video_host.cpp`) with one difference: the container is
/// created here through FFI, so the CI-generated runner template stays stock.
class Win32 {
  Win32._();

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  /// Class name registered by the stock Flutter Windows runner.
  static const String runnerClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

  /// Class name of the child window the embedder draws into.
  static const String flutterViewClass = 'FLUTTERVIEW';

  static const String _hostClass = 'STATIC';

  static const int _wsChild = 0x40000000;
  static const int _wsClipSiblings = 0x04000000;
  static const int _wsClipChildren = 0x02000000;
  static const int _hwndTop = 0;
  static const int _swpNoSize = 0x0001;
  static const int _swpNoMove = 0x0002;
  static const int _swpNoActivate = 0x0010;
  static const int _swpShowWindow = 0x0040;
  static const int _swShow = 5;
  static const int _swHide = 0;

  static final _FindWindowDart _findWindow =
      _user32.lookupFunction<_FindWindowNative, _FindWindowDart>('FindWindowW');

  static final _CreateWindowExDart _createWindowEx =
      _user32.lookupFunction<_CreateWindowExNative, _CreateWindowExDart>('CreateWindowExW');

  static final int Function(int) _destroyWindow =
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyWindow');

  static final int Function(int, Pointer<_Rect>) _getClientRect = _user32
      .lookupFunction<Int32 Function(IntPtr, Pointer<_Rect>), int Function(int, Pointer<_Rect>)>(
          'GetClientRect');

  static final _MoveWindowDart _moveWindow =
      _user32.lookupFunction<_MoveWindowNative, _MoveWindowDart>('MoveWindow');

  static final _SetWindowPosDart _setWindowPos =
      _user32.lookupFunction<_SetWindowPosNative, _SetWindowPosDart>('SetWindowPos');

  static final int Function(int, int) _showWindow =
      _user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');

  static final int Function(int) _isWindow =
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindow');

  static final int Function(int, Pointer<Utf16>, int) _getClassNameW = _user32
      .lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, int)>('GetClassNameW');

  static final int Function(int, Pointer<NativeFunction<_EnumProcNative>>, int) _enumChildWindows =
      _user32.lookupFunction<Int32 Function(IntPtr, Pointer<NativeFunction<_EnumProcNative>>, IntPtr),
              int Function(int, Pointer<NativeFunction<_EnumProcNative>>, int)>('EnumChildWindows');

  static final int Function(Pointer<NativeFunction<_EnumProcNative>>, int) _enumWindows =
      _user32.lookupFunction<Int32 Function(Pointer<NativeFunction<_EnumProcNative>>, IntPtr),
          int Function(Pointer<NativeFunction<_EnumProcNative>>, int)>('EnumWindows');

  static final int Function(int, Pointer<Uint32>) _getWindowThreadProcessId = _user32
      .lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>(
          'GetWindowThreadProcessId');

  static final int Function() _getCurrentProcessId =
      _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');

  static final int Function(Pointer<Utf16>) _getModuleHandle = _kernel32
      .lookupFunction<IntPtr Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>(
          'GetModuleHandleW');

  /// Finds our own top-level window.
  ///
  /// The stock runner registers [runnerClass], which is unique to our process,
  /// so no title matching (and no "did I grab somebody else's window" risk) is
  /// involved. A pid-checked enumeration is the fallback for custom runners.
  static int? appWindow() {
    if (!Platform.isWindows) {
      return null;
    }
    final int self = _getCurrentProcessId();
    final Pointer<Utf16> className = runnerClass.toNativeUtf16();
    try {
      final int byClass = _findWindow(className, nullptr);
      if (byClass != 0 && _windowProcessId(byClass) == self) {
        return byClass;
      }
    } finally {
      calloc.free(className);
    }

    int found = 0;
    // `isolateLocal` needs an exceptional return value because the native
    // signature is non-void; 1 means "keep enumerating", which is the safe
    // default if the trampoline is ever torn down mid-call.
    final NativeCallable<_EnumProcNative> callable =
        NativeCallable<_EnumProcNative>.isolateLocal((int hwnd, int _) {
      if (found != 0) {
        return 0;
      }
      if (_windowProcessId(hwnd) == self) {
        found = hwnd;
        return 0;
      }
      return 1;
    }, exceptionalReturn: 1);
    try {
      _enumWindows(callable.nativeFunction, 0);
    } finally {
      callable.close();
    }
    return found == 0 ? null : found;
  }

  /// Creates the container mpv renders into. Not visible until [setVisible].
  static int? createHost(int parent, WindowBox box) {
    if (!Platform.isWindows || parent == 0 || box.isEmpty) {
      return null;
    }
    final Pointer<Utf16> className = _hostClass.toNativeUtf16();
    try {
      final int handle = _createWindowEx(
        0, // dwExStyle
        className,
        nullptr, // no caption
        _wsChild | _wsClipChildren | _wsClipSiblings,
        box.left,
        box.top,
        box.width,
        box.height,
        parent,
        0, // no menu
        _getModuleHandle(nullptr),
        0, // no param
      );
      return handle == 0 ? null : handle;
    } finally {
      calloc.free(className);
    }
  }

  static void destroy(int hwnd) {
    if (hwnd != 0) {
      _destroyWindow(hwnd);
    }
  }

  static bool isWindow(int hwnd) => hwnd != 0 && _isWindow(hwnd) != 0;

  static int? _windowProcessId(int hwnd) {
    final Pointer<Uint32> pid = calloc<Uint32>();
    try {
      _getWindowThreadProcessId(hwnd, pid);
      return pid.value;
    } finally {
      calloc.free(pid);
    }
  }

  static WindowBox? clientBox(int hwnd) {
    if (hwnd == 0 || _isWindow(hwnd) == 0) {
      return null;
    }
    final Pointer<_Rect> rect = calloc<_Rect>();
    try {
      if (_getClientRect(hwnd, rect) == 0) {
        return null;
      }
      final _Rect value = rect.ref;
      return WindowBox(value.left, value.top, value.right - value.left, value.bottom - value.top);
    } finally {
      calloc.free(rect);
    }
  }

  static String _className(int hwnd) {
    const int capacity = 256;
    final Pointer<Utf16> buffer = calloc<Uint16>(capacity).cast<Utf16>();
    try {
      return _getClassNameW(hwnd, buffer, capacity) <= 0 ? '' : buffer.toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  /// Every direct child of [parent], with class name and client box.
  static List<ChildWindow> children(int parent) {
    final List<ChildWindow> result = <ChildWindow>[];
    final NativeCallable<_EnumProcNative> callable =
        NativeCallable<_EnumProcNative>.isolateLocal((int hwnd, int _) {
      final WindowBox? box = clientBox(hwnd);
      result.add(ChildWindow(hwnd, _className(hwnd), box ?? const WindowBox(0, 0, 0, 0)));
      return 1;
    }, exceptionalReturn: 0);
    try {
      _enumChildWindows(parent, callable.nativeFunction, 0);
    } finally {
      callable.close();
    }
    return result;
  }

  /// The surface mpv actually paints into.
  ///
  /// If mpv created a child under our container we return the widest one; if it
  /// painted into the container itself we return null and the caller keeps using
  /// the container rectangle. Flutter's own view is always excluded.
  static int? videoChild(int parent) {
    int best = 0;
    int bestArea = 0;
    int fallback = 0;
    for (final ChildWindow child in children(parent)) {
      if (child.className == flutterViewClass || child.className == runnerClass) {
        continue;
      }
      if (fallback == 0) {
        fallback = child.handle;
      }
      final int area = child.box.width * child.box.height;
      if (area > bestArea) {
        bestArea = area;
        best = child.handle;
      }
    }
    // A freshly created mpv child reports a 0x0 client rect until it handles its
    // first WM_SIZE. Dropping it left the surface stuck at "none"; returning it
    // lets the caller grow it to the container's client area.
    return best != 0 ? best : (fallback == 0 ? null : fallback);
  }

  /// Fits [hwnd] to [box] and raises it above the Flutter view.
  static bool fit(int hwnd, WindowBox box) {
    if (hwnd == 0 || box.isEmpty || _isWindow(hwnd) == 0) {
      return false;
    }
    final bool moved = _moveWindow(hwnd, box.left, box.top, box.width, box.height, 1) != 0;
    // SWP_NOSIZE and SWP_NOMOVE are mandatory here. Without them SetWindowPos
    // applies the cx/cy arguments (0, 0) and moves the window to the origin,
    // instantly undoing the MoveWindow above — the container collapses to 0x0,
    // mpv's child follows it, and nothing is ever visible.
    _setWindowPos(
      hwnd,
      _hwndTop,
      0,
      0,
      0,
      0,
      _swpNoSize | _swpNoMove | _swpNoActivate | _swpShowWindow,
    );
    return moved;
  }

  /// Puts [hwnd] above its siblings without touching size, position or focus.
  ///
  /// Child windows are siblings of the Flutter view; whichever came last owns
  /// the pixels. Re-raising on every poll is cheap and idempotent, and it
  /// removes a whole class of "the app is running but the picture is black".
  static void raise(int hwnd) {
    if (hwnd == 0 || _isWindow(hwnd) == 0) {
      return;
    }
    _setWindowPos(hwnd, _hwndTop, 0, 0, 0, 0, _swpNoSize | _swpNoMove | _swpNoActivate);
  }

  static void setVisible(int hwnd, {required bool visible}) {
    if (hwnd == 0 || _isWindow(hwnd) == 0) {
      return;
    }
    _showWindow(hwnd, visible ? _swShow : _swHide);
  }
}
