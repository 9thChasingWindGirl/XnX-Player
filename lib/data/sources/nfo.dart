import 'dart:convert';
import 'dart:io';

import '../models/media_item.dart';
import '../net.dart';

/// A Kodi-style sidecar file — what tinyMediaManager, Kodi and Emby all write
/// next to a video.
///
/// A local folder has no metadata server, so these files are the only source of
/// a real plot, cast list, year and rating. Every field is optional: a
/// half-scraped show still yields whatever it has, and a missing or broken file
/// returns null so the caller keeps its file-name fallback.
class NfoFile {
  const NfoFile({
    this.title,
    this.originalTitle,
    this.showTitle,
    this.plot,
    this.tagline,
    this.year,
    this.rating,
    this.genres = const <String>[],
    this.people = const <MediaPerson>[],
    this.studio,
    this.mpaa,
    this.duration,
    this.season,
    this.episode,
    this.airDate,
    this.status,
    this.tmdbId,
  });

  /// `<title>`: the episode title for `episodedetails`, the show for `tvshow`.
  final String? title;
  final String? originalTitle;

  /// `<showtitle>`: present on an episode file, redundant on `tvshow`.
  final String? showTitle;

  final String? plot;
  final String? tagline;
  final int? year;
  final double? rating;
  final List<String> genres;
  final List<MediaPerson> people;
  final String? studio;

  /// `<mpaa>`: "TV-MA", "PG-13".
  final String? mpaa;
  final Duration? duration;
  final int? season;
  final int? episode;
  final String? airDate;

  /// `<status>`: "Continuing" / "Ended".
  final String? status;
  final int? tmdbId;

  bool get isEmpty =>
      title == null &&
      plot == null &&
      year == null &&
      rating == null &&
      genres.isEmpty &&
      people.isEmpty &&
      studio == null &&
      mpaa == null;

  /// The `.nfo` that belongs beside [videoPath]: `Show.S01E01.mkv` ->
  /// `Show.S01E01.nfo`.
  static String pathFor(String videoPath) {
    final int slash = videoPath.lastIndexOf(RegExp(r'[\\/]'));
    final int dot = videoPath.lastIndexOf('.');
    if (dot <= slash) {
      return '$videoPath.nfo';
    }
    // Only strip what looks like an extension. A dotted name with no extension
    // (`Show.S01E01`) must keep its dots, or the sidecar cannot be found.
    final String ext = videoPath.substring(dot + 1);
    if (ext.isEmpty || ext.length > 5 || ext.contains(RegExp(r'\s'))) {
      return '$videoPath.nfo';
    }
    return '${videoPath.substring(0, dot)}.nfo';
  }

  /// Reads and parses [path]; null when the file does not exist or is unusable.
  ///
  /// Decoded with `allowMalformed` because a scraped nfo is often UTF-8 while
  /// an older Chinese release may still be GBK — a wrong byte should cost one
  /// character, not the whole file.
  static Future<NfoFile?> read(String path) async {
    if (path.isEmpty) {
      return null;
    }
    final File file = File(path);
    try {
      if (!await file.exists()) {
        return null;
      }
      final String text =
          utf8.decode(await file.readAsBytes(), allowMalformed: true);
      return parse(text);
    } on Object {
      return null;
    }
  }

  /// Parses Kodi/TMM XML. Returns null when there is no recognisable root
  /// element, so a random `.nfo` file cannot be mistaken for metadata.
  static NfoFile? parse(String xml) {
    final String text = xml.startsWith('\uFEFF') ? xml.substring(1) : xml;
    final XmlNode root = parseXml(text);
    final XmlNode? node = root.child('tvshow') ??
        root.child('episodedetails') ??
        root.child('movie') ??
        root.child('musicvideo');
    if (node == null) {
      return null;
    }

    final List<String> genres = node
        .named('genre')
        .map((XmlNode n) => n.trimmed)
        .where((String g) => g.isNotEmpty)
        .toList(growable: false);

    final List<MediaPerson> people = <MediaPerson>[];
    for (final XmlNode actor in node.named('actor')) {
      final String name = actor.textOf('name') ?? '';
      if (name.isEmpty) {
        continue;
      }
      people.add(
        MediaPerson(
          name: name,
          role: _emptyToNull(actor.textOf('role')),
          type: 'Actor',
        ),
      );
    }
    for (final XmlNode director in node.named('director')) {
      final String name = director.trimmed;
      if (name.isEmpty) {
        continue;
      }
      people.add(MediaPerson(name: name, job: '导演', type: 'Director'));
    }
    for (final XmlNode writer in node.named('writer')) {
      final String name = writer.trimmed;
      if (name.isEmpty) {
        continue;
      }
      people.add(MediaPerson(name: name, job: '编剧', type: 'Writer'));
    }

    final int? minutes = int.tryParse(node.textOf('runtime') ?? '');
    final String aired = node.textOf('aired') ?? node.textOf('premiered') ?? '';

    final NfoFile nfo = NfoFile(
      title: _emptyToNull(node.textOf('title')),
      originalTitle: _emptyToNull(node.textOf('originaltitle')),
      showTitle: _emptyToNull(node.textOf('showtitle')),
      plot: _emptyToNull(node.textOf('plot')) ?? _emptyToNull(node.textOf('outline')),
      tagline: _emptyToNull(node.textOf('tagline')),
      year: _year(node, aired),
      rating: _rating(node),
      genres: genres,
      people: people,
      studio: _emptyToNull(node.textOf('studio')),
      mpaa: _emptyToNull(node.textOf('mpaa')),
      duration: minutes != null && minutes > 0
          ? Duration(minutes: minutes)
          : null,
      season: int.tryParse(node.textOf('season') ?? ''),
      episode: int.tryParse(node.textOf('episode') ?? ''),
      airDate: _emptyToNull(aired),
      status: _emptyToNull(node.textOf('status')),
      tmdbId: _tmdbId(node),
    );
    return nfo.isEmpty ? null : nfo;
  }

  static int? _year(XmlNode node, String aired) {
    final int? plain = int.tryParse(node.textOf('year') ?? '');
    if (plain != null && plain > 1800) {
      return plain;
    }
    // `premiered` is `2024-01-17`; the leading four digits are the year.
    if (aired.length >= 4) {
      final int? parsed = int.tryParse(aired.substring(0, 4));
      if (parsed != null && parsed > 1800) {
        return parsed;
      }
    }
    return null;
  }

  /// Kodi writes `<ratings><rating><value>7.4</value></rating></ratings>`, while
  /// older scrapers wrote a bare `<rating>7.4</rating>`. Both are read here,
  /// and a zero/unparseable value is treated as "no rating".
  static double? _rating(XmlNode node) {
    for (final XmlNode rating in node.descendants('rating')) {
      final String raw = rating.child('value')?.trimmed ?? rating.trimmed;
      final double? value = double.tryParse(raw.replaceAll(',', '.'));
      if (value != null && value > 0) {
        return value;
      }
    }
    return null;
  }

  static int? _tmdbId(XmlNode node) {
    for (final XmlNode unique in node.named('uniqueid')) {
      if (unique.attr('type').toLowerCase() == 'tmdb') {
        final int? id = int.tryParse(unique.trimmed);
        if (id != null && id > 0) {
          return id;
        }
      }
    }
    final int? explicit = int.tryParse(node.textOf('tmdbid') ?? '');
    return explicit != null && explicit > 0 ? explicit : null;
  }

  static String? _emptyToNull(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
