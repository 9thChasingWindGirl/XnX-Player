import 'dart:convert';

import '../models/artwork.dart';
import '../models/media_item.dart';
import '../net.dart';
import 'media_source.dart';

/// Emby / Jellyfin REST client.
///
/// Both servers speak the same API; Jellyfin simply ignores the Emby-branded
/// authorization header. Image URLs carry the API key, so `Image.network` works
/// without extra headers, while playback goes through `/Videos/{id}/stream` with
/// `static=true` — that is the direct-play path, so mpv gets the original
/// bitstream (HDR, TrueHD, Dolby Vision) instead of a transcode.
class EmbySource extends MediaSource {
  EmbySource(super.config);

  static const String _client = 'XnX Player';
  static const String _version = '0.1.0';

  String? _token;
  String? _userId;

  String get _base => trimSlashes(config.url);

  String get _authValue {
    final String token = _token ?? config.token;
    const String auth = 'MediaBrowser Client="$_client", Device="Windows", '
        'DeviceId="xnx-player-windows", Version="$_version"';
    return token.isEmpty ? auth : '$auth, Token="$token"';
  }

  Map<String, String> get _headers => <String, String>{
        'X-Emby-Authorization': _authValue,
        'Accept': 'application/json',
      };

  String get _tokenValue => _token ?? config.token;

  Uri _uri(String path, [Map<String, String> params = const <String, String>{}]) {
    final String url = path.startsWith('http') ? path : '$_base$path';
    final Uri base = Uri.parse(url);
    if (params.isEmpty) {
      return base;
    }
    return base.replace(queryParameters: <String, String>{...base.queryParameters, ...params});
  }

  Future<void> _ensureAuth() async {
    if (_userId != null || config.userId.isNotEmpty) {
      _userId ??= config.userId;
      if (_tokenValue.isNotEmpty) {
        return;
      }
    }
    if (config.username.isEmpty) {
      throw const SourceException('请先填写 Emby / Jellyfin 的账号');
    }
    final HttpResult result = await Http.postJson(
      _uri('/Users/AuthenticateByName'),
      <String, dynamic>{'Username': config.username, 'Pw': config.password},
      headers: _headers,
    );
    if (!result.ok) {
      throw SourceException(result.status == 401 ? '账号或密码不正确' : '连接失败（HTTP ${result.status}）');
    }
    final Map<String, dynamic> data = result.jsonMap;
    _token = data['AccessToken'] as String?;
    final Object? user = data['User'];
    if (user is Map<String, dynamic>) {
      _userId = user['Id'] as String?;
    }
    if (_token == null || _userId == null) {
      throw const SourceException('服务器没有返回访问令牌或用户 ID');
    }
  }

  @override
  Future<List<MediaItem>> browse() async {
    await _ensureAuth();
    // Page through the whole library. A single Limit=80 request silently
    // truncated servers with more films — the reported "未能全部显示影片" —
    // so walk StartIndex until TotalRecordCount is exhausted. 300 per page
    // keeps each response light while a 2000-title library costs seven
    // round-trips, not one enormous one.
    const int pageSize = 300;
    final List<MediaItem> out = <MediaItem>[];
    int start = 0;
    while (true) {
      final Map<String, dynamic> data = await Http.getJson(
        _uri('/Users/$_userId/Items', <String, String>{
          'Recursive': 'true',
          'IncludeItemTypes': 'Movie,Series',
          'Fields': _fields,
          'SortBy': 'DateCreated',
          'SortOrder': 'Descending',
          'Limit': '$pageSize',
          'StartIndex': '$start',
          'EnableImageTypes': 'Primary,Logo,Thumb,Backdrop,Banner,Disc,Art',
        }),
        headers: _headers,
      );
      final List<MediaItem> page = _items(data);
      out.addAll(page);
      final int total = (data['TotalRecordCount'] as num?)?.toInt() ?? out.length;
      start += page.length;
      if (page.isEmpty || start >= total || page.length < pageSize) {
        break;
      }
    }
    return out;
  }

