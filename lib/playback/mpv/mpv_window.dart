import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Resolves the handle of our own top-level window, so mpv can render into the
/// app instead of opening a separate player window.
///
/// Safety matters here: handing mpv a foreign HWND would paint video into
/// somebody else's window, so the process id is verified before returning any
/// handle that did not come from an exact title match.
int? appWindowHandle({String title = 'XnX Player'}) {
  if (!Platform.isWindows) {
    return null;
  }
  try {
    final DynamicLibrary user32 = DynamicLibrary.open('user32.dll');
    final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');

    final int Function(Pointer<Utf16>, Pointer<Utf16>) findWindow =
        user32.lookupFunction<IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
            int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
    final int Function() getForegroundWindow =
        user32.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
    final int Function() getActiveWindow = user32.lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow');
    final int Function(int, Pointer<Uint32>) getWindowThreadProcessId =
        user32.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>(
      'GetWindowThreadProcessId',
    );
    final int Function() getCurrentProcessId = kernel32.lookupFunction<Uint32 Function(), int Function()>(
      'GetCurrentProcessId',
    );

    final Pointer<Utf16> titlePtr = title.toNativeUtf16();
    try {
      final int byTitle = findWindow(nullptr, titlePtr);
      if (byTitle != 0) {
        return byTitle;
      }
    } finally {
      calloc.free(titlePtr);
    }

    final int self = getCurrentProcessId();
    for (final int candidate in <int>[getForegroundWindow(), getActiveWindow()]) {
      if (candidate == 0) {
        continue;
      }
      final Pointer<Uint32> pidPtr = calloc<Uint32>();
      try {
        getWindowThreadProcessId(candidate, pidPtr);
        if (pidPtr.value == self) {
          return candidate;
        }
      } finally {
        calloc.free(pidPtr);
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}
