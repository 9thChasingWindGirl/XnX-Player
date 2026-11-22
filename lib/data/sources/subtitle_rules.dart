import 'dart:io';

/// Rules for finding external subtitle files next to a video.
///
/// Transcribed from Kodi (`Util.cpp`, `AdvancedSettings.cpp`,
/// `DVDFactorySubtitle.cpp`): the extensions, the companion-directory names,
/// and the "video name is a prefix of the subtitle name" match. Only the
/// rules are borrowed — Kodi's scan framework is C++/CFileItem and does not
/// belong in a Flutter app.
abstract final class SubtitleRules {
  /// `AdvancedSettings.cpp:582-583`, de-duplicated (Kodi lists `.ssa` twice).
  /// Archive extensions are deliberately excluded: they are scanned as
  /// containers by Kodi, not passed to `sub-add` verbatim.
  static const Set<String> extensions = <String>{
    'utf', 'utf8', 'utf-8', 'sub', 'srt', 'smi', 'rt', 'txt',
    'ssa', 'aqt', 'jss', 'ass', 'vtt', 'sup',
  };

  /// Kodi treats `.idx` as the index half of a VobSub pair.
  static const String vobSubIndex = 'idx';

  /// `Util.cpp:2305`. Kodi looks in the video's own folder and in a
  /// same-named companion folder; these are the conventional subfolders.
  static const Set<String> companionDirs = <String>{
    'subs', 'subtitles', 'vobsubs', 'sub', 'vobsub', 'subtitle',
  };

  /// `Util.cpp:2408-2414` — flags embedded in a subtitle file name.
  static const Map<String, SubtitleFlag> flags = <String, SubtitleFlag>{
    'default': SubtitleFlag.defaultTrack,
    'forced': SubtitleFlag.forced,
    'original': SubtitleFlag.original,
    'impaired': SubtitleFlag.hearingImpaired,
    'sdh': SubtitleFlag.hearingImpaired,
  };

  static bool isSubtitle(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return false;
    }
    final String ext = name.substring(dot + 1).toLowerCase();
    return extensions.contains(ext) || ext == vobSubIndex;
  }

  /// Strips the extension and lowercases, so matching is case-insensitive.
  static String stem(String name) {
    final int dot = name.lastIndexOf('.');
    final String base = dot > 0 ? name.substring(0, dot) : name;
    return base.toLowerCase();
  }

  /// Kodi's `ScanPathsForAssociatedItems` (`Util.cpp:2009-2051`): the video
  /// name is a *prefix* of the subtitle name, so `Movie.en.srt` matches
  /// `Movie.mkv`. The extra boundary check avoids `Movie2.srt` matching
  /// `Movie.mkv`, which Kodi's plain prefix match would allow.
  static bool matches(String videoName, String subtitleName) {
    final String video = stem(videoName);
    final String sub = stem(subtitleName);
    if (sub == video) {
      return true;
    }
    if (!sub.startsWith(video) || sub.length <= video.length) {
      return false;
    }
    final String next = sub[video.length];
    return next == '.' || next == '-' || next == '_' || next == ' ';
  }

  /// `Util.cpp:2479-2501`: tokens nearest the extension win, so a name like
  /// `Movie.en.forced.srt` reads "forced" then "en" as the language.
  static SubtitleCandidate describe(String name, String path) {
    final String base = stem(name);
    final RegExp separators = RegExp(r'[._\- ]');
    final List<String> tokens = base.split(separators)
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);

    SubtitleFlag flag = SubtitleFlag.none;
    String? language;
    final List<String> label = <String>[];
    for (int i = tokens.length - 1; i >= 0; i--) {
      final String token = tokens[i];
      final SubtitleFlag? hit = flags[token];
      if (hit != null) {
        if (flag == SubtitleFlag.none) {
          flag = hit;
        }
        continue;
      }
      // A 2-3 letter trailing token is Kodi's language convention.
      if (language == null && token.length >= 2 && token.length <= 3) {
        language = token;
        continue;
      }
      label.insert(0, token);
    }
    return SubtitleCandidate(
      path: path,
      language: language,
      flag: flag,
      name: label.join(' '),
    );
  }

  /// `DVDFactorySubtitle.cpp:47-79`, first 256 lines are enough for sniffing.
  /// Used only for diagnostics — mpv decides the real demuxer.
  static SubtitleFormat? detectFormat(String head) {
    final String sample = head.length > 4096 ? head.substring(0, 4096) : head;
    if (RegExp(r'^\s*\{\d+\}\{', multiLine: true).hasMatch(sample)) {
      return SubtitleFormat.microdvd;
    }
    if (RegExp(r'^\s*\[\d+\]\[\d+\]', multiLine: true).hasMatch(sample)) {
      return SubtitleFormat.mpl2;
    }
    if (sample.contains('-->')) {
      return SubtitleFormat.subRip;
    }
    if (RegExp(r'ScriptType:\s*v4\.00', caseSensitive: false).hasMatch(sample) ||
        sample.contains('[Events]') ||
        RegExp(r'^Dialogue:', multiLine: true).hasMatch(sample)) {
      return SubtitleFormat.ass;
    }
    if (RegExp(r'^WEBVTT', multiLine: true).hasMatch(sample)) {
      return SubtitleFormat.webVtt;
    }
    if (RegExp(r'<SAMI>', caseSensitive: false).hasMatch(sample)) {
      return SubtitleFormat.sami;
    }
    return null;
  }
}

enum SubtitleFlag { none, defaultTrack, forced, original, hearingImpaired }

enum SubtitleFormat { microdvd, mpl2, subRip, ass, webVtt, sami }

class SubtitleCandidate {
  const SubtitleCandidate({
    required this.path,
    this.language,
    this.flag = SubtitleFlag.none,
    this.name = '',
  });

  final String path;
  final String? language;
  final SubtitleFlag flag;
  final String name;

  /// `forced` first, then default, then the rest — the order mpv should try
  /// when several subtitle tracks match the same video.
  int get priority => switch (flag) {
        SubtitleFlag.forced => 0,
        SubtitleFlag.defaultTrack => 1,
        SubtitleFlag.hearingImpaired => 2,
        SubtitleFlag.original => 3,
        SubtitleFlag.none => 4,
      };

  @override
  String toString() => 'SubtitleCandidate(${File(path).uri.pathSegments.last}, '
      'lang=$language, flag=$flag)';
}
