import '../../core/app_log.dart';
import '../models/media_item.dart';
import '../net.dart';

/// One TMDB genre, as the category chips need it (id + localized name).
class TmdbGenre {
  const TmdbGenre(this.id, this.name);

  final int id;
  final String name;
}

/// The portal rows the home screen draws before it knows about any file.
class TmdbHome {
  const TmdbHome({
    required this.trending,
    required this.popularMovies,
    required this.nowPlaying,
    required this.upcoming,
    required this.popularTv,
    required this.onTheAir,
    required this.genres,
  });

  final List<MediaItem> trending;
  final List<MediaItem> popularMovies;
  final List<MediaItem> nowPlaying;
  final List<MediaItem> upcoming;
  final List<MediaItem> popularTv;
  final List<MediaItem> onTheAir;
  final List<TmdbGenre> genres;

  /// Every discovered item, for the hero carousel and genre filtering.
  List<MediaItem> get all => <MediaItem>[
        ...trending,
        ...nowPlaying,
        ...popularMovies,
        ...popularTv,
        ...onTheAir,
        ...upcoming,
      ];
}

/// TMDB as a *portal*: it supplies discovery rows, posters, overviews and
/// credits; playback still always comes from a configured media source.
///
/// A title can exist in TMDB with no file behind it. Those items are returned
/// with `playable: false`, which the detail page reports instead of offering a
/// play button that cannot work.
class Tmdb {
  Tmdb(this.apiKey);

  final String apiKey;

  static const String _base = 'https://api.themoviedb.org/3';
  static const String _image = 'https://image.tmdb.org/t/p';

  bool get _bearer => apiKey.startsWith('eyJ');

  Map<String, String> get _headers => <String, String>{
        'Accept': 'application/json',
        if (_bearer) 'Authorization': 'Bearer $apiKey',
      };

