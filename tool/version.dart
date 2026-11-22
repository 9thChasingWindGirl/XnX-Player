/// Version resolution for local builds and CI.
///
/// One base version (`X.YY.ZZ`) lives in `VERSION`; the channel is a dot
/// segment added at build time (`X.YY.ZZ.Dev`, `X.YY.ZZ.Beta`). Promotion
/// rewrites only that channel segment — beta and stable never bump the number
/// themselves; they inherit exactly what dev produced.
///
/// `ZZ` is the hotfix iteration counter, and `beta:VERSION.latest` is where
/// it lives. Every successful dev build writes its version back there; the
/// next build reads that record and advances `ZZ` by one iteration
/// (`0.00.05` → `0.00.06`). A successful build *is* one hotfix iteration —
/// the number expresses how many times the hotfix version moved forward, not
/// how many builds ran: failed or cancelled builds write nothing back and
/// the number stays. This replaced an earlier scheme that counted commits
/// since `VERSION` changed, which inflated the number a stable release
/// inherits during heavy development.
///
/// Carrying: `YY` and `ZZ` both cap at 99. An iteration past `ZZ = 99` rolls
/// into the minor (`0.00.99` → `0.01.00`), and a minor at 99 rolls into `X`
/// (`0.99.99` → `1.00.00`) — the pair behaves like two-digit decimal fields,
/// not independent counters that error out. CI never rewrites `VERSION`, so
/// after an automatic carry the record's `base:` line still matches it and
/// iterations continue from the carried number.
///
/// `X` is a breaking change, `YY` the two-digit minor iteration and `ZZ` the
/// two-digit hotfix, so versions always sort as strings of equal length.
///
///   dart run tool/version.dart show
///   dart run tool/version.dart bump minor
///   dart run tool/version.dart resolve --base 0.02.00 --channel dev --prev 0.00.15.Dev --prev-base 0.00.00
///   dart run tool/version.dart auto --write
library;

import 'dart:io';

void main(List<String> argv) {
  final String command = argv.isEmpty ? 'show' : argv.first;
  final Map<String, String> flags = <String, String>{};
  for (int i = 1; i < argv.length; i++) {
    final String arg = argv[i];
    if (arg.startsWith('--')) {
      final String key = arg.substring(2);
      if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
        flags[key] = argv[++i];
      } else {
        flags[key] = 'true';
      }
    } else {
      flags['part'] = arg;
    }
  }

  switch (command) {
    case 'show':
      stdout.writeln(_normalize(_readBase()));
      break;
    case 'resolve':
      final String base = _normalize(flags['base'] ?? _readBase());
      final String channel = (flags['channel'] ?? 'dev').toLowerCase();
      stdout.writeln(
        _resolve(
          base,
          channel,
          previous: flags['prev'],
          previousBase: flags['prev-base'],
        ),
      );
      break;
    case 'bump':
      final String part = (flags['part'] ?? 'patch').toLowerCase();
      final String next = _bump(_normalize(flags['base'] ?? _readBase()), part);
      _writeBase(next);
      _writePubspec(next);
      stdout.writeln(next);
      break;
    case 'auto':
      final _AutoVersion auto = _auto(_normalize(flags['base'] ?? _readBase()));
      if (flags['write'] == 'true') {
        _writeBase(auto.version);
        _writePubspec(auto.version);
      }
      stdout.writeln(auto.version);
      stderr.writeln('reason: ${auto.reason}');
      break;
    default:
      stderr.writeln('usage: version.dart <show|resolve|bump|auto> [flags]');
      stderr.writeln('  resolve: --base X.YY.ZZ --channel dev|beta|stable');
      stderr.writeln('           [--prev LAST_DEV --prev-base BASE]');
      exitCode = 64;
      break;
  }
}

/// Channel is a dot segment, not a SemVer prerelease: `0.00.03.Dev`,
/// `0.00.03.Beta`, `0.00.03`. Promotion only rewrites this segment; the build
/// number is not part of the version.
///
/// [previous] is the version the last successful dev build recorded in
/// `beta:VERSION.latest` (possibly empty on a fresh repository); [previousBase]
/// is the `base:` line next to it. Dev advances the hotfix iteration by one
/// from that record; every other channel returns the base untouched, so
/// beta/stable stay byte-identical to the dev artifact they were promoted
/// from.
String _resolve(
  String base,
  String channel, {
  String? previous,
  String? previousBase,
}) {
  switch (channel) {
    case 'stable':
      return base;
    case 'beta':
      return '$base.Beta';
    case 'dev':
      return '${_nextDev(base, previous, previousBase: previousBase)}.Dev';
    default:
      stderr.writeln('unknown channel "$channel", falling back to dev');
      return '${_nextDev(base, previous, previousBase: previousBase)}.Dev';
  }
}

