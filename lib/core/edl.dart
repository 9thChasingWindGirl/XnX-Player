/// An edit decision list: half-open intervals telling the player to skip or
/// mute parts of a file.
///
/// The shape is Kodi's (`xbmc/video/Edl.h`): every edit is
/// `start, end, action`, actions are CUT / MUTE / COMMBREAK, and only cuts
/// shorten the running time. That matters because it is the de-facto format for
/// sidecar `<video>.edl` files, so anything this app writes can be read by
/// Kodi and by cutting tools — and anything those tools write can be read here.
///
/// Two coordinate systems are in play and they are *not* interchangeable:
///
/// * **source time** — the timeline inside the container, which is what mpv
///   reports as `time-pos` and what `Duration` from a demuxer means;
/// * **timeline time** — the running time a viewer experiences, i.e. source
///   time minus every cut that precedes it.
///
/// A cut is invisible: source 10–20 s never plays, so timeline 10 s *is* source
/// 20 s. [sourceToTimeline] and [timelineToSource] convert between the two.
/// Mutes and commercial breaks keep the timeline intact — they only silence the
/// audio — so they take no part in that arithmetic.
///
/// This type is immutable and value-comparable: two lists with the same edits
/// are `==`, which makes round-tripping through text easy to test.
library;

/// What to do with a marked interval.
enum EdlAction {
  /// Remove the interval from playback entirely.
  cut(0, 'cut'),

  /// Keep the picture, drop the audio.
  mute(1, 'mute'),

  /// An ad break. Kodi mutes these unless configured to cut, and so do we;
  /// the distinct value is kept so the marker can be labelled and so the policy
  /// can change without rewriting the file.
  commercialBreak(2, 'commbreak');

  const EdlAction(this.code, this.key);

  /// The numeric action column of a `.edl` file.
  final int code;

  /// The mnemonic form accepted by hand-written files and by mpv's own tooling.
  final String key;

  /// Whether this action shortens the timeline.
  ///
  /// Only [cut] does. Everything else leaves the duration untouched, which is
  /// why the mapping functions below filter on this instead of switch-casing
  /// each action.
  bool get shiftsTimeline => this == EdlAction.cut;

  /// Whether playback should be silent inside the interval.
  bool get silences => this != EdlAction.cut;

  static EdlAction? fromCode(int code) {
    for (final EdlAction action in values) {
      if (action.code == code) {
        return action;
      }
    }
    return null;
  }

  static EdlAction? fromKey(String key) {
    final String needle = key.trim().toLowerCase();
    for (final EdlAction action in values) {
      if (action.key == needle || action.name.toLowerCase() == needle) {
        return action;
      }
    }
    // Common spellings found in the wild.
    switch (needle) {
      case 'commercial':
      case 'commercial_break':
      case 'ad':
        return EdlAction.commercialBreak;
      case 'skip':
      case '0':
        return EdlAction.cut;
      case '1':
        return EdlAction.mute;
      case '2':
        return EdlAction.commercialBreak;
    }
    return null;
  }
}

/// One `start, end, action` row.
///
/// The interval is half-open — `start <= t < end` — so two edits that touch
/// end-to-start do not overlap and no instant is covered twice.
class EdlEdit {
  const EdlEdit({
    required this.start,
    required this.end,
    this.action = EdlAction.cut,
  });

  /// Builds an edit from seconds, which is the unit EDL text uses.
  factory EdlEdit.seconds(
    num start,
    num end, {
    EdlAction action = EdlAction.cut,
  }) {
    return EdlEdit(
      start: _duration(start),
      end: _duration(end),
      action: action,
    );
  }

  final Duration start;
  final Duration end;
  final EdlAction action;

  Duration get length => end - start;

  /// A zero-length or inverted row is not an edit, it is a typo.
  bool get isValid => end > start;

  bool contains(Duration time) => time >= start && time < end;

  EdlEdit copyWith({Duration? start, Duration? end, EdlAction? action}) {
    return EdlEdit(
      start: start ?? this.start,
      end: end ?? this.end,
      action: action ?? this.action,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EdlEdit &&
        other.start == start &&
        other.end == end &&
        other.action == action;
  }

  @override
  int get hashCode => Object.hash(start, end, action);

  @override
  String toString() {
    return 'EdlEdit(${_formatTimecode(start)} – ${_formatTimecode(end)}, '
        '${action.key})';
  }
}

/// A validated, sorted, non-overlapping set of edits.
class Edl {
  Edl._(List<EdlEdit> edits)
      : edits = List<EdlEdit>.unmodifiable(edits),
        cuts = List<EdlEdit>.unmodifiable(
            edits.where((EdlEdit e) => e.action.shiftsTimeline)),
        silences = List<EdlEdit>.unmodifiable(
            edits.where((EdlEdit e) => e.action.silences));

