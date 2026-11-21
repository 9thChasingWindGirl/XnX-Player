import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/input/input_action.dart';
import '../../core/input/input_router.dart';
import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/sources/tmdb.dart';
import '../../data/store.dart';
import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_ids.dart';
import '../../ui/core/focus_navigator.dart';
import '../../ui/core/motion_clock.dart';
import '../../ui/core/poster_image.dart';
import '../../ui/core/title_treatment.dart';
import '../../ui/core/tv_focusable.dart';
import '../../ui/core/tv_scale.dart';
import '../../ui/widgets/ps_button.dart';
import '../../ui/widgets/ps_page.dart';
import '../home/home_tile.dart';

/// Game hub: the page a cover opens into.
///
/// Left column carries the copy and the actions, the key art bleeds off the
/// right edge, and the episodes sit on a shelf underneath — the same gliding
/// highlight as the home screen, so the transition reads as one place.
class HubPage extends StatefulWidget {
  const HubPage({
    super.key,
    required this.item,
    required this.onPlay,
  });

  final MediaItem item;

  /// [queue] carries the sibling episodes so the player can continue the season
  /// without coming back to this page.
  final void Function(MediaItem item, List<MediaItem> queue) onPlay;

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  List<MediaItem> _children = <MediaItem>[];

  /// The enriched record: tagline, genres, credits and technical detail.
  ///
  /// The item the shelf handed over is a *projection* — enough to draw a card.
  /// Null until the source answers, and it stays null when the source has
  /// nothing more to say, in which case the page simply shows less.
  MediaItem? _detail;

  /// File facts for a local title. A local library has no metadata server, so
  /// the detail page reads what the file system and the file name can prove:
  /// size, container, resolution, codecs, HDR, location and timestamps.
  _LocalInfo? _local;

  /// Portal aggregation: every configured file that can play this title.
  List<MediaItem> _providers = const <MediaItem>[];
  int _providerIndex = 0;
  MediaItem? _portal;

  bool _loading = false;
  String? _error;
  double _age = 0;
  double _last = -1;

  late bool _favorite = widget.item.favorite;

  InputSubscription? _input;