  /// "Continue watching": the server already knows where you stopped, which is
  /// why this is a query and not local bookkeeping.
  Future<List<MediaItem>> resumable() async {
    await _ensureAuth();
    final Map<String, dynamic> data = await Http.getJson(
      _uri('/Users/$_userId/Items', <String, String>{
        'Recursive': 'true',
        'Filters': 'IsResumable',
        'IncludeItemTypes': 'Movie,Episode',
        'Fields': _fields,
        'Limit': '24',
        'EnableImageTypes': 'Primary,Logo,Thumb,Backdrop,Banner,Disc,Art',
      }),
      headers: _headers,
    );
    return _items(data);
  }

  static const String _fields =
      'Overview,RunTimeTicks,ProductionYear,CommunityRating,ImageTags,Genres,'
      'BackdropImageTags,UserData,SeriesName,IndexNumber,ParentIndexNumber,'
      'PrimaryImageAspectRatio,'
      // Inheritance: an episode carries only a still, and names its series as
      // the owner of the logo, art and backdrop. Asking for these fields is
      // what makes a hub look finished instead of empty.
      'ParentLogoItemId,ParentLogoImageTag,ParentArtItemId,ParentArtImageTag,'
      'ParentBackdropItemId,ParentBackdropImageTags,ParentThumbItemId,'
      'ParentThumbImageTag,SeriesId,SeriesPrimaryImageTag';

  /// What a hub page needs on top of [_fields]. Kept separate because these are
  /// per-item costs — `People` alone is a few kilobytes — and a browse of 80
  /// titles has no use for any of them.
  static const String _detailFields = '$_fields,'
      'Taglines,Genres,People,Studios,OfficialRating,MediaSources';

  /// The full record for one item.
  ///
  /// `/Users/{uid}/Items/{id}` returns the same shape as the list endpoint, so
  /// the projection is reused and then enriched: the extra fields are simply
  /// absent from a list response, which is exactly why the hub used to look
  /// empty next to what the server actually knew.
  @override
  Future<MediaItem> details(MediaItem item) async {
    await _ensureAuth();
    final String nativeId = item.id.contains('::')
        ? item.id.split('::').last
        : item.id;
    final Map<String, dynamic> data = await Http.getJson(
      _uri('/Users/$_userId/Items/$nativeId', <String, String>{'Fields': _detailFields}),
      headers: _headers,
    );
    final MediaItem? parsed = _parse(data);
    if (parsed == null) {
      return item;
    }
    return parsed.copyWith(
      tagline: _first(data['Taglines']),
      genres: _strings(data['Genres']),
      people: _people(data['People']),
      studio: _studio(data['Studios']),
      officialRating: data['OfficialRating'] as String?,
      tech: _tech(data['MediaSources']),
    );
  }