  /// No edits at all. Shared so callers can use it as a default without
  /// allocating, and because "no edits" is the overwhelmingly common case.
  static final Edl empty = Edl._(const <EdlEdit>[]);

  /// Normalises an arbitrary collection: drops invalid rows, sorts by start,
  /// and rejects overlaps.
  ///
  /// Overlapping rows are dropped rather than clipped, because clipping would
  /// silently invent an end time the user never marked. Kodi refuses them for
  /// the same reason, and a file that arrives with overlaps is usually a merge
  /// artefact where the first row is the one the author meant.
  factory Edl.of(Iterable<EdlEdit> edits) {
    final List<EdlEdit> sorted = edits.where((EdlEdit e) => e.isValid).toList()
      ..sort((EdlEdit a, EdlEdit b) => a.start.compareTo(b.start));
    final List<EdlEdit> kept = <EdlEdit>[];
    Duration? previousEnd;
    for (final EdlEdit edit in sorted) {
      if (previousEnd != null && edit.start < previousEnd) {
        continue;
      }
      kept.add(edit);
      previousEnd = edit.end;
    }
    if (kept.isEmpty) {
      return Edl.empty;
    }
    return Edl._(kept);
  }

  /// Parses a `.edl` body.
  ///
  /// Accepted, because real files in the wild use all of it:
  /// * `hh:mm:ss.mmm`, `mm:ss`, `ss.mmm` and bare seconds;
  /// * whitespace **or** commas between columns;
  /// * `#` and `;` comments, blank lines, CRLF and a UTF-8 BOM;
  /// * three columns (`start end action`) or two (`start end`, meaning cut).
  ///
  /// A row that cannot be understood is skipped, never guessed at.
  factory Edl.parse(String text) {
    final List<EdlEdit> rows = <EdlEdit>[];
    for (String line in text.split(RegExp(r'\r\n|\r|\n'))) {
      line = line.replaceFirst('\uFEFF', '').trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      final int comment = line.indexOf('#');
      if (comment >= 0) {
        line = line.substring(0, comment).trim();
      }
      if (line.isEmpty) {
        continue;
      }
      final List<String> columns = line
          .split(RegExp(r'[\s,]+'))
          .where((String c) => c.isNotEmpty)
          .toList();
      if (columns.length < 2) {
        continue;
      }
      final Duration? start = parseTimecode(columns[0]);
      final Duration? end = parseTimecode(columns[1]);
      if (start == null || end == null) {
        continue;
      }
      EdlAction action = EdlAction.cut;
      if (columns.length >= 3) {
        final EdlAction? parsed = EdlAction.fromKey(columns[2]);
        if (parsed == null) {
          continue;
        }
        action = parsed;
      }
      rows.add(EdlEdit(start: start, end: end, action: action));
    }
    return Edl.of(rows);
  }

  /// Merges several lists, which is what happens when a sidecar file and the
  /// in-app marks describe the same video.
  factory Edl.merge(Iterable<Edl> lists) {
    return Edl.of(lists.expand((Edl list) => list.edits));
  }

  /// Sorted, non-overlapping edits.
  final List<EdlEdit> edits;

  bool get isEmpty => edits.isEmpty;
  bool get isNotEmpty => edits.isNotEmpty;
  int get length => edits.length;

  /// Only the edits that shorten the timeline, precomputed once so the mapping
  /// loops below never rebuild a filtered list.
  final List<EdlEdit> cuts;

  /// Only the edits that leave the picture alone.
  final List<EdlEdit> silences;

  /// How much running time the cuts remove in total.
  Duration get cutTotal {
    Duration total = Duration.zero;
    for (final EdlEdit cut in cuts) {
      total += cut.length;
    }
    return total;
  }

  /// Appends one edit, keeping the invariants.
  Edl add(EdlEdit edit) => Edl.of(<EdlEdit>[...edits, edit]);

  /// Drops every edit equal to [edit].
  Edl remove(EdlEdit edit) =>
      Edl.of(edits.where((EdlEdit e) => e != edit).toList());

  // ---- timeline mapping ----------------------------------------------------
  // Ported from `Edl::SourceToTime` / `Edl::TimeToSource` in Kodi's Edl.cpp.
  // The loop accumulates instead of binary-searching because an edit list is
  // tiny (a season's worth of ad breaks is dozens of rows), and an accumulator
  // is impossible to get subtly wrong at the boundaries.