  /// Scrolls the copy + file panel. Up/down first tries to move focus; when
  /// there is nowhere left to go it pages the content, which is what a detail
  /// screen needs once its buttons and cast row are exhausted.
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _input = InputRouter.instance.subscribe(_onIntent, name: 'hub');
    _load();
  }

  @override
  void dispose() {
    _input?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// A hub sits above the shell, so it gets first refusal — but it only claims
  /// Back. Everything else falls through to whatever is below it.
  bool _onIntent(InputIntent intent) {
    if (intent.action == InputAction.back) {
      Navigator.of(context).maybePop();
      return true;
    }
    if (intent.action == InputAction.navigateUp || intent.action == InputAction.navigateDown) {
      final bool up = intent.action == InputAction.navigateUp;
      if (FocusNavigator.move(up ? NavDir.up : NavDir.down)) {
        return true;
      }
      if (_scroll.hasClients) {
        final ScrollPosition position = _scroll.position;
        final double page = position.viewportDimension * 0.8;
        final double target = (position.pixels + (up ? -page : page))
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if (target != position.pixels) {
          _scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
          return true;
        }
      }
      return false;
    }
    return false;
  }

  Future<void> _load() async {
    final MediaItem item = widget.item;
    final bool drillable = item.kind == MediaKind.series ||
        item.kind == MediaKind.folder ||
        item.kind == MediaKind.season;
    if (drillable) {
      setState(() => _loading = true);
    }
    try {
      // The full record first: it is what the page is built from, and a movie
      // needs nothing else. `details` swallows its own failures and returns the
      // projection, so this can never cost the page.
      MediaItem full;
      if (item.tmdbId != null) {
        // Portal titles get their cast and overview from TMDB. Every matching
        // file becomes a selectable "play from" provider, so a title that is
        // both local and on Emby can be played from either one.
        final String key = AppStore.instance.tmdbKey;
        final MediaItem base = key.isEmpty ? item : await Tmdb(key).details(item);
        _portal = base;
        List<MediaItem> providers = Tmdb.matches(base, AppStore.instance.items);
        if (providers.isEmpty && (item.path ?? '').isNotEmpty) {
          providers = <MediaItem>[item];
        }
        _providers = providers;
        _providerIndex =
            providers.indexWhere((MediaItem source) => source.id == item.id);
        if (_providerIndex < 0) {
          _providerIndex = 0;
        }
        full = providers.isEmpty ? base : Tmdb.attach(base, providers[_providerIndex]);
        if (providers.isNotEmpty) {
          final MediaItem source = await AppStore.instance.details(full);
          full = full.copyWith(
            tech: source.tech ?? full.tech,
            duration: full.duration ?? source.duration,
            path: source.path,
            progress: source.progress,
            resumeAt: source.resumeAt,
            seriesStatus: full.seriesStatus ?? source.seriesStatus,
          );
        }
      } else {
        full = await AppStore.instance.details(item);
      }
      _LocalInfo? local;
      if (full.sourceKind == SourceKind.local) {
        local = await _LocalInfo.read(full);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = full;
        _local = local;
      });
      if (!drillable) {
        return;
      }
      if ((full.path ?? '').isEmpty) {
        // A portal-only series has no folder to enumerate.
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
      final List<MediaItem> children = await AppStore.instance.children(full);
      if (!mounted) {
        return;
      }
      setState(() {
        _children = children;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final MediaItem item = _detail ?? widget.item;
    // A series spends the bottom of the page on episodes; a movie has nothing
    // to put there, so the credits take that slot instead of an empty stage.
    final bool showEpisodes = _children.isNotEmpty;
    return PsPage(
      palette: item.palette,
      child: MotionBuilder(
        builder: (BuildContext context, double dt) {
          final MotionClock clock = MotionScope.of(context);
          if (clock.time != _last) {
            _last = clock.time;
            _age += clock.scaled(dt);
          }
          final double arrive = stagger(_age, 0, offset: 0.04, duration: 0.55);
          final double artArrive = stagger(_age, 1, offset: 0.06, duration: 0.7);
          final double shelfArrive = stagger(_age, 2, offset: 0.08, duration: 0.7);
          final bool local = item.sourceKind == SourceKind.local;
          final bool shelf = !local && (showEpisodes || (item.cast.isNotEmpty && !_loading));

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Full-bleed key art. The old version was a 1320-wide panel pinned
              // to the top-right, so its left edge cut the page with a hard,
              // visible seam. A background that covers the stage and dissolves
              // into it is what a detail page should look like.
              Positioned.fill(
                child: Opacity(
                  opacity: 0.55 + 0.45 * artArrive,
                  child: _KeyArt(item: item),
                ),
              ),
              Positioned(
                left: PsSpace.safeX,
                right: PsSpace.safeX,
                top: 92 + 18 * (1 - arrive),
                bottom: 40,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Opacity(
                    opacity: arrive,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _Poster(item: item),
                            const SizedBox(width: 48),
                            Expanded(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 900),
                                  child: _Info(
                                    item: item,
                                    favorite: _favorite,
                                    onFavorite: _toggleFavorite,
                                    onPlay: _play,
                                    onBack: () => Navigator.of(context).maybePop(),
                                    sources: _providers
                                        .map(_sourceLabel)
                                        .toList(growable: false),
                                    sourceIndex: _providerIndex,
                                    onSource: _switchProvider,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (local && _local != null) ...<Widget>[
                          const SizedBox(height: 30),
                          _FileInfoPanel(rows: _local!.rows),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_loading)
                const Positioned(
                  left: PsSpace.safeX,
                  top: 760,
                  child: Text(S.loading, style: PsType.body),
                ),
              if (_error != null)
                Positioned(
                  left: PsSpace.safeX,
                  top: 760,
                  width: 900,
                  child: Text(_error!, style: PsType.body.copyWith(color: PsColor.danger)),
                ),
              if (shelf && showEpisodes)
                Positioned(
                  left: 0,
                  top: 742,
                  width: TvScale.widthOf(context),
                  child: Opacity(
                    opacity: shelfArrive,
                    child: _EpisodeShelf(
                      items: _children,
                      onSelect: (MediaItem episode) => widget.onPlay(episode, _children),
                    ),
                  ),
                )
              else if (shelf && item.cast.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 742,
                  width: TvScale.widthOf(context),
                  child: Opacity(
                    opacity: shelfArrive,
                    child: _CastShelf(people: item.cast),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _toggleFavorite() {
    final MediaItem item = _detail ?? widget.item;
    setState(() => _favorite = !_favorite);
    AppStore.instance.toggleFavorite(item);
  }

  /// Switches the portal detail to another configured file. The presentation
  /// stays TMDB's; only the playback source, path and episode list change.
  Future<void> _switchProvider(int index) async {
    final MediaItem? base = _portal;
    if (base == null || index < 0 || index >= _providers.length || index == _providerIndex) {
      return;
    }
    MediaItem full = Tmdb.attach(base, _providers[index]);
    try {
      final MediaItem source = await AppStore.instance.details(full);
      full = full.copyWith(
        tech: source.tech ?? full.tech,
        duration: source.duration ?? full.duration,
        path: source.path,
        progress: source.progress,
        resumeAt: source.resumeAt,
      );
    } on Object {
      // The provider may be offline; the path from the linked item still works.
    }
    _LocalInfo? local;
    if (full.sourceKind == SourceKind.local) {
      local = await _LocalInfo.read(full);
    }
    if (!mounted) {
      return;
    }
    final bool drillable = full.kind == MediaKind.series ||
        full.kind == MediaKind.folder ||
        full.kind == MediaKind.season;
    setState(() {
      _providerIndex = index;
      _detail = full;
      _local = local;
      _children = const <MediaItem>[];
      _loading = drillable && (full.path ?? '').isNotEmpty;
    });
    if (drillable && (full.path ?? '').isNotEmpty) {
      final List<MediaItem> children = await AppStore.instance.children(full);
      if (!mounted) {
        return;
      }
      setState(() {
        _children = children;
        _loading = false;
      });
    }
  }

  /// A season or a folder is not playable itself: the button plays its first
  /// child, which is what "继续播放" means on a season cover.
  void _play() {
    final MediaItem item = _detail ?? widget.item;
    final MediaItem? first = _children.isNotEmpty ? _children.first : null;
    if (first != null) {
      widget.onPlay(first, _children);
      return;
    }
    if (!item.playable) {
      return;
    }
    widget.onPlay(item, _children);
  }

  static String _sourceLabel(MediaItem item) => switch (item.sourceKind) {
        SourceKind.emby => 'EMBY',
        SourceKind.jellyfin => 'JELLYFIN',
        SourceKind.iptv => 'LIVE',
        SourceKind.openlist => 'OPENLIST',
        SourceKind.webdav => 'WEBDAV',
        SourceKind.directUrl => 'URL',
        SourceKind.local => '本地',
        SourceKind.tmdb => 'TMDB',
      };
}

/// 2:3 cover at the left of the page, the way a shelf in a shop faces you.
class _Poster extends StatelessWidget {
  const _Poster({required this.item});

  final MediaItem item;

  static const double width = 320;
  static const double height = 480;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.palette;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PsRadius.cardLarge),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x99000000), blurRadius: 48, offset: Offset(0, 20)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PsRadius.cardLarge),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[art[1], art[0]],
                ),
              ),
            ),
            if (item.hasPoster)
              posterImage(
                item.posterUrl!,
                headers: item.headers,
                errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                    const SizedBox.shrink(),
              ),
            // A hairline keeps a dark poster from melting into a dark stage.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PsRadius.cardLarge),
                border: Border.all(color: PsColor.hairline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything to the right of the cover: title, facts, copy, genres, actions.
class _Info extends StatelessWidget {
  const _Info({
    required this.item,
    required this.favorite,
    required this.onFavorite,
    required this.onPlay,
    required this.onBack,
    this.sources = const <String>[],
    this.sourceIndex = 0,
    this.onSource,
  });

  final MediaItem item;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;
  final VoidCallback onBack;

  /// Every configured file that can play this portal title, by source label.
  final List<String> sources;
  final int sourceIndex;
  final ValueChanged<int>? onSource;

  @override
  Widget build(BuildContext context) {
    final double started = item.resumeAt?.inSeconds.toDouble() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Breadcrumb instead of a back button: where you are reads as a path,
        // and every earlier level is a click target rather than an escape
        // hatch you only notice when lost.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            TvFocusable(
              radius: 10,
              onSelect: onBack,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  S.tabHome,
                  style: PsType.eyebrow.copyWith(
                    color: Color.lerp(item.accentColor, PsColor.text, 0.45),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '›',
                style: PsType.eyebrow.copyWith(
                  color: PsColor.text.withValues(alpha: 0.35),
                ),
              ),
            ),
            Text(
              _HubPageState._sourceLabel(item),
              style: PsType.eyebrow.copyWith(
                color: PsColor.text.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TitleTreatment(
          item: item,
          style: PsType.page,
          maxWidth: 800,
          logoHeight: 84,
          maxLines: 2,
        ),
        const SizedBox(height: 18),
        _Facts(item: item),
        if ((item.tagline ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            item.tagline!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PsType.body.copyWith(
              fontSize: 22,
              // Upstream has no italic token and we do not want one: a slanted
              // CJK face is a synthetic skew that reads as a rendering bug.
              height: 1.4,
              color: PsColor.text.withValues(alpha: 0.62),
            ),
          ),
        ],
        if ((item.overview ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            item.overview!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: PsType.body.copyWith(
              fontSize: 21,
              height: 1.5,
              color: PsColor.text.withValues(alpha: 0.84),
            ),
          ),
        ] else if (item.sourceKind == SourceKind.local) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            '本地文件没有内嵌的剧情简介与演职员表。下方“文件信息”读取自文件名与文件属性。',
            style: PsType.body.copyWith(
              fontSize: 19,
              height: 1.55,
              color: PsColor.text.withValues(alpha: 0.58),
            ),
          ),
        ],
        if (item.genres.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          _Chips(values: item.genres),
        ],
        if ((item.tech ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            item.tech!,
            style: PsType.micro.copyWith(fontSize: 16, letterSpacing: 0.6),
          ),
        ],
        if (sources.length > 1) ...<Widget>[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                '播放来源',
                style: PsType.micro.copyWith(
                  fontSize: 13,
                  letterSpacing: 1.2,
                  color: PsColor.textFaint,
                ),
              ),
              const SizedBox(width: 10),
              for (int i = 0; i < sources.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TvFocusable(
                    radius: 999,
                    onSelect: () => onSource?.call(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: i == sourceIndex
                            ? PsColor.warning.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: i == sourceIndex ? PsColor.warning : PsColor.hairline,
                        ),
                      ),
                      child: Text(
                        sources[i],
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                          color: i == sourceIndex ? PsColor.warning : PsColor.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (item.tmdbId != null && (item.path ?? '').isEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.link_off_rounded, size: 20, color: PsColor.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '该条目由 TMDB 提供，但当前媒体源中没有找到对应文件。请在“媒体库”中接入来源，或确认本地文件名与 TMDB 标题一致。',
                  style: PsType.micro.copyWith(
                    fontSize: 16,
                    height: 1.5,
                    color: PsColor.warning,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 30),
        Row(
          children: <Widget>[
            PsButton(
              label: (item.path ?? '').isEmpty
                  ? '缺少媒体源'
                  : (item.progress > 0.02 ? S.resume : S.play),
              icon: (item.path ?? '').isEmpty
                  ? Icons.link_off_rounded
                  : Icons.play_arrow_rounded,
              primary: (item.path ?? '').isNotEmpty,
              enabled: (item.path ?? '').isNotEmpty,
              width: 232,
              accent: item.accentColor,
              onSelect: (item.path ?? '').isNotEmpty ? onPlay : null,
            ),
            const SizedBox(width: 18),
            PsIconButton(
              icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              accent: item.accentColor,
              selected: favorite,
              onSelect: onFavorite,
            ),
            const SizedBox(width: 14),
            PsButton(
              label: S.back,
              icon: Icons.arrow_back_rounded,
              width: 148,
              onSelect: onBack,
            ),
            if (started > 5) ...<Widget>[
              const SizedBox(width: 20),
              Text(
                '从 ${_clock(item.resumeAt!)} 继续',
                style: PsType.micro.copyWith(fontSize: 15),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static String _clock(Duration value) {
    final int minutes = value.inMinutes;
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
  }
}

/// The one line of facts under the title: year · certificate · runtime ·
/// score · badge. Plex puts exactly this row there, and it is the difference
/// between "a poster with a name" and "a film you can decide about".
class _Facts extends StatelessWidget {
  const _Facts({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final List<Widget> parts = <Widget>[];
    void add(Widget widget) {
      if (parts.isNotEmpty) {
        parts.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('·', style: TextStyle(fontSize: 18, color: Color(0x59FFFFFF))),
        ));
      }
      parts.add(widget);
    }

    final TextStyle style = PsType.meta.copyWith(
      fontSize: 20,
      color: PsColor.text.withValues(alpha: 0.82),
    );

    if (item.year != null) {
      add(Text('${item.year}', style: style));
    }
    if ((item.officialRating ?? '').isNotEmpty) {
      // A certificate is a plate, not a word: it is the one fact a parent scans
      // for, and Plex draws it in a box for the same reason.
      add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: PsColor.text.withValues(alpha: 0.45)),
        ),
        child: Text(
          item.officialRating!,
          style: style.copyWith(fontSize: 15, letterSpacing: 1.0),
        ),
      ));
    }
    if (item.duration != null) {
      add(Text(item.runtimeLabel, style: style));
    }
    if (item.rating != null) {
      add(Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.star_rounded, size: 20, color: Color(0xFFFFC24B)),
          const SizedBox(width: 4),
          Text(item.rating!.toStringAsFixed(1), style: style),
        ],
      ));
    }
    if ((item.badge ?? '').isNotEmpty) {
      add(Text(item.badge!, style: style.copyWith(fontWeight: FontWeight.w600)));
    }
    if ((item.studio ?? '').isNotEmpty) {
      add(Text(item.studio!, style: style));
    }
    if ((item.meta ?? '').isNotEmpty && item.duration == null) {
      add(Text(item.meta!, style: style));
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: parts);
  }
}

/// Small hairline pills — genres, and anything else that is a tag.
class _Chips extends StatelessWidget {
  const _Chips({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: <Widget>[
        for (final String value in values)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PsRadius.pill),
              border: Border.all(color: PsColor.text.withValues(alpha: 0.28)),
            ),
            child: Text(
              value,
              style: PsType.label.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: PsColor.text.withValues(alpha: 0.86),
              ),
            ),
          ),
      ],
    );
  }
}

/// Round portraits with a name and a character, scrolled horizontally.
class _CastShelf extends StatelessWidget {
  const _CastShelf({required this.people});

  final List<MediaPerson> people;

  static const double _size = 132;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size + 76,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: PsSpace.safeX, bottom: 14),
            child: Text('演员', style: PsType.section.copyWith(fontSize: 20)),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PsSpace.safeX),
              clipBehavior: Clip.none,
              itemCount: people.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: 26),
              itemBuilder: (BuildContext context, int index) {
                final MediaPerson person = people[index];
                return SizedBox(
                  width: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Portrait(person: person, size: _size),
                      const SizedBox(height: 10),
                      Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PsType.label.copyWith(fontSize: 18),
                      ),
                      if ((person.caption ?? '').isNotEmpty)
                        Text(
                          person.caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PsType.micro.copyWith(fontSize: 15),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.person, required this.size});

  final MediaPerson person;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Initials are the fallback, not a placeholder icon: a row of identical
    // silhouettes says "we could not be bothered", a row of initials at least
    // identifies who is who.
    final String initials =
        person.name.isEmpty ? '·' : String.fromCharCode(person.name.runes.first);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: PsColor.text.withValues(alpha: 0.08),
        border: Border.all(color: PsColor.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: (person.imageUrl ?? '').isEmpty
          ? Center(
              child: Text(
                initials,
                style: PsType.page.copyWith(
                  fontSize: 44,
                  color: PsColor.text.withValues(alpha: 0.42),
                ),
              ),
            )
          : posterImage(
              person.imageUrl!,
              headers: person.headers,
              errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                  Center(
                child: Text(
                  initials,
                  style: PsType.page.copyWith(
                    fontSize: 44,
                    color: PsColor.text.withValues(alpha: 0.42),
                  ),
                ),
              ),
            ),
    );
  }
}

