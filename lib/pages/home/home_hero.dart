import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_ids.dart';
import '../../ui/core/focus_zone.dart';
import '../../ui/core/poster_image.dart';
import '../../ui/core/tv_focusable.dart';
import '../../ui/core/title_treatment.dart';
import '../../ui/widgets/ps_button.dart';

/// The hero panel: key art top-right, copy on the left, one action.
///
/// The reference cross-fades it whenever the focused cover changes — the old
/// copy leaves upward quickly, the new one arrives a beat later from below.
/// That "content changes by cross-fading, never by swapping" rule is what stops
/// the home screen from feeling like a file browser.
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.item,
    this.opacity = 1,
    this.slide = 0,
    this.time = 0,
    this.onPlay,
    this.onFavorite,
    this.onDetails,
    this.carousel,
  });

  final MediaItem item;
  final double opacity;

  /// Horizontal offset in design pixels; negative while leaving, positive while
  /// arriving.
  final double slide;

  /// Free-running clock, used for the slow artwork float.
  final double time;

  final VoidCallback? onPlay;
  final VoidCallback? onFavorite;
  final VoidCallback? onDetails;

  /// The shelf the hero item came from, drawn as the right-edge carousel.
  /// Null on the leaving panel of a cross-fade — only the arriving hero
  /// carries the list.
  final HeroCarousel? carousel;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.palette;
    final Color accent = Color.lerp(art[2], PsColor.text, 0.45) ?? PsColor.text;
    final double bob = math.sin(time * 0.8) * 6;

    return IgnorePointer(
      ignoring: opacity < 0.12,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            // Full-bleed key art. The reference home is a poster that owns the
            // whole stage, not a framed square on the right: the left-to-right
            // and top-to-bottom dissolves sink it into the page, and the copy
            // sits directly on the picture.
            Positioned.fill(
              left: -80 + slide * 1.2,
              child: _HeroBackdrop(item: item),
            ),
            if (carousel != null)
              Positioned(
                right: 88 + slide * 1.6,
                top: 120 + bob,
                child: carousel!,
              ),
            Positioned(
              left: PsSpace.safeX + slide,
              top: 204,
              width: 900,
              child: Text(
                item.sourceKind == SourceKind.iptv ? '正在直播' : S.continueWatching,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PsType.eyebrow.copyWith(color: accent),
              ),
            ),
            Positioned(
              left: PsSpace.safeX - 4 + slide,
              top: 240,
              child: TitleTreatment(
                item: item,
                style: PsType.display,
                maxWidth: 1000,
                logoHeight: 116,
              ),
            ),
            Positioned(
              left: PsSpace.safeX + slide,
              top: 372,
              width: 1000,
              child: Text(
                _metaLine(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PsType.meta.copyWith(color: PsColor.text.withValues(alpha: 0.78)),
              ),
            ),
            if ((item.overview ?? '').isNotEmpty)
              Positioned(
                left: PsSpace.safeX + slide,
                top: 414,
                width: PsSpace.heroTextWidth,
                child: Text(
                  item.overview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PsType.body.copyWith(
                    fontSize: 28,
                    height: 1.43,
                    color: PsColor.text.withValues(alpha: 0.86),
                  ),
                ),
              ),
            if (item.progress > 0.01)
              Positioned(
                left: PsSpace.safeX + slide,
                top: 500,
                child: _Progress(
                  value: item.progress,
                  accent: item.accentColor,
                  label: _remaining(item),
                ),
              ),
            Positioned(
              left: PsSpace.safeX + slide,
              top: 544,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  PsButton(
                    label: item.progress > 0.02 ? S.resume : S.play,
                    icon: Icons.play_arrow_rounded,
                    primary: true,
                    width: 220,
                    accent: item.accentColor,
                    focusId: FocusIds.action('home', 'play'),
                    onSelect: onPlay,
                  ),
                  const SizedBox(width: 20),
                  PsIconButton(
                    icon: item.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    accent: item.accentColor,
                    selected: item.favorite,
                    focusId: FocusIds.action('home', 'favorite'),
                    onSelect: onFavorite,
                  ),
                  const SizedBox(width: 16),
                  PsIconButton(
                    icon: Icons.more_horiz_rounded,
                    accent: item.accentColor,
                    focusId: FocusIds.action('home', 'more'),
                    onSelect: onDetails,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _metaLine(MediaItem item) {
    final List<String> parts = <String>[
      if (item.year != null) '${item.year}',
      if (item.badge != null && item.badge!.isNotEmpty) item.badge!,
      if (item.duration != null) item.runtimeLabel,
      if (item.sourceKind == SourceKind.emby) 'Emby',
      if (item.sourceKind == SourceKind.jellyfin) 'Jellyfin',
      if (item.sourceKind == SourceKind.iptv) 'IPTV',
      if (item.sourceKind == SourceKind.webdav) 'WebDAV',
      if (item.sourceKind == SourceKind.openlist) 'OpenList',
    ];
    return parts.isEmpty ? item.meta ?? '' : parts.join('  ·  ');
  }

  static String _remaining(MediaItem item) {
    final Duration? duration = item.duration;
    if (duration == null) {
      return '${(item.progress * 100).round()}%';
    }
    final int left = duration.inMinutes - (duration.inMinutes * item.progress).round();
    return '还剩 ${left.clamp(0, 100000)} 分钟';
  }
}

/// The whole-stage art, dissolved into the page on its left and bottom edges
/// so the copy and the shelves read on top of it without a scrim bar.
class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.palette;
    final String? url = item.heroBackdropUrl ?? item.posterUrl;
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
            gapless: true,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                const SizedBox.shrink(),
          ),
        // Left dissolve: copy side fades the picture out completely.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[Color(0xFF05060C), Color(0xB305060C), Color(0x00000000)],
              stops: <double>[0.0, 0.34, 0.72],
            ),
          ),
        ),
        // Bottom dissolve: the shelves arrive on clean ground.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x0005060C), Color(0xD905060C)],
              stops: <double>[0.55, 1.0],
            ),
          ),
        ),
        // Right-edge dim under the carousel strip.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: <Color>[Color(0x9605060C), Color(0x00000000)],
              stops: <double>[0.0, 0.30],
            ),
          ),
        ),
      ],
    );
  }
}