/// The next hotfix iteration: the recorded version advanced by one.
///
/// "The base changed" needs the base the record was built from, which is why
/// `VERSION.latest` carries a `base:` line. Comparing versions alone cannot
/// work: a normal run of iterations (`VERSION = 0.00.00`, record
/// `0.00.15.Dev`) differs from the base in every digit, while a manual hotfix
/// bump (`0.00.05` → `0.00.10`) may differ in none. With the base line, any
/// change to `VERSION` restarts the counter exactly at the new base. A
/// legacy single-line record (written before the base line existed) falls
/// back to comparing `X.YY` only.
///
/// `previous` carrying a channel suffix (`0.00.15.Dev`) is fine; [parts]
/// ignores it.
String _nextDev(String base, String? previous, {String? previousBase}) {
  final List<int> current = _parts(base);
  final String? prev = previous?.trim();
  if (prev == null || prev.isEmpty) {
    // Fresh repository, or the record was deleted on purpose: the first
    // iteration ships exactly the base.
    return base;
  }
  final List<int> last = _parts(prev);
  final String? recorded = previousBase?.trim();
  final bool sameBase;
  if (recorded != null && recorded.isNotEmpty) {
    final List<int> built = _parts(recorded);
    sameBase = built[0] == current[0] &&
        built[1] == current[1] &&
        built[2] == current[2];
  } else {
    sameBase = last[0] == current[0] && last[1] == current[1];
  }
  if (!sameBase) {
    // VERSION changed since the last iteration: restart from the new base.
    return base;
  }
  return _carry(last);
}

/// One iteration forward with two-digit decimal carry: `…99` rolls into the
/// next minor, `…99.99` into the next major — `0.00.99` → `0.01.00`,
/// `0.99.99` → `1.00.00`. No error path: the counter cannot overflow, it
/// moves into the wider field.
String _carry(List<int> v) {
  int hotfix = v[2] + 1;
  int minor = v[1];
  int major = v[0];
  if (hotfix > 99) {
    hotfix = 0;
    minor += 1;
    if (minor > 99) {
      minor = 0;
      major += 1;
    }
  }
  return _format(major, minor, hotfix);
}

String _bump(String base, String part) {
  final List<int> parts = _parts(base);
  int major = parts[0];
  int minor = parts[1];
  int patch = parts[2];
  switch (part) {
    case 'major':
      major++;
      minor = 0;
      patch = 0;
      break;
    case 'minor':
      minor++;
      patch = 0;
      break;
    default:
      patch++;
      break;
  }
  return _format(major, minor, patch);
}

/// `X.YY.ZZ`: minor and hotfix are always two digits.
String _format(int major, int minor, int patch) =>
    '$major.${minor.toString().padLeft(2, '0')}.${patch.toString().padLeft(2, '0')}';

String _normalize(String raw) {
  final List<int> parts = _parts(raw);
  return _format(parts[0], parts[1], parts[2]);
}

List<int> _parts(String raw) {
  final String body = raw
      .trim()
      .replaceFirst(RegExp(r'^v'), '')
      .split(RegExp(r'[-+]'))
      .first;
  final List<int> out = <int>[];
  for (final String piece in body.split('.')) {
    out.add(int.tryParse(piece) ?? 0);
  }
  while (out.length < 3) {
    out.add(0);
  }
  return out.sublist(0, 3);
}

String _readBase() {
  final File file = File('VERSION');
  if (!file.existsSync()) {
    return '0.0.0';
  }
  final String value = file.readAsStringSync().trim();
  return value.isEmpty ? '0.0.0' : value;
}

void _writeBase(String version) {
  File('VERSION').writeAsStringSync('$version\n');
}

void _writePubspec(String version) {
  final File file = File('pubspec.yaml');
  if (!file.existsSync()) {
    return;
  }
  final String source = file.readAsStringSync();
  final RegExp pattern = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true);
  final RegExpMatch? match = pattern.firstMatch(source);
  final int build = match == null
      ? 1
      : (int.tryParse(match.group(1)!.split('+').last) ?? 1);
  final String line = 'version: $version+$build';
  final String next = match == null
      ? '$source\n$line\n'
      : source.replaceFirst(pattern, line);
  file.writeAsStringSync(next);
}

class _AutoVersion {
  const _AutoVersion(this.version, this.reason);

  final String version;
  final String reason;
}

_AutoVersion _auto(String base) {
  String? tag;
  final ProcessResult describe = _git(<String>[
    'describe',
    '--tags',
    '--abbrev=0',
    '--match',
    'v*',
  ]);
  if (describe.exitCode == 0) {
    tag = (describe.stdout as String).trim();
  }

  final String range = tag == null ? 'HEAD' : '$tag..HEAD';
  final ProcessResult log = _git(<String>['log', range, '--pretty=%s%x1f%b']);
  final List<String> messages = log.exitCode == 0
      ? (log.stdout as String)
          .split('\n')
          .where((String line) => line.trim().isNotEmpty)
          .toList(growable: false)
      : const <String>[];

  if (messages.isEmpty) {
    return _AutoVersion(base, 'no commits since ${tag ?? 'the start'}');
  }

  bool breaking = false;
  bool feature = false;
  for (final String message in messages) {
    if (message.contains('BREAKING CHANGE') ||
        RegExp(r'^\w+(\([^)]*\))?!:', multiLine: true).hasMatch(message)) {
      breaking = true;
    }
    if (RegExp(r'^feat(\([^)]*\))?:', multiLine: true).hasMatch(message)) {
      feature = true;
    }
  }
  final String part = breaking ? 'major' : (feature ? 'minor' : 'patch');
  final String start = tag == null ? base : _normalize(tag);
  return _AutoVersion(_bump(start, part), '$part bump from ${messages.length} commit(s)');
}

ProcessResult _git(List<String> args) {
  try {
    return Process.runSync('git', args, runInShell: true);
  } on Object catch (error) {
    return ProcessResult(0, 1, '', '$error');
  }
}
