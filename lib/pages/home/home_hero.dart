import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_ids.dart';
import '../../ui/core/poster_image.dart';
import '../../ui/core/title_treatment.dart';
import '../../ui/core/tv_focusable.dart';

/// The Plex-style featured banner at the top of the home screen.
///
/// Plex does not put a full-screen poster stage above its shelves: it opens
/// with a wide 16:9 still, a small caption, and the first row already visible
/// underneath. This reproduces that grammar — compact copy in the lower left,
/// hard gradients into the page background, and controls the size of a real
/// button rather than a console prompt.
class PlexHero extends StatelessWidget {
  const PlexHero({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onDetails,
    required this.onFavorite,
  });

  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback onDetails;
  final VoidCallback onFavorite;

  /// Tall enough for a 16:9 still to read, short enough that the first shelf
  /// is on screen at 1080p. Plex's own banner sits in this band.
  static const double height = 524;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _HeroBackdrop(item: item),
          Positioned(
            left: 64,
            right: 64,
            bottom: 44,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_eyebrow(item), style: _eyebrowStyle),
                    const SizedBox(height: 14),
                    TitleTreatment(
                      item: item,
                      style: _titleStyle,
                      maxWidth: 800,
                      logoHeight: 78,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    _MetaLine(item: item),
                    if ((item.overview ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        item.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _bodyStyle,
                      ),
                    ],
                    if (item.progress > 0.01) ...<Widget>[
                      const SizedBox(height: 16),
                      _HeroProgress(item: item),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _HeroButton(
                          label: item.progress > 0.02 ? S.resume : S.play,
                          icon: Icons.play_arrow_rounded,
                          primary: true,
                          focusId: FocusIds.action('home', 'play'),
                          onSelect: onPlay,
                        ),
                        const SizedBox(width: 12),
                        _HeroButton(
                          label: '更多信息',
                          icon: Icons.info_outline_rounded,
                          primary: false,
                          focusId: FocusIds.action('home', 'more'),
                          onSelect: onDetails,
                        ),
                        const SizedBox(width: 12),
                        TvFocusable(
                          radius: 6,
                          focusId: FocusIds.action('home', 'favorite'),
                          onSelect: onFavorite,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: PlexColor.line),
                            ),
                            child: Icon(
                              item.favorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 22,
                              color: item.favorite ? PlexColor.amber : PlexColor.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _eyebrow(MediaItem item) {
    if (item.sourceKind == SourceKind.iptv) {
      return '正在直播';
    }
    if (item.progress > 0.02) {
      return '继续观看';
    }
    if (item.kind == MediaKind.series) {
      return '剧集推荐';
    }
    return '为你推荐';
  }

  static const TextStyle _eyebrowStyle = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 3,
    color: PlexColor.amber,
  );

  static const TextStyle _titleStyle = TextStyle(
    fontSize: 56,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    color: PlexColor.text,
  );

  static const TextStyle _bodyStyle = TextStyle(
    fontSize: 20,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: PlexColor.textDim,
  );
}

/// One line of facts under the title: year, rating, genres, runtime.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final String facts = _facts(item);
    final double? rating = item.rating;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (rating != null && rating > 0) ...<Widget>[
          const Icon(Icons.star_rounded, size: 18, color: PlexColor.amber),
          const SizedBox(width: 5),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: PlexColor.amber,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: Text(
            facts,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: PlexColor.textDim,
            ),
          ),
        ),
      ],
    );
  }

  static String _facts(MediaItem item) {
    final List<String> parts = <String>[
      if (item.year != null) '${item.year}',
      if (item.officialRating != null && item.officialRating!.isNotEmpty) item.officialRating!,
      if (item.genres.isNotEmpty) item.genres.take(3).join(' / '),
      if (item.duration != null) item.runtimeLabel,
      if (item.badge != null && item.badge!.isNotEmpty) item.badge!,
    ];
    if (parts.isNotEmpty) {
      return parts.join('  ·  ');
    }
    return item.meta ?? '';
  }
}

class _HeroProgress extends StatelessWidget {
  const _HeroProgress({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final Duration? duration = item.duration;
    final String left = duration == null
        ? '${(item.progress * 100).round()}%'
        : '还剩 ${(duration.inMinutes - duration.inMinutes * item.progress).round().clamp(0, 100000)} 分钟';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 360,
          height: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(color: Colors.white.withValues(alpha: 0.20)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: item.progress.clamp(0.0, 1.0).toDouble(),
                  child: const ColoredBox(color: PlexColor.amber),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          left,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: PlexColor.textDim,
          ),
        ),
      ],
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onSelect,
    this.focusId,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onSelect;
  final String? focusId;

  @override
  Widget build(BuildContext context) {
    const Color ink = Color(0xFF151515);
    final Color foreground = primary ? ink : PlexColor.text;
    return TvFocusable(
      radius: 6,
      focusId: focusId,
      onSelect: onSelect,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: primary ? PlexColor.amber : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: primary ? null : Border.all(color: PlexColor.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 22, color: foreground),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.palette;
    final String? url = item.heroBackdropUrl ?? item.thumbUrl;
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
            alignment: Alignment.topCenter,
            gapless: true,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                const SizedBox.shrink(),
          ),
        // Left dissolve: the caption always reads, whatever the still holds.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                Color(0xF20D0D0F),
                Color(0xB30D0D0F),
                Color(0x000D0D0F),
              ],
              stops: <double>[0.0, 0.45, 0.82],
            ),
          ),
        ),
        // Bottom dissolve into the shelf surface.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: <Color>[PlexColor.bg, Color(0x00141416)],
              stops: <double>[0.0, 0.62],
            ),
          ),
        ),
        // Top scrim under the window chrome.
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
                colors: <Color>[Color(0x99000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