  /// Source time → the time the viewer sees.
  ///
  /// A point inside a cut maps back to the cut's start on the timeline: that
  /// instant was removed, so it has no timeline of its own.
  Duration sourceToTimeline(Duration source) {
    Duration removed = Duration.zero;
    for (final EdlEdit cut in cuts) {
      if (source <= cut.start) {
        break;
      }
      final Duration reached =
          source < cut.end ? source : cut.end;
      removed += reached - cut.start;
    }
    final Duration timeline = source - removed;
    return timeline.isNegative ? Duration.zero : timeline;
  }

  /// Timeline time → source time.
  ///
  /// The boundary case is deliberate: a timeline position that lands exactly on
  /// where a cut *was* resolves to the far side of it, so scrubbing forward
  /// never parks the playhead on a frame that should not exist.
  Duration timelineToSource(Duration timeline) {
    Duration removed = Duration.zero;
    for (final EdlEdit cut in cuts) {
      final Duration startOnTimeline = cut.start - removed;
      if (timeline < startOnTimeline) {
        break;
      }
      removed += cut.length;
    }
    return timeline + removed;
  }

  /// What a file of [sourceDuration] plays for once cuts are honoured.
  Duration timelineDuration(Duration sourceDuration) =>
      sourceToTimeline(sourceDuration);

  /// The inverse of [timelineDuration]: how long the source must be to fill a
  /// timeline of [timeline].
  Duration sourceDuration(Duration timeline) => timelineToSource(timeline);

  /// The edit covering [source], if any.
  ///
  /// Edits never overlap, so there is at most one; the loop still scans
  /// backwards from the last row because callers ask this every frame and the
  /// playhead is usually near the end of the list only in the credit roll.
  EdlEdit? covering(Duration source) {
    for (final EdlEdit edit in edits) {
      if (edit.start > source) {
        break;
      }
      if (edit.contains(source)) {
        return edit;
      }
    }
    return null;
  }

  /// Whether the audio must be silent at [source].
  bool isSilentAt(Duration source) {
    final EdlEdit? edit = covering(source);
    return edit != null && edit.action.silences;
  }

  /// Whether [source] has been cut away and playback should jump to
  /// `covering(source).end`.
  bool isCutAt(Duration source) {
    final EdlEdit? edit = covering(source);
    return edit != null && edit.action.shiftsTimeline;
  }

  // ---- serialisation -------------------------------------------------------

  /// Renders the canonical Kodi body: one row per edit, `hh:mm:ss.mmm` columns.
  String toEdlText({bool withHeader = true}) {
    final StringBuffer buffer = StringBuffer();
    if (withHeader) {
      buffer.writeln('# XnX Player edit decision list');
      buffer.writeln('# start end action      (0 cut, 1 mute, 2 commercial break)');
    }
    for (final EdlEdit edit in edits) {
      buffer
        ..write(_formatTimecode(edit.start))
        ..write(' ')
        ..write(_formatTimecode(edit.end))
        ..write(' ')
        ..writeln(edit.action.code);
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (other is! Edl || other.edits.length != edits.length) {
      return false;
    }
    for (int i = 0; i < edits.length; i++) {
      if (other.edits[i] != edits[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(edits);

  @override
  String toString() => 'Edl(${edits.length} edits, cut ${cutTotal.inSeconds}s)';
}

// ---- timecode helpers ------------------------------------------------------

/// `hh:mm:ss.mmm`, `mm:ss`, `ss.mmm`, bare seconds — and nothing else.
///
/// Returns null on anything ambiguous instead of falling back to zero: a
/// mis-parsed timecode silently deletes the wrong ten seconds of a film, which
/// is far worse than dropping a row.
Duration? parseTimecode(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final List<String> parts = text.split(':');
  if (parts.length > 3) {
    return null;
  }
  double seconds = 0;
  for (final String part in parts) {
    final double? value = double.tryParse(part);
    if (value == null || !value.isFinite || value < 0) {
      return null;
    }
    seconds = seconds * 60 + value;
  }
  return _duration(seconds);
}

String _formatTimecode(Duration value) {
  final int total = value.isNegative ? 0 : value.inMilliseconds;
  final String hours = (total ~/ 3600000).toString().padLeft(2, '0');
  final String minutes = ((total ~/ 60000) % 60).toString().padLeft(2, '0');
  final String seconds = ((total ~/ 1000) % 60).toString().padLeft(2, '0');
  final String millis = (total % 1000).toString().padLeft(3, '0');
  return '$hours:$minutes:$seconds.$millis';
}

Duration _duration(num seconds) =>
    Duration(microseconds: (seconds * 1000000).round());
