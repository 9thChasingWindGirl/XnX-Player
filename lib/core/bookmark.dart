/// Where playback stopped, and what that is worth keeping.
///
/// The shape and the two thresholds come from the reference build
/// (`Bookmark.h`, `AdvancedSettings.cpp:266-267`,
/// `ApplicationPlayerCallback.cpp:415-424`), because they answer a question
/// that is easy to get wrong: a position is not automatically a resume point.
///
/// Recording every position looks harmless and is not. Stop an episode at 99 %
/// and the next "resume" drags the user to the last ten seconds of the credits;
/// stop it after forty seconds and the shelf claims a progress bar for
/// something nobody watched.
library;

import 'dart:math' as math;

/// What a stored position means.
enum BookmarkKind {
  /// Automatically maintained: where the user stopped.
  resume,

  /// Placed by hand: a moment worth returning to.
  mark,
}

/// One stored position inside one file.
///
/// Kept deliberately close to `CBookmark`: [at] and [total] together are what
/// make the difference between "watched three quarters of it" and "watched
/// three quarters of *something*, we do not know what".
class Bookmark {
  const Bookmark({
    required this.at,
    required this.total,
    this.kind = BookmarkKind.resume,
    this.part = 0,
  });

  /// Where inside the file. Never negative: a finished file has no bookmark.
  final Duration at;

  /// How long the file is. Zero when the backend could not tell us.
  final Duration total;

  final BookmarkKind kind;

  /// Which part of a multi-part item this belongs to (`partNumber` upstream).
  final int part;

  /// Whether the file length is known, which every other judgement depends on.
  bool get isSet => total > Duration.zero;

  /// Upstream's `IsPartWay`: a bookmark that is neither absent nor at zero.
  ///
  /// This is what makes a "continue watching" button meaningful rather than
  /// decorative — a row that offers to resume from 0:00 is a row that will
  /// simply restart the film.
  bool get isPartWay => isSet && at > Duration.zero && at < total;

  /// 0..1, clamped. Zero for an unset bookmark so callers never divide by zero.
  double get fraction => isSet ? (at.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0) : 0.0;

  /// Rounded to whole seconds for storage: sub-second resume points are noise,
  /// and the JSON file stays readable.
  Map<String, Object?> toJson() => <String, Object?>{
    'at': at.inSeconds,
    'total': total.inSeconds,
    if (kind != BookmarkKind.resume) 'kind': kind.name,
    if (part != 0) 'part': part,
  };

  static Bookmark? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? at = raw['at'];
    final Object? total = raw['total'];
    if (at is! num || total is! num) {
      return null;
    }
    final String? kindName = raw['kind'] as String?;
    return Bookmark(
      at: Duration(seconds: at.toInt()),
      total: Duration(seconds: total.toInt()),
      kind: kindName == BookmarkKind.mark.name ? BookmarkKind.mark : BookmarkKind.resume,
      part: (raw['part'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Bookmark && other.at == at && other.total == total && other.kind == kind && other.part == part;

  @override
  int get hashCode => Object.hash(at, total, kind, part);

  @override
  String toString() => 'Bookmark(${kind.name} ${at.inSeconds}s / ${total.inSeconds}s)';
}

/// What to do with a position the player just reported.
enum BookmarkDecision {
  /// Forget about it. Too early to mean anything.
  ignore,

  /// Keep it as the resume point.
  resume,

  /// Past the end threshold: the item is finished, so the resume point goes.
  finished,
}

/// The two thresholds, and the rule that applies them.
///
/// Named rather than inlined so a settings row can expose them later without
/// hunting through the player.
abstract final class BookmarkPolicy {
  const BookmarkPolicy._();

  /// Below this many seconds the item counts as "not really started".
  ///
  /// Upstream default is three minutes (`m_videoIgnoreSecondsAtStart`). Long
  /// enough to survive a mis-click and a trailer, short enough that someone who
  /// watched five minutes keeps their place.
  static const Duration minStart = Duration(minutes: 3);

  /// Within this fraction of the end the item counts as watched.
  ///
  /// Upstream default is 8 % (`m_videoIgnorePercentAtEnd`): credits are not
  /// part of the film, and asking someone to sit through them to clear a
  /// progress bar is how a "continue watching" row fills with things that are
  /// already done.
  static const double endFraction = 0.08;

  /// Decides what a reported position means.
  ///
  /// The order matters: the end test runs before the start test, so a very
  /// short item (a two-minute clip watched to the end) is finished rather than
  /// ignored.
  static BookmarkDecision decide({
    required Duration position,
    required Duration total,
  }) {
    // A live stream, or a backend that never reported a length. There is no
    // "part way" without a whole.
    if (total <= Duration.zero || position <= Duration.zero) {
      return BookmarkDecision.ignore;
    }
    final int tail = (total.inMilliseconds * endFraction).round();
    if (total - position <= Duration(milliseconds: math.max(0, tail))) {
      return BookmarkDecision.finished;
    }
    if (position < minStart) {
      return BookmarkDecision.ignore;
    }
    return BookmarkDecision.resume;
  }
}