  Uri _uri(String path, [Map<String, String> params = const <String, String>{}]) {
    return Uri.parse('$_base$path').replace(
      queryParameters: <String, String>{
        'language': 'zh-CN',
        'include_adult': 'false',
        ...params,
        if (!_bearer) 'api_key': apiKey,
      },
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    try {
      return await Http.getJson(_uri(path, params), headers: _headers)
          .timeout(const Duration(seconds: 12));
    } on Object catch (error) {
      AppLog.warn('TMDB 请求失败：$path（$error）');
      return const <String, dynamic>{};
    }
  }

  Future<TmdbHome> home() async {
    final List<Map<String, dynamic>> data = await Future.wait<Map<String, dynamic>>(
      <Future<Map<String, dynamic>>>[
        _get('/trending/all/week'),
        _get('/movie/popular'),
        _get('/movie/now_playing', <String, String>{'region': 'CN'}),
        _get('/movie/upcoming', <String, String>{'region': 'CN'}),
        _get('/tv/popular'),
        _get('/tv/on_the_air'),
        _get('/genre/movie/list'),
        _get('/genre/tv/list'),
      ],
    );
    final Map<int, String> movieGenres = _genreMap(data[6]);
    final Map<int, String> tvGenres = _genreMap(data[7]);
    final List<TmdbGenre> genres = _mergeGenres(movieGenres, tvGenres);
    return TmdbHome(
      trending: _items(data[0], 'movie', movieGenres, tvGenres),
      popularMovies: _items(data[1], 'movie', movieGenres, tvGenres),
      nowPlaying: _items(data[2], 'movie', movieGenres, tvGenres),
      upcoming: _items(data[3], 'movie', movieGenres, tvGenres),
      popularTv: _items(data[4], 'tv', movieGenres, tvGenres),
      onTheAir: _items(data[5], 'tv', movieGenres, tvGenres),
      genres: genres,
    );
  }

  /// The full record for one portal item, including credits.
  Future<MediaItem> details(MediaItem item) async {
    final int? id = item.tmdbId;
    if (id == null) {
      return item;
    }
    final bool tv = item.kind == MediaKind.series;
    final Map<String, dynamic> data = await _get(
      '${tv ? '/tv' : '/movie'}/$id',
      <String, String>{'append_to_response': 'credits'},
    );
    if (data.isEmpty) {
      return item;
    }
    final List<String> genres = <String>[
      for (final Object? entry in (data['genres'] is List ? data['genres'] as List : <Object?>[]))
        if (entry is Map && entry['name'] is String) entry['name'] as String,
    ];
    final Object? credits = data['credits'];
    final List<MediaPerson> people = <MediaPerson>[];
    if (credits is Map && credits['cast'] is List) {
      for (final Object? entry in credits['cast'] as List) {
        if (entry is! Map || entry['name'] is! String) {
          continue;
        }
        final String? profile = entry['profile_path'] as String?;
        people.add(MediaPerson(
          name: (entry['name'] as String).trim(),
          role: entry['character'] is String ? (entry['character'] as String).trim() : null,
          imageUrl: profile == null ? null : '$_image/w185$profile',
        ));
        if (people.length >= 24) {
          break;
        }
      }
    }
    final int runtime = (data['runtime'] as num?)?.toInt() ??
        ((data['episode_run_time'] is List && (data['episode_run_time'] as List).isNotEmpty)
            ? ((data['episode_run_time'] as List).first as num).toInt()
            : 0);
    final String? overview = (data['overview'] as String?)?.trim();
    return item.copyWith(
      overview: (overview ?? '').isEmpty ? item.overview : overview,
      tagline: data['tagline'] as String?,
      genres: genres.isEmpty ? item.genres : genres,
      people: people.isEmpty ? item.people : people,
      duration: runtime > 0 ? Duration(minutes: runtime) : item.duration,
    );
  }

  Map<int, String> _genreMap(Map<String, dynamic> data) {
    final Map<int, String> out = <int, String>{};
    final Object? raw = data['genres'];
    if (raw is List) {
      for (final Object? entry in raw) {
        if (entry is Map) {
          final int? id = (entry['id'] as num?)?.toInt();
          final Object? name = entry['name'];
          if (id != null && name is String && name.isNotEmpty) {
            out[id] = name;
          }
        }
      }
    }
    return out;
  }

  List<TmdbGenre> _mergeGenres(Map<int, String> a, Map<int, String> b) {
    final Map<String, TmdbGenre> byName = <String, TmdbGenre>{};
    for (final MapEntry<int, String> entry in <MapEntry<int, String>>[
      ...a.entries,
      ...b.entries,
    ]) {
      byName.putIfAbsent(entry.value, () => TmdbGenre(entry.key, entry.value));
    }
    final List<TmdbGenre> out = byName.values.toList()
      ..sort((TmdbGenre x, TmdbGenre y) => x.name.compareTo(y.name));
    return out;
  }

  List<MediaItem> _items(
    Map<String, dynamic> data,
    String fallbackType,
    Map<int, String> movieGenres,
    Map<int, String> tvGenres,
  ) {
    final Object? raw = data['results'];
    if (raw is! List) {
      return const <MediaItem>[];
    }
    final List<MediaItem> out = <MediaItem>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final String type = (entry['media_type'] as String?) ?? fallbackType;
      if (type != 'movie' && type != 'tv') {
        continue;
      }
      final int? id = (entry['id'] as num?)?.toInt();
      final Object? title = entry['title'] ?? entry['name'];
      if (id == null || title is! String || title.isEmpty) {
        continue;
      }
      final String? date =
          (entry['release_date'] ?? entry['first_air_date']) as String?;
      final int? year = date != null && date.length >= 4
          ? int.tryParse(date.substring(0, 4))
          : null;
      final Map<int, String> genreMap = type == 'movie' ? movieGenres : tvGenres;
      final List<String> genres = <String>[
        for (final Object? genre in (entry['genre_ids'] is List
            ? entry['genre_ids'] as List
            : <Object?>[]))
          if (genre is num && genreMap[genre.toInt()] != null) genreMap[genre.toInt()]!,
      ];
      final String? poster = entry['poster_path'] as String?;
      final String? backdrop = entry['backdrop_path'] as String?;
      out.add(MediaItem(
        id: 'tmdb::$type::$id',
        sourceId: 'tmdb',
        sourceKind: SourceKind.tmdb,
        kind: type == 'movie' ? MediaKind.movie : MediaKind.series,
        title: title.trim(),
        overview: entry['overview'] as String?,
        year: year,
        rating: (entry['vote_average'] as num?)?.toDouble(),
        genres: genres,
        meta: year == null ? null : '$year',
        posterUrl: poster == null ? null : '$_image/w500$poster',
        backdropUrl: backdrop == null ? null : '$_image/w1280$backdrop',
        tmdbId: id,
        playable: false,
      ));
    }
    return out;
  }

