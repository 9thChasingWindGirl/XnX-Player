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
    this.outline,
    this.tagline,
    this.year,
    this.rating,
    this.genres = const <String>[],
    this.countries = const <String>[],
    this.credits = const <String>[],
    this.thumbUrls = const <String>[],
    this.namedSeasons = const <int, String>{},
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

  /// Kodi keeps `<outline>` and `<plot>` as separate fields; a short outline
  /// is not a truncated plot, so callers choose which one to show.
  final String? plot;
  final String? outline;
  final String? tagline;
  final int? year;
  final double? rating;
  final List<String> genres;
  final List<String> countries;
  final List<String> credits;

  /// `<thumb>` elements: scraper-provided art URLs that belong to the show.
  final List<String> thumbUrls;

  /// `<namedseason number="N">` — localized season titles.
  final Map<int, String> namedSeasons;
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
      outline == null &&
      year == null &&
      rating == null &&
      genres.isEmpty &&
      countries.isEmpty &&
      credits.isEmpty &&
      thumbUrls.isEmpty &&
      namedSeasons.isEmpty &&
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

  /// All sidecar names Kodi/TMM may write for one video, in priority order.
  ///
  /// `VideoTagLoaderNFO.cpp:161-294`: a movie folder's `movie.nfo` can sit
  /// beside an episode file, and a stack may use an `SxxEyy`-suffixed nfo.
  /// [pathFor] stays the first candidate for callers that want one file.
  static List<String> candidatePaths(String videoPath) {
    final String primary = pathFor(videoPath);
    final int slash = videoPath.lastIndexOf(RegExp(r'[\\/]'));
    final String folder = slash >= 0 ? videoPath.substring(0, slash) : '';
    final Set<String> out = <String>{primary};

    final String movieNfo = folder.isEmpty ? 'movie.nfo' : '$folder${Platform.pathSeparator}movie.nfo';
    out.add(movieNfo);
    // `Show.S01E02.mkv` -> `Show.S01E02.nfo` already covered; scrapers that
    // name by tag alone produce `S01E02.nfo` in the same folder.
    final RegExpMatch? tag = RegExp(r'[Ss](\d{1,2})[._ -]?[Ee](\d{1,3})').firstMatch(videoPath);
    if (tag != null) {
      final String label = 'S${tag.group(1)}E${tag.group(2)}.nfo';
      out.add(folder.isEmpty ? label : '$folder${Platform.pathSeparator}$label');
    }
    return out.toList(growable: false);
  }

  /// Reads the first existing sidecar from [candidatePaths].
  static Future<NfoFile?> readFor(String videoPath) async {
    for (final String path in candidatePaths(videoPath)) {
      final NfoFile? nfo = await read(path);
      if (nfo != null) {
        return nfo;
      }
    }
    return null;
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
    // Kodi's ParseNative gives premiered precedence over aired (both may be
    // present and disagree after a re-scrape).
    final String aired = node.textOf('premiered') ??
        node.textOf('aired') ??
        '';

    final Map<int, String> namedSeasons = <int, String>{};
    for (final XmlNode season in node.descendants('namedseason')) {
      final int? number = int.tryParse(season.attr('number'));
      final String? label = _emptyToNull(season.trimmed);
      if (number != null && label != null) {
        namedSeasons[number] = label;
      }
    }
    final List<String> thumbUrls = node
        .descendants('thumb')
        .map((XmlNode thumb) => _emptyToNull(thumb.trimmed))
        .whereType<String>()
        .toList(growable: false);

    final NfoFile nfo = NfoFile(
      title: _emptyToNull(node.textOf('title')),
      originalTitle: _emptyToNull(node.textOf('originaltitle')),
      showTitle: _emptyToNull(node.textOf('showtitle')),
      plot: _emptyToNull(node.textOf('plot')),
      outline: _emptyToNull(node.textOf('outline')),
      tagline: _emptyToNull(node.textOf('tagline')),
      countries: node
          .named('country')
          .map((XmlNode n) => n.trimmed)
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
      credits: node
          .named('credits')
          .map((XmlNode n) => n.trimmed)
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
      thumbUrls: thumbUrls,
      namedSeasons: namedSeasons,
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

  /// Kodi writes `<ratings><rating max="10" default="true"><value>7.4</value>
  /// </rating></ratings>`; older scrapers wrote a bare `<rating>7.4</rating>`.
  /// Scales are normalised to 10 (`VideoInfoTag.cpp:1281-1318`): a `max="5"`
  /// site's 4.5 becomes 9, otherwise the facts row would claim a 4.5/10 film.
  static double? _rating(XmlNode node) {
    final List<XmlNode> ratings = node.descendants('rating');
    // A `default="true"` rating wins over the first one in document order.
    final XmlNode? preferred = ratings.cast<XmlNode?>().firstWhere(
          (XmlNode? rating) =>
              rating!.attr('default').toLowerCase() == 'true',
          orElse: () => null,
        );
    final Iterable<XmlNode> ordered = preferred == null
        ? ratings
        : <XmlNode>[preferred, ...ratings.where((XmlNode r) => r != preferred)];

    for (final XmlNode rating in ordered) {
      final String raw = rating.child('value')?.trimmed ?? rating.trimmed;
      final double? value = double.tryParse(raw.replaceAll(',', '.'));
      if (value == null || value <= 0) {
        continue;
      }
      final double max = double.tryParse(rating.attr('max')) ?? 10;
      if (max <= 0) {
        continue;
      }
      final double normalized = value * 10 / max;
      if (normalized >= 0 && normalized <= 10) {
        return normalized;
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