  static String? _first(Object? raw) {
    if (raw is List && raw.isNotEmpty) {
      final Object? value = raw.first;
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static List<String> _strings(Object? raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .whereType<String>()
        .where((String value) => value.trim().isNotEmpty)
        .map((String value) => value.trim())
        .toList(growable: false);
  }

  static String? _studio(Object? raw) {
    if (raw is! List) {
      return null;
    }
    for (final Object? entry in raw) {
      if (entry is Map && entry['Name'] is String) {
        final String name = (entry['Name'] as String).trim();
        if (name.isNotEmpty) {
          return name;
        }
      }
    }
    return null;
  }

  /// Credits, in the order the server listed them (cast first, then crew).
  ///
  /// A portrait is only built for people the server actually has an image for:
  /// requesting `/Images/Primary` for a person without one returns a 404 per
  /// face, which on a 30-person row is 30 wasted round-trips.
  List<MediaPerson> _people(Object? raw) {
    if (raw is! List) {
      return const <MediaPerson>[];
    }
    final List<MediaPerson> out = <MediaPerson>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final Object? name = entry['Name'];
      if (name is! String || name.trim().isEmpty) {
        continue;
      }
      final Object? id = entry['Id'];
      final Object? tag = entry['PrimaryImageTag'];
      final String? portrait = id is String && tag is String && tag.isNotEmpty
          ? _imageUrl(id, 'Primary', tag: tag, maxHeight: 320)
          : null;
      out.add(
        MediaPerson(
          name: name.trim(),
          role: entry['Role'] is String ? (entry['Role'] as String).trim() : null,
          job: entry['Type'] is String && entry['Type'] != 'Actor'
              ? _jobLabel(entry['Type'] as String)
              : null,
          type: entry['Type'] is String ? entry['Type'] as String : 'Actor',
          imageUrl: portrait,
          headers: <String, String>{'X-Emby-Token': _tokenValue},
        ),
      );
    }
    return out;
  }

  static String _jobLabel(String type) => switch (type) {
        'Director' => '导演',
        'Writer' => '编剧',
        'Producer' => '制片',
        'Composer' => '音乐',
        'GuestStar' => '客串',
        _ => type,
      };

  /// "2160p · HEVC · EAC3 5.1" from the first media source's streams.
  ///
  /// The value has to survive a transcoded file as well: what is printed is
  /// whatever the server reports for the source it would actually play.
  static String? _tech(Object? raw) {
    if (raw is! List || raw.isEmpty) {
      return null;
    }
    final Object? first = raw.first;
    if (first is! Map) {
      return null;
    }
    final Object? streams = first['MediaStreams'];
    if (streams is! List) {
      return null;
    }
    String? video;
    String? audio;
    for (final Object? entry in streams) {
      if (entry is! Map) {
        continue;
      }
      final String type = entry['Type'] is String ? entry['Type'] as String : '';
      if (type == 'Video' && video == null) {
        final int height = (entry['Height'] as num?)?.toInt() ?? 0;
        final String codec = (entry['Codec'] as String? ?? '').toUpperCase();
        final String range = entry['VideoRange'] is String ? entry['VideoRange'] as String : '';
        video = <String>[
          if (height >= 2160)
            '2160p'
          else if (height >= 1080)
            '1080p'
          else if (height >= 720)
            '720p'
          else if (height > 0)
            '${height}p',
          if (codec.isNotEmpty) codec,
          if (range.isNotEmpty && range.toUpperCase() == 'HDR') 'HDR',
        ].join(' ');
      } else if (type == 'Audio' && audio == null) {
        final String codec = (entry['Codec'] as String? ?? '').toUpperCase();
        final int channels = (entry['Channels'] as num?)?.toInt() ?? 0;
        final String layout = switch (channels) {
          1 => '1.0',
          2 => '2.0',
          6 => '5.1',
          8 => '7.1',
          _ => channels > 0 ? '${channels}ch' : '',
        };
        audio = <String>[codec, layout].where((String part) => part.isNotEmpty).join(' ');
      }
    }
    final List<String> parts = <String>[
      if (video != null && video.isNotEmpty) video,
      if (audio != null && audio.isNotEmpty) audio,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  List<MediaItem> _items(Map<String, dynamic> data) {
    final Object? raw = data['Items'];
    if (raw is! List) {
      return const <MediaItem>[];
    }
    final List<MediaItem> out = <MediaItem>[];
    for (final Object? entry in raw) {
      if (entry is Map<String, dynamic>) {
        final MediaItem? item = _parse(entry);
        if (item != null) {
          out.add(item);
        }
      }
    }
    return out;
  }

  MediaItem? _parse(Map<String, dynamic> json) {
    final Object? idValue = json['Id'];
    if (idValue is! String) {
      return null;
    }
    final String type = json['Type'] as String? ?? 'Movie';
    final Map<String, dynamic> userData = json['UserData'] is Map<String, dynamic>
        ? json['UserData'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final int ticks = (json['RunTimeTicks'] as num?)?.toInt() ?? 0;
    final int positionTicks = (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    final double played = (userData['PlayedPercentage'] as num?)?.toDouble() ?? 0;
    final String name = json['Name'] as String? ?? '未命名';
    final String? series = json['SeriesName'] as String?;
    final int? index = (json['IndexNumber'] as num?)?.toInt();
    final int? season = (json['ParentIndexNumber'] as num?)?.toInt();
    final int? year = (json['ProductionYear'] as num?)?.toInt();
    final double? rating = (json['CommunityRating'] as num?)?.toDouble();

    final MediaKind kind = switch (type) {
      'Series' => MediaKind.series,
      'Season' => MediaKind.season,
      'Episode' => MediaKind.episode,
      'Folder' || 'CollectionFolder' || 'BoxSet' => MediaKind.folder,
      _ => MediaKind.movie,
    };

    String? badge;
    if (kind == MediaKind.episode && index != null) {
      badge = 'S${season ?? 1}E$index';
    }

    final Artwork art = _artworkFor(json, idValue);

    return MediaItem(
      id: '${config.id}::$idValue',
      sourceId: config.id,
      sourceKind: config.kind,
      kind: kind,
      title: name,
      subtitle: series,
      overview: json['Overview'] as String?,
      genres: _strings(json['Genres']),
      meta: <String>[
        if (year != null) '$year',
        if (ticks > 0) _runtime(Duration(microseconds: ticks ~/ 10)),
      ].join(' · '),
      progress: (played / 100).clamp(0.0, 1.0).toDouble(),
      duration: ticks > 0 ? Duration(microseconds: ticks ~/ 10) : null,
      resumeAt: positionTicks > 0 ? Duration(microseconds: positionTicks ~/ 10) : null,
      path: idValue,
      posterUrl: art.best(ArtKind.poster)?.url,
      backdropUrl: art.best(ArtKind.backdrop)?.url,
      artwork: art,
      badge: badge,
      year: year,
      rating: rating,
      playable: kind != MediaKind.series && kind != MediaKind.season,
      headers: <String, String>{'X-Emby-Token': _tokenValue},
    );
  }

  /// Emby re-encodes any image at any size, so each role asks for roughly what
  /// the slot will paint. One `maxHeight=660` for everything was cheap but
  /// soft: a 440pt hero cover was being upscaled from 660px.
  String? _imageUrl(
    String id,
    String type, {
    String? tag,
    int? index,
    int? maxWidth,
    int? maxHeight,
  }) {
    if (_tokenValue.isEmpty) {
      return null;
    }
    final (int, int) box = switch (type) {
      'Backdrop' => (maxWidth ?? 1920, maxHeight ?? 0),
      'Logo' => (maxWidth ?? 900, maxHeight ?? 0),
      'Thumb' => (maxWidth ?? 1280, maxHeight ?? 0),
      'Banner' => (maxWidth ?? 1000, maxHeight ?? 0),
      'Disc' => (maxWidth ?? 700, maxHeight ?? 0),
      'Art' => (maxWidth ?? 0, maxHeight ?? 700),
      _ => (maxWidth ?? 0, maxHeight ?? 900),
    };
    final StringBuffer url = StringBuffer('$_base/Items/$id/Images/$type');
    if (index != null) {
      url.write('/$index');
    }
    url.write('?');
    if (box.$1 > 0) {
      url.write('maxWidth=${box.$1}&');
    }
    if (box.$2 > 0) {
      url.write('maxHeight=${box.$2}&');
    }
    if (tag != null && tag.isNotEmpty) {
      url.write('tag=$tag&');
    }
    url.write('quality=90&api_key=$_tokenValue');
    return url.toString();
  }

  /// Builds the full art set, applying the server's inheritance rules.
  ///
  /// `ImageTags` lists what this item owns; `Parent*` names the item that owns
  /// what it lacks. The rule is worth implementing rather than approximating:
  /// without it an episode hub shows a single 16:9 still and calls it a page.
  Artwork _artworkFor(Map<String, dynamic> json, String itemId) {
    final ArtworkBuilder art = ArtworkBuilder();
    final Map<String, dynamic> tags = json['ImageTags'] is Map
        ? (json['ImageTags'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    void own(ArtKind kind, String type) {
      final String? tag = tags[type]?.toString();
      if (tag == null) {
        return;
      }
      art.add(kind, _imageUrl(itemId, type, tag: tag), source: 'emby');
    }

    own(ArtKind.poster, 'Primary');
    own(ArtKind.logo, 'Logo');
    own(ArtKind.thumb, 'Thumb');
    own(ArtKind.banner, 'Banner');
    own(ArtKind.disc, 'Disc');
    own(ArtKind.clearart, 'Art');

    final List<dynamic> backdropTags = json['BackdropImageTags'] is List
        ? json['BackdropImageTags'] as List<dynamic>
        : const <dynamic>[];
    for (int i = 0; i < backdropTags.length; i++) {
      art.add(
        ArtKind.backdrop,
        _imageUrl(itemId, 'Backdrop', tag: backdropTags[i].toString(), index: i),
        source: 'emby',
      );
    }

    // An episode has no logo, art or backdrop of its own; the series does.
    void inherit(ArtKind kind, String idField, String tagField, String type) {
      if (art.has(kind)) {
        return;
      }
      final String? owner = json[idField] as String?;
      if (owner == null || owner.isEmpty) {
        return;
      }
      art.add(
        kind,
        _imageUrl(owner, type, tag: json[tagField] as String?),
        source: 'emby',
      );
    }

    inherit(ArtKind.logo, 'ParentLogoItemId', 'ParentLogoImageTag', 'Logo');
    inherit(ArtKind.clearart, 'ParentArtItemId', 'ParentArtImageTag', 'Art');
    inherit(ArtKind.thumb, 'ParentThumbItemId', 'ParentThumbImageTag', 'Thumb');
    inherit(ArtKind.poster, 'SeriesId', 'SeriesPrimaryImageTag', 'Primary');

    if (!art.has(ArtKind.backdrop)) {
      final String? owner = json['ParentBackdropItemId'] as String?;
      final List<dynamic> parentTags = json['ParentBackdropImageTags'] is List
          ? json['ParentBackdropImageTags'] as List<dynamic>
          : const <dynamic>[];
      if (owner != null && owner.isNotEmpty) {
        if (parentTags.isEmpty) {
          art.add(ArtKind.backdrop, _imageUrl(owner, 'Backdrop'), source: 'emby');
        }
        for (int i = 0; i < parentTags.length; i++) {
          art.add(
            ArtKind.backdrop,
            _imageUrl(owner, 'Backdrop', tag: parentTags[i].toString(), index: i),
            source: 'emby',
          );
        }
      }
    }

    return art.build();
  }

  static String _runtime(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours} 小时 ${duration.inMinutes.remainder(60)} 分';
    }
    return '${duration.inMinutes} 分钟';
  }

  @override
  Future<List<MediaItem>> children(MediaItem container) async {
    await _ensureAuth();
    final String nativeId = container.id.split('::').last;
    final Uri uri = container.kind == MediaKind.series
        ? _uri('/Shows/$nativeId/Episodes', <String, String>{
            'UserId': '$_userId',
            'Fields': _fields,
            'EnableImageTypes': 'Primary,Logo,Thumb,Backdrop,Banner,Disc,Art',
          })
        : _uri('/Users/$_userId/Items', <String, String>{
            'ParentId': nativeId,
            'Fields': _fields,
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
            'EnableImageTypes': 'Primary,Logo,Thumb,Backdrop,Banner,Disc,Art',
          });
    final Map<String, dynamic> data = await Http.getJson(uri, headers: _headers);
    return _items(data);
  }

  @override
  Future<String> resolve(MediaItem item) async {
    await _ensureAuth();
    final String nativeId = item.id.split('::').last;
    return '$_base/Videos/$nativeId/stream?static=true&MediaSourceId=$nativeId'
        '&api_key=$_tokenValue';
  }

  @override
  Map<String, String> headersFor(MediaItem item) => const <String, String>{};

  /// Report playback position so the server's resume state stays in sync.
  Future<void> reportProgress(MediaItem item, Duration position) async {
    if (_userId == null) {
      return;
    }
    final String nativeId = item.id.split('::').last;
    try {
      await Http.postJson(
        _uri('/Sessions/Playing/Progress'),
        <String, dynamic>{
          'ItemId': nativeId,
          'PositionTicks': position.inMicroseconds * 10,
          'IsPaused': false,
          'CanSeek': true,
          'PlayMethod': 'DirectPlay',
        },
        headers: _headers,
      );
    } on Object {
      // Progress reporting is best-effort: a media server being briefly
      // unreachable must never interrupt playback.
    }
  }

  String get debugAuth => _authValue;

  String encodeHeaderForMpv() => jsonEncode(<String, String>{'X-Emby-Authorization': _authValue});
}
