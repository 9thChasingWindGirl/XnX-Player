import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/input/input_action.dart';
import '../../core/input/input_router.dart';
import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/store.dart';
import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_ids.dart';
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

  bool _loading = false;
  String? _error;
  double _age = 0;
  double _last = -1;

  late bool _favorite = widget.item.favorite;

  InputSubscription? _input;

  @override
  void initState() {
    super.initState();
    _input = InputRouter.instance.subscribe(_onIntent, name: 'hub');
    _load();
  }

  @override
  void dispose() {
    _input?.cancel();
    super.dispose();
  }

  /// A hub sits above the shell, so it gets first refusal — but it only claims
  /// Back. Everything else falls through to whatever is below it.
  bool _onIntent(InputIntent intent) {
    if (intent.action != InputAction.back) {
      return false;
    }
    Navigator.of(context).maybePop();
    return true;
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
      final MediaItem full = await AppStore.instance.details(item);
      if (!mounted) {
        return;
      }
      setState(() => _detail = full);
      if (!drillable) {
        return;
      }
      final List<MediaItem> children = await AppStore.instance.children(item);
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

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned(
                right: -80 - 40 * (1 - artArrive),
                top: -90,
                width: 1320,
                height: 1000,
                child: Opacity(
                  opacity: 0.35 + 0.65 * artArrive,
                  child: _KeyArt(item: item),
                ),
              ),
              Positioned(
                left: PsSpace.safeX,
                top: 92 + 18 * (1 - arrive),
                width: 1180,
                child: Opacity(
                  opacity: arrive,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Poster(item: item),
                      const SizedBox(width: 48),
                      Expanded(child: _Info(item: item, favorite: _favorite, onFavorite: _toggleFavorite, onPlay: _play, onBack: () => Navigator.of(context).maybePop())),
                    ],
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
              if (showEpisodes)
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
              else if (item.cast.isNotEmpty && !_loading)
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

  /// A season or a folder is not playable itself: the button plays its first
  /// child, which is what "继续播放" means on a season cover.
  void _play() {
    final MediaItem item = _detail ?? widget.item;
    final MediaItem? first = _children.isNotEmpty ? _children.first : null;
    widget.onPlay(first ?? item, _children);
  }

  static String _sourceLabel(MediaItem item) => switch (item.sourceKind) {
        SourceKind.emby => 'EMBY',
        SourceKind.jellyfin => 'JELLYFIN',
        SourceKind.iptv => 'LIVE',
        SourceKind.openlist => 'OPENLIST',
        SourceKind.webdav => 'WEBDAV',
        SourceKind.directUrl => 'URL',
        SourceKind.local => '本地',
      };
}

/// 2:3 cover at the left of the page, the way a shelf in a shop faces you.
class _Poster extends StatelessWidget {
  const _Poster({required this.item});

  final MediaItem item;

  static const double width = 300;
  static const double height = 450;

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
  });

  final MediaItem item;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;
  final VoidCallback onBack;

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
        const SizedBox(height: 30),
        Row(
          children: <Widget>[
            PsButton(
              label: item.progress > 0.02 ? S.resume : S.play,
              icon: Icons.play_arrow_rounded,
              primary: true,
              width: 232,
              accent: item.accentColor,
              onSelect: onPlay,
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
            alignment: Alignment.topRight,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                const SizedBox.shrink(),
          ),
        // Dissolve the art into the stage on its left and bottom edges.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[Color(0xFF05060C), Color(0xCC05060C), Color(0x00000000)],
              stops: <double>[0.0, 0.42, 0.86],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x00000000), Color(0xE605060C)],
              stops: <double>[0.55, 1.0],
            ),
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
