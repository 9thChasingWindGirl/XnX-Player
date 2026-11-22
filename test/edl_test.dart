import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/core/edl.dart';

/// Fixture: a 10 s ad cut at 00:10 and a 5 s mute at 01:00.
///
/// Two different actions on purpose — the mapping functions must shorten the
/// timeline for the cut and leave it alone for the mute.
const String _sample = '''
# Kodi-style edit decision list
00:00:10.000 00:00:20.000 0
00:01:00.000 00:01:05.000 1
''';

void main() {
  group('EdlAction', () {
    test('only cut shortens the timeline', () {
      expect(EdlAction.cut.shiftsTimeline, isTrue);
      expect(EdlAction.mute.shiftsTimeline, isFalse);
      expect(EdlAction.commercialBreak.shiftsTimeline, isFalse);
      expect(EdlAction.cut.silences, isFalse);
      expect(EdlAction.mute.silences, isTrue);
      // An ad break leaves the picture too, so it is not a silence.
      expect(EdlAction.commercialBreak.silences, isFalse);
      expect(EdlAction.commercialBreak.skips, isTrue);
      expect(EdlAction.mute.skips, isFalse);
    });

    test('codes and mnemonics both resolve', () {
      expect(EdlAction.fromCode(0), EdlAction.cut);
      expect(EdlAction.fromCode(1), EdlAction.mute);
      expect(EdlAction.fromCode(3), EdlAction.commercialBreak);
      // 2 is Kodi's scene marker: a point, not an interval, so it is not an
      // action this model can represent.
      expect(EdlAction.fromCode(2), isNull);
      expect(EdlAction.fromCode(7), isNull);
      expect(EdlAction.fromKey('COMMBREAK'), EdlAction.commercialBreak);
      expect(EdlAction.fromKey(' commercial_break '), EdlAction.commercialBreak);
      expect(EdlAction.fromKey('3'), EdlAction.commercialBreak);
      expect(EdlAction.fromKey('2'), isNull);
      expect(EdlAction.fromKey('nonsense'), isNull);
    });
  });

  group('parseTimecode', () {
    test('reads every accepted shape', () {
      expect(parseTimecode('90'), const Duration(seconds: 90));
      expect(parseTimecode('01:30.250'),
          const Duration(minutes: 1, seconds: 30, milliseconds: 250));
      expect(parseTimecode('01:02:03.500'),
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500));
    });

    test('rejects ambiguity instead of guessing', () {
      expect(parseTimecode(''), isNull);
      expect(parseTimecode('abc'), isNull);
      expect(parseTimecode('1:2:3:4'), isNull);
      expect(parseTimecode('-5'), isNull);
      expect(parseTimecode('1::30'), isNull);
    });
  });

  group('Edl.parse', () {
    test('keeps order, actions and lengths', () {
      final Edl edl = Edl.parse(_sample);
      expect(edl.length, 2);
      expect(edl.edits.first.start, const Duration(seconds: 10));
      expect(edl.edits.first.end, const Duration(seconds: 20));
      expect(edl.edits.first.action, EdlAction.cut);
      expect(edl.edits.last.action, EdlAction.mute);
      expect(edl.cutTotal, const Duration(seconds: 10));
    });

    test('sorts, and drops overlapping or inverted rows', () {
      final Edl edl = Edl.parse('''
00:00:30.000 00:00:40.000 0
00:00:05.000 00:00:15.000 0
00:00:10.000 00:00:25.000 0
00:00:40.000 00:00:40.000 0
''');
      expect(edl.edits.map((EdlEdit e) => e.start.inSeconds).toList(), <int>[5, 30]);
    });

    test('accepts commas, a BOM and CRLF; two columns is a scene marker', () {
      final Edl edl = Edl.parse('\uFEFF00:00:01.000,00:00:02.000,0\r\n'
          '00:00:03.000 00:00:04.000\r\n'
          '\r\n');
      expect(edl.length, 1);
      expect(edl.edits.single.action, EdlAction.cut);
    });

    test('drops rows it cannot understand, never guesses', () {
      final Edl edl = Edl.parse('''
00:00:01.000 00:00:02.000 bogus
00:00:03.000
00:00:04.000 00:00:05.000 1
''');
      expect(edl.length, 1);
      expect(edl.edits.single.action, EdlAction.mute);
    });

    test('empty text is the shared empty list', () {
      expect(Edl.parse('# nothing here').isEmpty, isTrue);
      expect(Edl.parse(''), same(Edl.empty));
    });
  });

  group('timeline mapping', () {
    final Edl edl = Edl.parse(_sample);

    test('cuts are removed from the running time', () {
      expect(edl.sourceToTimeline(const Duration(seconds: 5)),
          const Duration(seconds: 5));
      // Inside the cut: that instant no longer exists, it maps to the cut edge.
      expect(edl.sourceToTimeline(const Duration(seconds: 15)),
          const Duration(seconds: 10));
      expect(edl.sourceToTimeline(const Duration(seconds: 25)),
          const Duration(seconds: 15));
      // A mute does not shift anything.
      expect(edl.sourceToTimeline(const Duration(seconds: 62)),
          const Duration(seconds: 52));
    });

    test('the inverse lands on the far side of a cut', () {
      expect(edl.timelineToSource(const Duration(seconds: 10)),
          const Duration(seconds: 20));
      expect(edl.timelineToSource(const Duration(seconds: 15)),
          const Duration(seconds: 25));
      expect(edl.timelineToSource(const Duration(seconds: 3)),
          const Duration(seconds: 3));
    });

    test('durations map both ways', () {
      expect(edl.timelineDuration(const Duration(seconds: 120)),
          const Duration(seconds: 110));
      expect(edl.sourceDuration(const Duration(seconds: 110)),
          const Duration(seconds: 120));
      expect(Edl.empty.timelineDuration(const Duration(minutes: 2)),
          const Duration(minutes: 2));
    });

    test('timeline -> source -> timeline is stable', () {
      for (final int second in <int>[0, 3, 9, 10, 11, 50, 59, 63, 100, 130]) {
        final Duration timeline = Duration(seconds: second);
        final Duration source = edl.timelineToSource(timeline);
        expect(edl.sourceToTimeline(source), timeline,
            reason: 'round trip failed at ${timeline.inSeconds}s');
      }
    });

    test('source never maps before zero', () {
      expect(edl.sourceToTimeline(Duration.zero), Duration.zero);
    });
  });

  group('queries', () {
    final Edl edl = Edl.parse(_sample);

    test('tells cuts and mutes apart at the playhead', () {
      expect(edl.isSkippedAt(const Duration(seconds: 15)), isTrue);
      expect(edl.isSkippedAt(const Duration(seconds: 20)), isFalse);
      expect(edl.isSilentAt(const Duration(seconds: 62)), isTrue);
      expect(edl.isSilentAt(const Duration(seconds: 65)), isFalse);
      expect(edl.covering(const Duration(seconds: 62))?.action, EdlAction.mute);
      expect(edl.covering(const Duration(seconds: 5)), isNull);
    });
  });

  group('editing', () {
    test('add keeps the list sorted and refuses overlaps', () {
      final Edl base = Edl.parse('00:00:10.000 00:00:20.000 0');
      final Edl added = base.add(const EdlEdit(
        start: Duration(seconds: 5),
        end: Duration(seconds: 8),
      ));
      expect(added.edits.first.start, const Duration(seconds: 5));
      final Edl overlapping = base.add(const EdlEdit(
        start: Duration(seconds: 15),
        end: Duration(seconds: 30),
      ));
      expect(overlapping.length, 1);
    });

    test('remove drops exactly the matching row', () {
      final Edl base = Edl.parse(_sample);
      final Edl trimmed = base.remove(base.edits.first);
      expect(trimmed.length, 1);
      expect(trimmed.edits.single.action, EdlAction.mute);
      expect(trimmed.cutTotal, Duration.zero);
    });

    test('merge combines lists and re-sorts them', () {
      final Edl a = Edl.parse('00:00:10.000 00:00:20.000 0');
      final Edl b = Edl.parse('00:00:01.000 00:00:02.000 1');
      final Edl merged = Edl.merge(<Edl>[a, b]);
      expect(merged.length, 2);
      expect(merged.edits.first.start, const Duration(seconds: 1));
      expect(merged.silences.single.action, EdlAction.mute);
    });
  });

  group('serialisation', () {
    test('round-trips through the canonical text form', () {
      final Edl edl = Edl.parse(_sample);
      expect(Edl.parse(edl.toEdlText()), edl);
      expect(edl.toEdlText(), contains('00:00:10.000 00:00:20.000 0'));
      expect(edl.toEdlText(), contains('00:01:00.000 00:01:05.000 1'));
    });

    test('commercial breaks survive the round trip without shifting time', () {
      final Edl edl = Edl.parse('00:00:30.000 00:00:40.000 3');
      expect(edl.edits.single.action, EdlAction.commercialBreak);
      expect(edl.timelineDuration(const Duration(seconds: 60)),
          const Duration(seconds: 60));
      // An ad break is jumped over, not muted: the picture disappears, so
      // nothing is left playing silently inside it.
      expect(edl.isSilentAt(const Duration(seconds: 35)), isFalse);
      expect(Edl.parse(edl.toEdlText()), edl);
    });
  });
}