/// The right-edge carousel: one small card per shelf item, the active one
/// ringed in the accent. Picking a card cross-fades the hero — this is the
/// "轮播" of the reference layout, and it doubles as a preview strip for the
/// row below.
class HeroCarousel extends StatelessWidget {
  const HeroCarousel({
    super.key,
    required this.items,
    required this.activeId,
    required this.onPick,
  });

  final List<MediaItem> items;
  final String activeId;
  final ValueChanged<MediaItem> onPick;

  static const double _cardWidth = 196;
  static const double _cardHeight = 110;
  static const int _max = 6;

  @override
  Widget build(BuildContext context) {
    final List<MediaItem> shown = items.take(_max).toList(growable: false);
    return FocusZone(
      id: 'hero-carousel',
      child: Column(
        children: <Widget>[
          for (final MediaItem item in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TvFocusable(
                key: ValueKey<String>(item.id),
                radius: 10,
                accent: item.accentColor,
                highlightScale: 1.04,
                pressScale: PsCard.pressScale,
                onSelect: () => onPick(item),
                child: Stack(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: _cardWidth,
                        height: _cardHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: <Color>[item.palette[1], item.palette[0]],
                            ),
                          ),
                          child: (item.thumbUrl ?? '').isNotEmpty
                              ? posterImage(
                                  item.thumbUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (BuildContext context, Object error, StackTrace? stack) =>
                                          const SizedBox.shrink(),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    if (item.id == activeId)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: item.accentColor, width: 3),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PsType.micro.copyWith(
                          fontSize: 14,
                          shadows: <Shadow>[
                            const Shadow(color: Color(0xB3000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.accent, required this.label});

  final double value;
  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 420,
          height: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(color: PsColor.text.withValues(alpha: 0.18)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(0.0, 1.0).toDouble(),
                  child: ColoredBox(color: accent),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        Text(label, style: PsType.numeral),
      ],
    );
  }
}
