import 'package:flutter/material.dart';

import '../../data/models/media_item.dart';
import '../../design/ps_tokens.dart';
import '../../ui/core/tv_focusable.dart';

/// PS5 home tile: a square key-art card, 200x200 at 1080p, that lifts slightly
/// and reveals its title when focused.
class HomeTile extends StatelessWidget {
  const HomeTile({
    super.key,
    required this.item,
    this.size = PsSpace.tileSize,
    this.onSelect,
    this.autofocus = false,
  });

  final MediaItem item;
  final double size;
  final VoidCallback? onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final List<Color> art = item.artwork;

    return TvFocusable(
      autofocus: autofocus,
      radius: PsRadius.card,
      onSelect: onSelect,
      debugLabel: 'tile:${item.title}',
      child: SizedBox(
        width: size,
        height: size,
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
                    colors: <Color>[art[0], art[1]],
                  ),
                ),
              ),
              // Oversized initial, like a key art silhouette.
              Align(
                alignment: const Alignment(0.35, -0.15),
                child: Text(
                  item.title.substring(0, 1),
                  style: TextStyle(
                    fontSize: size * 0.42,
                    fontWeight: FontWeight.w200,
                    color: const Color(0x14FFFFFF),
                    height: 1,
                  ),
                ),
              ),
              // Bottom scrim so the title always reads.
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: size * 0.62,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0x00000000), Color(0xE6000000)],
                      stops: <double>[0.0, 1.0],
                    ),
                  ),
                ),
              ),
              if (item.badge != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _Badge(text: item.badge!),
                ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PsType.label.copyWith(
                        fontWeight: FontWeight.w500,
                        shadows: const <Shadow>[Shadow(blurRadius: 8, color: Color(0x99000000))],
                      ),
                    ),
                    if (item.subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PsType.micro.copyWith(color: PsColor.textDim),
                      ),
                    ],
                    if (item.progress > 0) ...<Widget>[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: item.progress.clamp(0.0, 1.0).toDouble(),
                          minHeight: 3,
                          backgroundColor: const Color(0x40FFFFFF),
                          valueColor: const AlwaysStoppedAnimation<Color>(PsColor.text),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PsRadius.pill),
        border: Border.all(color: const Color(0x59FFFFFF), width: 1),
        color: const Color(0x33000000),
      ),
      child: Text(
        text,
        style: PsType.micro.copyWith(fontSize: 13, color: PsColor.text, letterSpacing: 0.6),
      ),
    );
  }
}
