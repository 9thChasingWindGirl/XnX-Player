import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// A transparent child window that sits *above* the mpv video surface and is
/// painted entirely from Dart.
///
/// This is the escape hatch from mpv's colour pipeline. Everything mpv draws —
/// including its own OSD — is adapted into the swapchain's colour space, so
/// under HDR passthrough the chrome is rendered through PQ and its whites land
/// on the SDR reference (≈203 cd/m²). A separate window is composited by DWM
/// as plain 8-bit SDR content, which is exactly what "the OSD must not be
/// touched by the picture" requires.
///
/// The layer is deliberately a *pure display* surface: its window procedure
/// answers `HTTRANSPARENT` for every hit-test, so pointer input falls through
/// and keeps flowing into the Flutter view, which is the one place that sees
/// and forwards mouse events in this embedding. The chrome's interactions live
/// in `player_page.dart`'s pointer forwarder — no second input channel.
final class OsdLayer {
  OsdLayer._(this._hwnd, this._width, this._height);

  final int _hwnd;
  int _width;
  int _height;

  int? _dib;
  Pointer<Uint8>? _dibBits;
  int? _dibDc;

  static const String className = 'XNX_OSD_LAYER';
  static bool _classRegistered = false;

  // --- Win32 --------------------------------------------------------------
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final DynamicLibrary _gdi32 = DynamicLibrary.open('gdi32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static const int _wsChild = 0x40000000;
  static const int _wsClipSiblings = 0x04000000;
  static const int _wsExLayered = 0x00080000;
  static const int _wmNcHitTest = 0x0084;
  static const int _htTransparent = -1;
  static const int _ulwAlpha = 0x0002;
  static const int _swShow = 5;
  static const int _swHide = 0;

  // The window procedure is a plain native pointer from [Pointer.fromFunction]
  // — the CI SDK predates `NativeCallable.receiver`, and a listener cannot
  // serve WM_NCHITTEST anyway because its return value must be decided inside
  // the dispatch. The procedure never touches Dart: it returns HTTRANSPARENT
  // for hit-tests and defers everything else to DefWindowProc.
  static int _globalWndProc(int hwnd, int msg, int wParam, int lParam) => msg == _wmNcHitTest
      ? _htTransparent
      : _defWindowProc(hwnd, msg, wParam, lParam);

  static final Pointer<NativeFunction<Int64 Function(IntPtr, Uint32, IntPtr, IntPtr)>>
      _proc = Pointer.fromFunction<Int64 Function(IntPtr, Uint32, IntPtr, IntPtr)>(
          _globalWndProc, 0);

  static final int Function(Pointer<_WndClassEx>) _registerClass = _user32
      .lookupFunction<Int32 Function(Pointer<_WndClassEx>), int Function(
          Pointer<_WndClassEx>)>('RegisterClassExW');

  static final int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int, int, int, int, int,
          int, int, int) _createWindowEx =
      _user32.lookupFunction<IntPtr Function(Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32, Int32,
              Int32, Int32, Int32, IntPtr, IntPtr, IntPtr, IntPtr),
          int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int, int, int, int, int, int, int,
              int)>('CreateWindowExW');

  static final int Function(int) _destroyWindow =
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyWindow');

  static final int Function(int) _isWindow =
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindow');

  static final int Function(int, int, int, int, int) _moveWindow = _user32
      .lookupFunction<Int32 Function(IntPtr, Int32, Int32, Int32, Int32, Int32), int Function(
          int, int, int, int, int, int)>('MoveWindow');

  static final int Function(int, int) _showWindow =
      _user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');

  static final int Function(int, int, int, int) _defWindowProc = _user32
      .lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr), int Function(
          int, int, int, int)>('DefWindowProcW');

  static final int Function(Pointer<Utf16>) _getModuleHandle = _kernel32
      .lookupFunction<IntPtr Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>(
          'GetModuleHandleW');

  static final int Function(int, int, int, int, int, int, int, Pointer<_Point>, Pointer<_Point>,
          int, Pointer<_Blend>, int) _updateLayeredWindow = _user32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Pointer<_Point>, Pointer<_Point>, IntPtr,
              Pointer<_Point>, int, Pointer<_Blend>, Uint32),
          int Function(int, int, Pointer<_Point>, Pointer<_Point>, int, Pointer<_Point>, int,
              Pointer<_Blend>, int)>('UpdateLayeredWindow');

  static final int Function(int) _createCompatibleDc = _gdi32
      .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('CreateCompatibleDC');

  static final int Function(int) _deleteDc =
      _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');

  static final int Function(int) _deleteObject =
      _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');

  static final int Function(int, int) _selectObject = _gdi32
      .lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('SelectObject');

  static final int Function(int, Pointer<_BitmapInfo>, int, Pointer<Pointer<Void>>, int, int)
      _createDibSection = _gdi32.lookupFunction<
          IntPtr Function(IntPtr, Pointer<_BitmapInfo>, Uint32, Pointer<Pointer<Void>>, IntPtr,
              int),
          int Function(int, Pointer<_BitmapInfo>, int, Pointer<Pointer<Void>>, int,
              int)>('CreateDIBSection');

  static final int Function(int, int, int, int, int, int, int) _setWindowPos = _user32
      .lookupFunction<Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
          int Function(int, int, int, int, int, int, int)>('SetWindowPos');

  /// Creates the layer as the topmost child of [parent]. Returns null off
  /// Windows or when window creation failed; callers keep using the Lua OSD.
  static OsdLayer? create(int parent, int width, int height) {
    if (!Platform.isWindows || parent == 0) {
      return null;
    }
    _registerClassOnce();
    final int instance = _getModuleHandle(nullptr);
    final Pointer<Utf16> cls = className.toNativeUtf16();
    int hwnd = 0;
    try {
      hwnd = _createWindowEx(
        _wsExLayered,
        cls,
        nullptr,
        _wsChild | _wsClipSiblings,
        0,
        0,
        width,
        height,
        parent,
        0,
        instance,
        0,
      );
    } finally {
      calloc.free(cls);
    }
    if (hwnd == 0) {
      return null;
    }
    return OsdLayer._(hwnd, width, height);
  }

  static void _registerClassOnce() {
    if (_classRegistered) {
      return;
    }
    final Pointer<Utf16> name = className.toNativeUtf16();
    final Pointer<_WndClassEx> wc = calloc<_WndClassEx>();
    try {
      wc.ref
        ..cbSize = sizeOf<_WndClassEx>()
        ..style = 0
        ..lpfnWndProc = _proc.address
        ..hInstance = _getModuleHandle(nullptr)
        ..lpszClassName = name;
      _registerClass(wc);
      _classRegistered = true;
    } finally {
      calloc.free(wc);
      calloc.free(name);
    }
  }

  // --- layout ---------------------------------------------------------------

  void resize(int width, int height) {
    _width = width;
    _height = height;
    _rebuildDib();
    _moveWindow(_hwnd, 0, 0, width, height, 0);
  }

  void show() => _showWindow(_hwnd, _swShow);

  void hide() => _showWindow(_hwnd, _swHide);

  /// Puts the layer back above the mpv child without touching size or focus.
  /// Z-order does not survive fullscreen transitions; raising is idempotent.
  void raise() {
    _setWindowPos(_hwnd, 0 /* HWND_TOP */, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
  }

  void destroy() {
    _freeDib();
    if (_isWindow(_hwnd) != 0) {
      _destroyWindow(_hwnd);
    }
  }

  // --- painting -------------------------------------------------------------

  /// Pushes a premultiplied BGRA frame to the window.
  ///
  /// [pixels] is row-major RGBA with premultiplied alpha — what Flutter's
  /// `Image.toByteData(rawRgba)` produces apart from the R/B swap, done here
  /// in one pass over 1080p-worth of bytes, a few milliseconds of the 33 ms
  /// frame budget at 30 fps.
  void present(Uint8List pixels) {
    final int count = _width * _height * 4;
    final Pointer<Uint8>? bits = _dibBits;
    if (bits == null || pixels.length < count) {
      return;
    }
    final Uint8List dst = bits.asTypedList(count);
    for (int i = 0; i < count; i += 4) {
      final int r = pixels[i];
      dst[i] = pixels[i + 2]; // B
      dst[i + 1] = pixels[i + 1]; // G
      dst[i + 2] = r; // R
      dst[i + 3] = pixels[i + 3]; // A
    }
    final Pointer<_Point> dstPoint = calloc<_Point>();
    final Pointer<_Point> srcPoint = calloc<_Point>();
    final Pointer<_Point> sizePoint = calloc<_Point>();
    final Pointer<_Blend> blend = calloc<_Blend>();
    try {
      dstPoint.ref
        ..x = 0
        ..y = 0;
      srcPoint.ref
        ..x = 0
        ..y = 0;
      sizePoint.ref
        ..x = _width
        ..y = _height;
      blend.ref
        ..blendOp = 0 // AC_SRC_OVER
        ..blendFlags = 0
        ..sourceConstantAlpha = 255
        ..alphaFormat = 1; // AC_SRC_ALPHA — the bitmap is premultiplied
      _updateLayeredWindow(_hwnd, 0, dstPoint, sizePoint, _dibDc ?? 0, srcPoint, 0, blend,
          _ulwAlpha);
    } finally {
      calloc.free(dstPoint);
      calloc.free(srcPoint);
      calloc.free(sizePoint);
      calloc.free(blend);
    }
  }

  void _rebuildDib() {
    _freeDib();
    final Pointer<_BitmapInfo> bmi = calloc<_BitmapInfo>();
    try {
      bmi.ref.bmiHeader
        ..biSize = sizeOf<_BitmapInfoHeader>()
        ..biWidth = _width
        ..biHeight = -_height // top-down
        ..biPlanes = 1
        ..biBitCount = 32
        ..biCompression = 0 // BI_RGB
        ..biSizeImage = 0;
      final Pointer<Pointer<Void>> bitsPtr = calloc<Pointer<Void>>();
      try {
        final int dc = _createCompatibleDc(0);
        final int dib = _createDibSection(dc, bmi, 0 /* DIB_RGB_COLORS */, bitsPtr, 0, 0);
        if (dib == 0 || bitsPtr.value == nullptr) {
          _deleteDc(dc);
          return;
        }
        _selectObject(dc, dib);
        _dibDc = dc;
        _dib = dib;
        _dibBits = bitsPtr.value.cast<Uint8>();
      } finally {
        calloc.free(bitsPtr);
      }
    } finally {
      calloc.free(bmi);
    }
  }

  void _freeDib() {
    if (_dibDc != null) {
      _deleteDc(_dibDc!);
      _dibDc = null;
    }
    if (_dib != null) {
      _deleteObject(_dib!);
      _dib = null;
    }
    _dibBits = null;
  }
}