class _KeyArt extends StatelessWidget {
  const _KeyArt({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.palette;
    final String? url = item.heroBackdropUrl;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[art[1], art[0]],
            ),
          ),
        ),
        if (url != null && url.isNotEmpty)
          posterImage(
            url,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                const SizedBox.shrink(),
          ),
        // The copy sits on the left third; dissolve the picture there and let
        // the right side stay visible, so the page still shows its art.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                Color(0xF205060C),
                Color(0xD905060C),
                Color(0x6605060C),
                Color(0x0005060C),
              ],
              stops: <double>[0.0, 0.34, 0.62, 0.88],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x00000000), Color(0xE605060C)],
              stops: <double>[0.48, 1.0],
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 160,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x9905060C), Color(0x0005060C)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One label/value pair in the file-information panel.
class _InfoRow {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;
}

/// Facts a local file can prove about itself.
///
/// A media server answers with overviews, credits and per-stream metadata. A
/// file on disk has a name, a size, a timestamp and a directory — so the page
/// reads those instead of showing an empty stage, and parses the release tags
/// the scene convention encodes in the name.
class _LocalInfo {
  const _LocalInfo(this.rows);

  final List<_InfoRow> rows;

  static Future<_LocalInfo> read(MediaItem item) async {
    final String path = item.path ?? '';
    if (path.isEmpty) {
      return const _LocalInfo(<_InfoRow>[]);
    }
    String size = item.meta ?? '—';
    String modified = '—';
    try {
      final FileStat stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.notFound) {
        size = _bytes(stat.size);
        modified = _stamp(stat.modified);
      }
    } on Object {
      // The page still has the name and the folder; no need to fail it.
    }
    final String name = path.split(RegExp(r'[\\/]')).last;
    final int dot = name.lastIndexOf('.');
    final String container = dot > 0 ? name.substring(dot + 1).toUpperCase() : '—';
    final String folder = File(path).parent.path;
    final String tech = item.tech ?? '';
    final List<String> parts =
        tech.isEmpty ? const <String>[] : tech.split(' · ');

