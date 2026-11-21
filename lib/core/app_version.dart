import 'dart:io';

import 'strings.dart';

/// The version this build was packaged as.
///
/// Precedence: `version.txt` beside the executable (written by CI) → `VERSION`
/// in the working directory (useful for `flutter run`) → the compiled
/// `APP_VERSION` fallback.
String resolveAppVersion() {
  final String compiled = S.appVersion;
  for (final String path in _candidates()) {
    try {
      final File file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      final String text = file.readAsStringSync().trim();
      if (text.isEmpty) {
        continue;
      }
      return text.split(RegExp(r'\s+')).first;
    } on Object {
      // Try the next candidate.
    }
  }
  return compiled;
}

List<String> _candidates() {
  final List<String> out = <String>[];
  final String separator = Platform.pathSeparator;
  try {
    final String exeDir = File(Platform.resolvedExecutable).parent.path;
    out.add('$exeDir${separator}version.txt');
    out.add('$exeDir${separator}VERSION');
  } on Object {
    // resolvedExecutable is always available, but never let it break startup.
  }
  final String cwd = Directory.current.path;
  out.add('$cwd${separator}version.txt');
  out.add('$cwd${separator}VERSION');
  return out;
}