final class _Point extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

final class _Blend extends Struct {
  @Uint8()
  external int blendOp;

  @Uint8()
  external int blendFlags;

  @Uint8()
  external int sourceConstantAlpha;

  @Uint8()
  external int alphaFormat;
}

final class _BitmapInfoHeader extends Struct {
  @Uint32()
  external int biSize;

  @Int32()
  external int biWidth;

  @Int32()
  external int biHeight;

  @Uint16()
  external int biPlanes;

  @Uint16()
  external int biBitCount;

  @Uint32()
  external int biCompression;

  @Uint32()
  external int biSizeImage;

  @Int32()
  external int xPelsPerMeter;

  @Int32()
  external int yPelsPerMeter;

  @Uint32()
  external int clrUsed;

  @Uint32()
  external int clrImportant;
}

final class _BitmapInfo extends Struct {
  external _BitmapInfoHeader bmiHeader;

  @Uint32()
  external int bmiColors;
}

final class _WndClassEx extends Struct {
  @Uint32()
  external int cbSize;

  @Uint32()
  external int style;

  @IntPtr()
  external int lpfnWndProc;

  @Int32()
  external int cbClsExtra;

  @Int32()
  external int cbWndExtra;

  @IntPtr()
  external int hInstance;

  @IntPtr()
  external int hIcon;

  @IntPtr()
  external int hCursor;

  @IntPtr()
  external int hbrBackground;

  @Pointer<Utf16>()
  external Pointer<Utf16> lpszMenuName;

  @Pointer<Utf16>()
  external Pointer<Utf16> lpszClassName;

  @IntPtr()
  external int hIconSm;
}
