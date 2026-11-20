/// Artwork as the servers actually model it.
///
/// Emby, Jellyfin and Plex all converge on the same seven roles, and the names
/// only differ per provider (`Primary`/`poster`, `Backdrop`/`fanart`,
/// `Logo`/`clearLogo`). Modelling the roles instead of the provider names is
/// what lets one screen look the same whether the library is Emby or a folder
/// of files: the hero asks for "a logo" and gets whatever the source has.
///
/// Two rules that make the difference between "posters in a grid" and a
/// ten-foot UI:
///
/// * **A logo is not a poster with text on it.** It is a transparent PNG used
///   *instead* of a title, which is why [ArtKind.logo] exists separately.
/// * **Artwork inherits.** An episode usually has only a still; its series owns
///   the logo and the backdrop. Sources fill that in via `Parent*` fields, and
///   [mergedUnder] does it generically for anything that cannot.
library;

enum ArtKind {
  /// 2:3 cover. 1000×1500 is the server-side convention.
  poster,

  /// 16:9 scene. Several can exist; clients alternate them.
  backdrop,

  /// Transparent title treatment (clearlogo). Sits over the backdrop.
  logo,

  /// 16:9 still, usually a frame from the video.
  thumb,

  /// Wide, short promotional strip (1000×185).
  banner,

  /// Disc art for physical-media libraries.
  disc,

  /// Transparent character cut-out / alternative art.
  clearart,
}

/// One image, plus what it takes to fetch it.
///
/// [headers] matter because a Plex server rejects a bare URL: the token has to
/// travel in `X-Plex-Token`. Emby puts its key in the query string, so its refs
/// carry no headers — the difference is contained here, not at the call site.
class ArtRef {
  const ArtRef(this.url, {this.headers = const <String, String>{}, this.source = ''});

  final String url;
  final Map<String, String> headers;

  /// Where it came from (`emby`, `plex`, `local`). Used for diagnostics and to
  /// pick a sensible cache key.
  final String source;

  bool get isRemote => url.startsWith('http://') || url.startsWith('https://');

  bool get isEmpty => url.isEmpty;
}

/// The artwork of one item: at most a handful of refs per role, in preference
/// order.
class Artwork {
  const Artwork(this._refs);

  const Artwork.empty() : _refs = const <ArtKind, List<ArtRef>>{};

  final Map<ArtKind, List<ArtRef>> _refs;

  bool get isEmpty => _refs.isEmpty;

  bool has(ArtKind kind) => _refs[kind]?.isNotEmpty ?? false;

  /// The first choice for [kind], or null when the source has none.
  ArtRef? best(ArtKind kind) {
    final List<ArtRef>? list = _refs[kind];
    if (list == null || list.isEmpty) {
      return null;
    }
    return list.first;
  }

  /// Every ref for [kind], in preference order. Backdrops use this; the rest
  /// almost always want [best].
  List<ArtRef> all(ArtKind kind) => _refs[kind] ?? const <ArtRef>[];

  /// Fills the gaps in this artwork from [parent], keeping our own refs first.
  ///
  /// This is the generic form of the server's `ParentLogoItemId` /
  /// `ParentBackdropImageTags` inheritance: an episode with only a still gets
  /// its series' logo and backdrop without the source having to implement the
  /// rule twice.
  Artwork mergedUnder(Artwork parent) {
    if (_refs.isEmpty) {
      return parent;
    }
    if (parent._refs.isEmpty) {
      return this;
    }
    final Map<ArtKind, List<ArtRef>> merged = <ArtKind, List<ArtRef>>{};
    for (final ArtKind kind in ArtKind.values) {
      final List<ArtRef> own = all(kind);
      final List<ArtRef> inherited = parent.all(kind);
      // Own backdrops are alternatives, not replacements: a client that
      // rotates backgrounds should see the parent's too.
      final List<ArtRef> combined = <ArtRef>[...own, ...inherited];
      if (combined.isNotEmpty) {
        merged[kind] = combined;
      }
    }
    return Artwork(merged);
  }
}

/// Mutable helper used by the sources while they parse a response or a folder.
///
/// Deliberately not a builder-with-validation: duplicate roles are legitimate
/// (backdrops), and an empty URL is a miss rather than an error — every source
/// is parsing a payload that may simply not have the image.
class ArtworkBuilder {
  final Map<ArtKind, List<ArtRef>> _refs = <ArtKind, List<ArtRef>>{};

  void add(ArtKind kind, String? url, {Map<String, String> headers = const <String, String>{}, String source = ''}) {
    if (url == null || url.isEmpty) {
      return;
    }
    _refs.putIfAbsent(kind, () => <ArtRef>[]).add(ArtRef(url, headers: headers, source: source));
  }

  bool has(ArtKind kind) => _refs[kind]?.isNotEmpty ?? false;

  Artwork build() {
    if (_refs.isEmpty) {
      return const Artwork.empty();
    }
    // Snapshot the lists: a builder that keeps adding after build() must not
    // mutate an Artwork that a widget is already holding.
    return Artwork(<ArtKind, List<ArtRef>>{
      for (final MapEntry<ArtKind, List<ArtRef>> entry in _refs.entries)
        entry.key: List<ArtRef>.of(entry.value),
    });
  }
}
