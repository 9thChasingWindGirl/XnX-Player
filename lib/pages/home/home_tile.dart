import 'package:material_ui/material_ui.dart';

import '../../data/models/media_item.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/poster_image.dart';

/// Artwork card used by every shelf.
///
/// The card draws at whatever size it is given: the shelf animates the box, so
/// artwork, scrim, badge and progress all scale together and the gliding ring
/// always hugs the visible edge.
///
/// [focused] is what makes a shelf read as *one lit card among many*, which is
/// the reference's home screen (`aurora.cpp:483-495`): resting cards are drawn
/// at 82 % over the stage and cast no shadow, the focused one is drawn full
/// strength, lifted, and at the larger corner. Pass `null` on surfaces that do
/// not track focus per card (a plain list) and the card stays lit and quiet.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    this.showTitle = true,
    this.focused,
  });

  final MediaItem item;
  final double width;
  final double height;
  final bool showTitle;

  /// `true` / `false` when the surface knows which card is focused; `null` when
  /// it does not, in which case the card is neither dimmed nor lifted.
  ///
  /// Growth is *not* here: the `TvFocusable` above the card owns
  /// `highlightScale`, so artwork and ring scale together and this widget only
  /// has to know how to *look* focused.
  final bool? focused;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.palette;
    final bool lit = focused ?? true;
    final bool grown = focused == true;
    final double radius = grown ? PsRadius.cardFocused : PsRadius.card;

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: grown ? PsElevation.cardFocused : PsElevation.cardResting,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
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
                fit: BoxFit.cover,
                gapless: true,
                errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                    _ArtFallback(item: item),
              )
            else
              _ArtFallback(item: item),
            // Unfocused artwork is dimmed, not desaturated: the colour still
            // identifies the title, it just stops competing with the one card
            // the user is actually on.
            if (!lit) const ColoredBox(color: Color(0x2E000000)),
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
                // `CardLook::badge_size` is 16 and the pill is `size + 14`
                // tall, inset by `edge` from the corner (`card.cpp:341-357`).
                // Upstream fills it with the accent; a poster is already
                // colour, so this keeps a black plate and takes only the size.
                child: Container(
                  height: PsCard.badgeSize + 14,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000).withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(PsRadius.pill),
                    border: Border.all(color: PsColor.text.withValues(alpha: 0.22)),
                  ),
                  child: Text(
                    item.badge!,
                    style: PsType.label.copyWith(
                      fontSize: PsCard.badgeSize,
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
            // The watched bar sits *inside* the art, inset by
            // `max(10, radius * 0.45)` and 6 tall, with a track at 50 %
            // because it has to read on any picture (`card.cpp:300-318`).
            // Ours used to run edge to edge at 4 px and 16 %, i.e. it read as
            // a border rather than as progress.
            if (item.progress > 0.01)
              Positioned(
                left: PsCard.progressInset,
                right: PsCard.progressInset,
                bottom: PsCard.progressInset - 2,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(PsCard.progressHeight / 2),
                  child: SizedBox(
                    height: PsCard.progressHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ColoredBox(color: PsColor.text.withValues(alpha: 0.5)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: item.progress.clamp(0.0, 1.0).toDouble(),
                          child: ColoredBox(color: item.accentColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return SizedBox(width: width, height: height, child: card);
  }
}

class _ArtFallback extends StatelessWidget {
  const _ArtFallback({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.palette;
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

/// A Plex-style shelf card: plain artwork at rest, with a caption that appears
/// when the card is focused.
///
/// Plex keeps its rows visually quiet — no scrim or title on every poster, just
/// the artwork — and reveals the name on hover. That is the opposite of the
/// console card, which always writes the title over the art, so the home screen
/// uses this widget while the library grid keeps [PosterCard].
class PlexCard extends StatelessWidget {
  const PlexCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    this.focused = false,
    this.wide = false,
  });

  final MediaItem item;
  final double width;
  final double height;
  final bool focused;

  /// 16:9 shelves (continue watching, live) caption every card; poster shelves
  /// caption only the focused one.
  final bool wide;

  static const double radius = 8;

  @override
  Widget build(BuildContext context) {
    final bool channel = item.kind == MediaKind.channel;
    final bool caption = focused || wide || channel;
    final List<Color> art = item.palette;
    // Wide shelves are 16:9, so they prefer the thumbnail (a still) over the
    // 2:3 poster; a poster shelf does the opposite.
    final String? imageUrl = wide ? item.thumbUrl : item.posterUrl;
    final bool hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PlexColor.surface,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
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
              if (hasImage)
                (channel
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 46),
                        child: posterImage(
                          imageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (BuildContext context, Object error, StackTrace? stack) =>
                                  const SizedBox.shrink(),
                        ),
                      )
                    : posterImage(
                        imageUrl!,
                        fit: BoxFit.cover,
                        gapless: true,
                        errorBuilder:
                            (BuildContext context, Object error, StackTrace? stack) =>
                                _ArtFallback(item: item),
                      ))
              else
                _ArtFallback(item: item),
              if (caption)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          Color(0xE6000000),
                          Color(0x66000000),
                          Color(0x00000000),
                        ],
                        stops: <double>[0.0, 0.42, 0.78],
                      ),
                    ),
                  ),
                ),
              if (item.badge != null && item.badge!.isNotEmpty)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      item.badge!,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: PlexColor.text,
                      ),
                    ),
                  ),
                ),
              if (caption)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: item.progress > 0.01 ? 15 : 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: wide ? 18 : 16,
                          height: 1.22,
                          fontWeight: FontWeight.w600,
                          color: PlexColor.text,
                          shadows: const <Shadow>[
                            Shadow(color: Color(0xB3000000), blurRadius: 6),
                          ],
                        ),
                      ),
                      if (wide || focused) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          _caption(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            color: PlexColor.textDim,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (item.progress > 0.01)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ColoredBox(color: Colors.white.withValues(alpha: 0.25)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: item.progress.clamp(0.0, 1.0).toDouble(),
                          child: const ColoredBox(color: PlexColor.amber),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _caption(MediaItem item) {
    if (item.kind == MediaKind.channel) {
      return item.group ?? '直播';
    }
    if (item.subtitle != null && item.subtitle!.isNotEmpty) {
      return item.subtitle!;
    }
    final List<String> parts = <String>[
      if (item.year != null) '${item.year}',
      if (item.duration != null) item.runtimeLabel,
    ];
    return parts.join('  ·  ');
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
    final List<Color> art = item.palette;
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
          boxShadow: PsElevation.cardResting,
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
                    child: posterImage(
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
