/// Version resolution for local builds and CI.
///
/// One base version (`X.YY.ZZ`) lives in `VERSION`; the channel is a dot
/// segment added at build time (`X.YY.ZZ.Dev`, `X.YY.ZZ.Beta`). Promotion
/// rewrites only that channel segment — beta and stable never bump the number
/// themselves; they inherit exactly what dev produced.
///
/// The `YY`/`ZZ` pair is a counter, not a per-build bump: the automatic dev
/// build adds the number of commits made since `VERSION` last changed to `ZZ`.
/// So `VERSION = 0.00.00` yields `0.00.00.Dev` on the commit that set it,
/// `0.00.01.Dev` after the next commit, and so on. Only the dev channel does
/// this; beta/stable keep the resulting number as-is.
///
/// `X` is a breaking change, `YY` the two-digit minor iteration and `ZZ` the
/// two-digit hotfix, so versions always sort as strings of equal length.
///
///   dart run tool/version.dart show
///   dart run tool/version.dart bump minor
///   dart run tool/version.dart resolve --base 0.02.00 --channel dev --commits 3
///   dart run tool/version.dart auto --write
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
      final int commits = int.tryParse(flags['commits'] ?? '0') ?? 0;
      stdout.writeln(_resolve(base, channel, commits: commits));
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
      exitCode = 64;
      break;
  }
}

/// Channel is a dot segment, not a SemVer prerelease: `0.00.03.Dev`,
/// `0.00.03.Beta`, `0.00.03`. Promotion only rewrites this segment; the build
/// number is not part of the version.
///
/// [commits] is the number of commits since `VERSION` last changed and is added
/// to `ZZ` for the dev channel only — beta/stable must stay byte-identical to
/// the dev artifact they were promoted from.
String _resolve(String base, String channel, {int commits = 0}) {
  switch (channel) {
    case 'stable':
      return base;
    case 'beta':
      return '$base.Beta';
    case 'dev':
      return '${_addHotfix(base, commits)}.Dev';
    default:
      stderr.writeln('unknown channel "$channel", falling back to dev');
      return '${_addHotfix(base, commits)}.Dev';
  }
}

String _addHotfix(String base, int commits) {
  if (commits <= 0) {
    return base;
  }
  final List<int> parts = _parts(base);
  return _format(parts[0], parts[1], parts[2] + commits);
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