  /// Attaches a configured file to every portal item that has a matching
  /// title. Unmatched items stay portal-only (`playable: false`), which is
  /// what the detail page reports as a missing media source.
  static List<MediaItem> link(List<MediaItem> portal, List<MediaItem> sources) {
    final Map<String, MediaItem> exact = <String, MediaItem>{};
    final Map<String, MediaItem> loose = <String, MediaItem>{};
    for (final MediaItem source in sources) {
      // A series is not directly playable but still owns a folder of
      // episodes; it must be linkable, or every show would look unowned.
      if ((!source.isPlayable && (source.path ?? '').isEmpty) ||
          source.kind == MediaKind.channel) {
        continue;
      }
      final String key = _norm(source.title);
      if (key.length < 2) {
        continue;
      }
      loose.putIfAbsent(key, () => source);
      if (source.year != null) {
        exact.putIfAbsent('$key|${source.year}', () => source);
      }
    }
    return <MediaItem>[
      for (final MediaItem item in portal)
        _linkOne(item, exact, loose),
    ];
  }

  /// Every configured file that can play this portal title, best first.
  ///
  /// This is what "aggregate" means for the detail page: the row can offer the
  /// local copy and the Emby/WebDAV copy side by side instead of silently
  /// picking whichever the library happened to return first.
  static List<MediaItem> matches(MediaItem portal, List<MediaItem> sources) {
    final String key = _norm(portal.title);
    final List<MediaItem> out = <MediaItem>[];
    final Set<String> seen = <String>{};
    for (final MediaItem source in sources) {
      if (source.kind == MediaKind.channel) {
        continue;
      }
      if (!source.isPlayable && (source.path ?? '').isEmpty) {
        continue;
      }
      if (_norm(source.title) != key) {
        continue;
      }
      if (portal.year != null && source.year != null && portal.year != source.year) {
        continue;
      }
      if (seen.add(source.id)) {
        out.add(source);
      }
    }
    int rank(MediaItem item) => item.sourceKind == SourceKind.local
        ? 0
        : (item.sourceKind == SourceKind.directUrl ? 1 : 2);
    out.sort((MediaItem a, MediaItem b) => rank(a).compareTo(rank(b)));
    return out;
  }

  /// Merges one configured file into a portal item, keeping the portal's
  /// presentation and the file's playback fields.
  static MediaItem attach(MediaItem portal, MediaItem source) {
    return MediaItem(
      id: source.id,
      sourceId: source.sourceId,
      sourceKind: source.sourceKind,
      kind: portal.kind,
      title: portal.title,
      subtitle: portal.subtitle,
      overview: portal.overview,
      meta: portal.meta,
      progress: source.progress,
      duration: source.duration ?? portal.duration,
      path: source.path,
      badge: source.badge ?? portal.badge,
      posterUrl: portal.posterUrl ?? source.posterUrl,
      backdropUrl: portal.backdropUrl ?? source.backdropUrl,
      artwork: portal.artwork,
      headers: source.headers,
      favorite: source.favorite,
      group: portal.group,
      resumeAt: source.resumeAt,
      year: portal.year,
      rating: portal.rating,
      playable: source.playable,
      tagline: portal.tagline,
      genres: portal.genres,
      people: portal.people,
      studio: portal.studio,
      officialRating: portal.officialRating,
      tech: source.tech ?? portal.tech,
      seriesStatus: portal.seriesStatus ?? source.seriesStatus,
      tmdbId: portal.tmdbId,
    );
  }

  static MediaItem _linkOne(
    MediaItem portal,
    Map<String, MediaItem> exact,
    Map<String, MediaItem> loose,
  ) {
    final String key = _norm(portal.title);
    final MediaItem? source =
        (portal.year == null ? null : exact['$key|${portal.year}']) ?? loose[key];
    if (source == null) {
      return portal;
    }
    return attach(portal, source);
  }

  static String _norm(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
  }
}
