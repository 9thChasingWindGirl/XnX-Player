/// What a stop position is worth keeping.
///
/// The two thresholds, and the order they are applied in, come from the
/// reference build (`AdvancedSettings.cpp:266-267` and
/// `ApplicationPlayerCallback.cpp:415-424`), because they answer a question
/// that is easy to get wrong: a position is not automatically a resume point.
///
/// Recording every position looks harmless and is not. Stop an episode at 99 %
/// and the next "resume" drags the user to the last ten seconds of the credits;
/// stop it after forty seconds and the shelf claims a progress bar for
/// something nobody watched.
///
/// Deliberately *not* a port of `CBookmark`. That class exists because Kodi's
/// video database stores a type, a part number, a saved player state and a
/// thumbnail path per bookmark, and needs one type to carry them. Here an item
/// has a single duration and everything else comes from the item, so mirroring
/// the shape would produce a class whose fields are always empty — and a type
/// that promises fields the code never fills is worse than no type at all.
library;

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
  /// Upstream default is three minutes (`m_videoIgnoreSecondsAtStart`: long
  /// enough to survive a mis-click and a trailer, short enough that someone who
  /// watched five minutes keeps their place).
  static const Duration minStart = Duration(minutes: 3);

  /// Within this fraction of the end the item counts as watched.
  ///
  /// Upstream default is 8 % (`m_videoIgnorePercentAtEnd`): credits are not
  /// part of the film, and asking someone to sit through them to clear a
  /// progress bar is how a "continue watching" row fills with finished items.
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
    final Duration tail = Duration(
      milliseconds: (total.inMilliseconds * endFraction).round(),
    );
    if (total - position <= tail) {
      return BookmarkDecision.finished;
    }
    if (position < minStart) {
      return BookmarkDecision.ignore;
    }
    return BookmarkDecision.resume;
  }
}
