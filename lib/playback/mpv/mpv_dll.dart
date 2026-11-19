import 'dart:ffi';
import 'dart:io';

/// Thrown when the mpv runtime cannot be located. The player page turns this
/// into a readable message instead of dying silently.
class MpvUnavailable implements Exception {
  MpvUnavailable(this.message, {this.tried = const <String>[]});

  final String message;
  final List<String> tried;

  @override
  String toString() => 'MpvUnavailable: $message';
}

/// Locates and opens `libmpv-2.dll`.
///
/// The DLL ships next to the executable (the CI bundle copies it there), so the
/// default Windows loader search is almost always enough; the explicit paths
/// exist to give a useful error when it is missing.
class MpvDll {
  const MpvDll._();

  static DynamicLibrary open() {
    final List<String> tried = <String>[];
    final String exeDir = File(Platform.resolvedExecutable).parent.path;
    final String sep = Platform.pathSeparator;

    for (final String candidate in <String>[
      '$exeDir${sep}libmpv-2.dll',
      '$exeDir${sep}libs${sep}libmpv-2.dll',
      'libmpv-2.dll',
    ]) {
      tried.add(candidate);
      try {
        return DynamicLibrary.open(candidate);
      } on ArgumentError {
        continue;
      }
    }

    throw MpvUnavailable(
      '未找到 libmpv-2.dll。请把它放到程序目录，或运行 tool/fetch_libmpv.dart 下载。',
      tried: tried,
    );
  }
}
