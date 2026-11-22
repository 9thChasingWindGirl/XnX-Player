import 'dart:io';

import 'subtitle_rules.dart';

/// Result of scanning one video's neighbourhood for external subtitles.
///
/// Deliberately not part of [MediaItem]: a library of 400 titles should not
/// carry 400 subtitle lists around. The player scans the one file it is about
/// to open and mounts the matches.
class SubtitleFinder {
  const SubtitleFinder._();

  /// Looks in the video's folder, its same-named companion folder and the
  /// conventional `subs/`-style subfolders (`Util.cpp:1976-2005, 2305`).
  ///
  /// `maxDepth` keeps a symlink loop or a deeply nested media tree from
  /// turning a play request into a filesystem crawl.
  static Future<List<SubtitleCandidate>> find(
    String videoPath, {
    int maxFiles = 200,
  }) async {
    final File video = File(videoPath);
    final String videoName = video.uri.pathSegments.last;
    final String parent = video.parent.path;
    final List<SubtitleCandidate> out = <SubtitleCandidate>[];
    int visited = 0;

    Future<void> scan(Directory dir, int depth) async {
      if (visited >= maxFiles || depth > 2) {
        return;
      }
      try {
        await for (final FileSystemEntity entity
            in dir.list(recursive: false, followLinks: false)) {
          if (visited >= maxFiles) {
            return;
          }
          if (entity is File) {
            visited++;
            final String name = entity.uri.pathSegments.last;
            // Skip the video itself and anything that is not a subtitle.
            if (name == videoName || !SubtitleRules.isSubtitle(name)) {
              continue;
            }
            if (!SubtitleRules.matches(videoName, name)) {
              continue;
            }
            out.add(SubtitleRules.describe(name, entity.path));
            continue;
          }
          if (entity is Directory && depth < 2) {
            final String folder = entity.uri.pathSegments.last.toLowerCase();
            // Kodi scans a folder named after the video, plus the known
            // subtitle folder names. Other folders are left alone.
            if (folder == SubtitleRules.stem(videoName) ||
                SubtitleRules.companionDirs.contains(folder)) {
              await scan(entity, depth + 1);
            }
          }
        }
      } on Object {
        // An unreadable sibling must not stop playback.
      }
    }

    await scan(Directory(parent), 0);
    out.sort((SubtitleCandidate a, SubtitleCandidate b) {
      final int byFlag = a.priority.compareTo(b.priority);
      if (byFlag != 0) {
        return byFlag;
      }
      return a.path.compareTo(b.path);
    });
    return out;
  }
}
