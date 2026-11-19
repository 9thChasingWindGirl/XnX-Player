import 'package:material_ui/material_ui.dart';

import '../../data/models/media_item.dart';
import '../../design/ps_tokens.dart';

/// Artwork card used by every shelf.
///
/// The card draws at whatever size it is given: the shelf animates the box, so
/// artwork, scrim, badge and progress all scale together and the gliding ring
/// always hugs the visible edge.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    this.showTitle = true,
  });

  final MediaItem item;
  final double width;
  final double height;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.artwork;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PsRadius.card),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.55),
              blurRadius: 26,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PsRadius.card),
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
                Image.network(
                  item.posterUrl!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                      _ArtFallback(item: item),
                )
              else
                _ArtFallback(item: item),
              // Bottom scrim: the title has to read over any artwork.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color(0x00000000),
                        Color(0x1A000000),
                        Color(0xD9000000),
                      ],
                      stops: <double>[0.42, 0.68, 1.0],
                    ),
                  ),
                ),
              ),
              if (item.badge != null && item.badge!.isNotEmpty)
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000).withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(PsRadius.pill),
                      border: Border.all(color: PsColor.text.withValues(alpha: 0.22)),
                    ),
                    child: Text(
                      item.badge!,
                      style: PsType.micro.copyWith(
                        fontSize: 12,
                        letterSpacing: 1.2,
                        color: PsColor.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (showTitle && height >= 140)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: item.progress > 0.01 ? 18 : 12,
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PsType.label.copyWith(
                      fontSize: 18,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                      shadows: const <Shadow>[
                        Shadow(color: Color(0xB3000000), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              if (item.progress > 0.01)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 4,
                    color: PsColor.text.withValues(alpha: 0.16),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: item.progress.clamp(0.0, 1.0).toDouble(),
                      child: ColoredBox(color: item.accentColor),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtFallback extends StatelessWidget {
  const _ArtFallback({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.artwork;
    final String initial = item.title.isEmpty
        ? '·'
        : String.fromCharCode(item.title.runes.first);
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
        Positioned(
          right: -(((item.hashCode % 40) + 10).toDouble()),
          top: -20,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: art[2].withValues(alpha: 0.35),
            ),
          ),
        ),
        Center(
          child: Text(
            initial,
            style: PsType.display.copyWith(
              fontSize: 96,
              color: PsColor.text.withValues(alpha: 0.16),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Wide card for a live channel: logo top-left, name and group at the bottom.
class ChannelCard extends StatelessWidget {
  const ChannelCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
  });

  final MediaItem item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.artwork;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PsRadius.card),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[art[1], art[0]],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PsRadius.card),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (item.hasPoster)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 16, bottom: 56, right: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Image.network(
                      item.posterUrl!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain,
                      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                          Icon(
                        Icons.live_tv_rounded,
                        size: 40,
                        color: PsColor.text.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PsType.label.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.group ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PsType.micro.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Text(
                  'LIVE',
                  style: PsType.micro.copyWith(fontSize: 12, letterSpacing: 2, color: PsColor.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
