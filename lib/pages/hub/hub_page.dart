import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/store.dart';
import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/motion_clock.dart';
import '../../ui/core/tv_focusable.dart';
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
  final ValueChanged<MediaItem> onPlay;

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  List<MediaItem> _children = <MediaItem>[];
  bool _loading = false;
  String? _error;
  double _age = 0;
  double _last = -1;

  late bool _favorite = widget.item.favorite;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _load();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return true;
    }
    return false;
  }

  Future<void> _load() async {
    final MediaItem item = widget.item;
    final bool drillable = item.kind == MediaKind.series ||
        item.kind == MediaKind.folder ||
        item.kind == MediaKind.season;
    if (!drillable) {
      return;
    }
    setState(() => _loading = true);
    try {
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
    final MediaItem item = widget.item;
    return PsPage(
      palette: item.artwork,
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
                width: 1180,
                height: 900,
                child: Opacity(
                  opacity: 0.35 + 0.65 * artArrive,
                  child: _KeyArt(item: item),
                ),
              ),
              Positioned(
                left: PsSpace.safeX,
                top: 120 + 18 * (1 - arrive),
                width: 980,
                child: Opacity(
                  opacity: arrive,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _sourceLabel(item),
                        style: PsType.eyebrow.copyWith(
                          color: Color.lerp(item.accentColor, PsColor.text, 0.45),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PsType.hero,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _meta(item),
                        style: PsType.meta.copyWith(color: PsColor.text.withValues(alpha: 0.78)),
                      ),
                      if ((item.overview ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 26),
                        Text(
                          item.overview!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: PsType.body.copyWith(
                            fontSize: 24,
                            height: 1.5,
                            color: PsColor.text.withValues(alpha: 0.84),
                          ),
                        ),
                      ],
                      const SizedBox(height: 36),
                      Row(
                        children: <Widget>[
                          PsButton(
                            label: item.progress > 0.02 ? S.resume : S.play,
                            icon: Icons.play_arrow_rounded,
                            primary: true,
                            width: 220,
                            accent: item.accentColor,
                            onSelect: () => widget.onPlay(item),
                          ),
                          const SizedBox(width: 20),
                          PsIconButton(
                            icon: _favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            accent: item.accentColor,
                            selected: _favorite,
                            onSelect: () => setState(() {
                              _favorite = !_favorite;
                              AppStore.instance.toggleFavorite(item);
                            }),
                          ),
                          const SizedBox(width: 16),
                          PsButton(
                            label: S.back,
                            icon: Icons.arrow_back_rounded,
                            width: 168,
                            onSelect: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const Positioned(
                  left: PsSpace.safeX,
                  top: 720,
                  child: Text(S.loading, style: PsType.body),
                ),
              if (_error != null)
                Positioned(
                  left: PsSpace.safeX,
                  top: 720,
                  width: 900,
                  child: Text(_error!, style: PsType.body.copyWith(color: PsColor.danger)),
                ),
              if (_children.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 742,
                  width: 1920,
                  child: Opacity(
                    opacity: shelfArrive,
                    child: _EpisodeShelf(
                      items: _children,
                      onSelect: (MediaItem episode) => widget.onPlay(episode),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
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

  static String _meta(MediaItem item) {
    final List<String> parts = <String>[
      if (item.year != null) '${item.year}',
      if (item.duration != null) item.runtimeLabel,
      if (item.rating != null) '★ ${item.rating!.toStringAsFixed(1)}',
      if (item.group != null) item.group!,
      if (item.badge != null) item.badge!,
    ];
    return parts.isEmpty ? (item.meta ?? '') : parts.join('   ·   ');
  }
}

class _KeyArt extends StatelessWidget {
  const _KeyArt({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.artwork;
    final String? url = item.backdropUrl ?? item.posterUrl;
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
          Image.network(
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
  int _focus = -1;
  double _last = -1;

  static const double _cardWidth = 300;
  static const double _cardHeight = 170;
  static const double _gap = 24;

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
              final double anchor = PsSpace.safeX + pitch * 1.5;
              final double left = PsSpace.safeX + _focus * pitch;
              final double contentRight = PsSpace.safeX + widget.items.length * pitch;
              final double maxScroll = math.max(0.0, contentRight + PsSpace.safeX - 1920);
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
                  radius: PsRadius.card,
                  accent: item.accentColor,
                  onSelect: () => widget.onSelect(item),
                  onFocused: (bool focused) {
                    if (focused) {
                      _focus = i;
                    }
                  },
                  child: PosterCard(item: item, width: _cardWidth, height: _cardHeight),
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
