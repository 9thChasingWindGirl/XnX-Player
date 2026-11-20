import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/focus_ids.dart';
import '../../ui/core/poster_image.dart';
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

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.artwork;
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
            Positioned(
              left: PsSpace.heroArtX + slide * 1.6,
              top: PsSpace.heroArtY + bob,
              width: PsSpace.heroArt,
              height: PsSpace.heroArt,
              child: _HeroArt(item: item),
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
              top: 248,
              width: 1160,
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PsType.display,
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

class _HeroArt extends StatelessWidget {
  const _HeroArt({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.artwork;
    final String? url = item.backdropUrl ?? item.posterUrl;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PsRadius.hero),
        boxShadow: PsElevation.heroGlow(art[2]),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PsRadius.hero),
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
            if (url != null && url.isNotEmpty)
              posterImage(
                url,
                fit: BoxFit.cover,
                gapless: true,
                errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                    const SizedBox.shrink(),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PsRadius.hero),
                border: Border.all(color: PsColor.text.withValues(alpha: 0.16), width: 2),
              ),
            ),
          ],
        ),
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