    String find(RegExp pattern, {String fallback = '—'}) {
      for (final String part in parts) {
        if (pattern.hasMatch(part)) {
          return part;
        }
      }
      return fallback;
    }

    final String resolution =
        find(RegExp(r'^\d{3,4}p$|^\d+(?:\.\d+)?k$', caseSensitive: false));
    final String video = find(RegExp(r'hevc|h\.?26[45]|av1|vp9', caseSensitive: false));
    final String depth = find(RegExp(r'\d+-bit', caseSensitive: false));
    final String audio =
        find(RegExp(r'aac|ac3|eac3|dts|truehd|atmos|flac', caseSensitive: false));
    final String hdr = find(RegExp(r'hdr|dolby vision|hlg', caseSensitive: false));
    final String fps = find(RegExp(r'fps$', caseSensitive: false));

    return _LocalInfo(<_InfoRow>[
      _InfoRow('文件名', name),
      _InfoRow('大小', size.isEmpty ? '—' : size),
      _InfoRow('容器', container),
      _InfoRow('分辨率', resolution),
      _InfoRow('视频编码', video),
      _InfoRow('位深', depth),
      _InfoRow('音频', audio),
      _InfoRow('HDR', hdr),
      _InfoRow('帧率', fps),
      _InfoRow('修改时间', modified),
      _InfoRow('所在文件夹', folder),
      _InfoRow('完整路径', path),
    ]);
  }

  static String _bytes(int bytes) {
    if (bytes <= 0) {
      return '—';
    }
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// The two-column (wrapping) card under a local file's copy.
class _FileInfoPanel extends StatelessWidget {
  const _FileInfoPanel({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('文件信息', style: PsType.section.copyWith(fontSize: 20)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          decoration: BoxDecoration(
            color: PsColor.text.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PsColor.hairline),
          ),
          child: Wrap(
            spacing: 44,
            runSpacing: 16,
            children: <Widget>[
              for (final _InfoRow row in rows)
                SizedBox(
                  width: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        row.label,
                        style: PsType.micro.copyWith(
                          fontSize: 13,
                          letterSpacing: 1.2,
                          color: PsColor.textFaint,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PsType.label.copyWith(fontSize: 17),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EpisodeShelf extends StatefulWidget {
  const _EpisodeShelf({required this.items, required this.onSelect});

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onSelect;

  @override
  State<_EpisodeShelf> createState() => _EpisodeShelfState();
}

class _EpisodeShelfState extends State<_EpisodeShelf> {
  final Spring _scroll = Spring(value: 0, frequency: 12);

  /// Last column the player was on: kept when focus leaves so the shelf does
  /// not jump back to the start every time the row goes dim.
  int _focus = -1;

  /// The card that is focused *right now*. Separate from [_focus] because a
  /// shelf that scrolled position and a card that is lit are two questions: the
  /// ring only exists where focus is, so only that card may grow.
  int _lit = -1;
  double _last = -1;

  static const double _cardWidth = 300;
  static const double _cardHeight = 170;
  static const double _gap = 24;

  /// 6 % of a 300 px card is 18 px — 9 px into each 24 px gutter: enough to
  /// read as a lift, not enough to touch the neighbour. This is
  /// `CardLook::focus_scale`, not a local opinion.
  static const double _grow = PsCard.focusScale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _cardHeight + 56,
      child: MotionBuilder(
        builder: (BuildContext context, double dt) {
          final MotionClock clock = MotionScope.of(context);
          if (clock.time != _last) {
            _last = clock.time;
            if (_focus >= 0) {
              const double pitch = _cardWidth + _gap;
              const double anchor = PsSpace.safeX + pitch * 1.5;
              final double left = PsSpace.safeX + _focus * pitch;
              final double contentRight = PsSpace.safeX + widget.items.length * pitch;
              final double maxScroll =
                  math.max(0.0, contentRight + PsSpace.safeX - TvScale.widthOf(context));
              _scroll.target = (left - anchor).clamp(0.0, maxScroll).toDouble();
            }
            _scroll.update(dt);
          }

          final List<Widget> cards = <Widget>[];
          for (int i = 0; i < widget.items.length; i++) {
            final MediaItem item = widget.items[i];
            final double left = PsSpace.safeX + i * (_cardWidth + _gap) - _scroll.value;
            if (left > 1960 || left + _cardWidth < -40) {
              continue;
            }
            cards.add(
              Positioned(
                left: left,
                top: 40,
                width: _cardWidth,
                height: _cardHeight,
                child: TvFocusable(
                  focusId: FocusIds.media(item.id),
                  radius: PsRadius.card,
                  focusedRadius: PsRadius.cardFocused,
                  accent: item.accentColor,
                  highlightScale: _grow,
                  pressScale: PsCard.pressScale,
                  onSelect: () => widget.onSelect(item),
                  onFocused: (bool focused) {
                    if (focused) {
                      _focus = i;
                      _lit = i;
                    } else if (_lit == i) {
                      _lit = -1;
                    }
                  },
                  child: PosterCard(
                    item: item,
                    width: _cardWidth,
                    height: _cardHeight,
                    focused: i == _lit,
                  ),
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: PsSpace.safeX,
                top: 0,
                child: Text(S.allMedia, style: PsType.section.copyWith(fontSize: 20)),
              ),
              ...cards,
            ],
          );
        },
      ),
    );
  }
}
