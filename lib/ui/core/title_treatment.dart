import 'package:material_ui/material_ui.dart';

import '../../data/models/media_item.dart';
import 'poster_image.dart';

/// The title of a title, drawn the way the source intends it.
///
/// Emby, Jellyfin and Plex all carry a *clearlogo* — the wordmark as transparent
/// artwork, designed by whoever made the poster. Drawing a system font over
/// that poster is the single most "this is a file manager" thing a media client
/// can do, so any surface with room for a title uses this widget:
///
/// * logo present → drawn at its own aspect ratio inside a fixed box, so the
///   layout underneath does not jump when the artwork changes;
/// * logo missing or broken → the plain title in [style], as before.
///
/// The fallback is a real state change rather than a widget placed under the
/// image: logos are transparent PNGs, so a title behind one would show through
/// its holes.
class TitleTreatment extends StatefulWidget {
  const TitleTreatment({
    super.key,
    required this.item,
    required this.style,
    this.maxWidth = 1000,
    this.logoHeight = 120,
    this.maxLines = 1,
    this.alignment = Alignment.centerLeft,
  });

  final MediaItem item;
  final TextStyle style;

  /// Both limits matter: a wide wordmark and a square one must both fit.
  final double maxWidth;
  final double logoHeight;

  final int maxLines;
  final Alignment alignment;

  @override
  State<TitleTreatment> createState() => _TitleTreatmentState();
}

class _TitleTreatmentState extends State<TitleTreatment> {
  /// Set when the logo request fails, so the widget settles on the text instead
  /// of retrying an image that will not arrive.
  bool _broken = false;

  @override
  void didUpdateWidget(TitleTreatment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _broken = false;
    }
  }

  Text _text() {
    return Text(
      widget.item.title,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? logo = widget.item.logoUrl;
    if (_broken || logo == null || logo.isEmpty) {
      return _text();
    }

    return SizedBox(
      width: widget.maxWidth,
      height: widget.logoHeight,
      child: Align(
        alignment: widget.alignment,
        child: posterImage(
          logo,
          fit: BoxFit.contain,
          alignment: widget.alignment,
          gapless: true,
          headers: widget.item.logoHeaders,
          height: widget.logoHeight,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
            // Called during layout: switch on the next frame rather than
            // rebuilding mid-paint.
            if (!_broken) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_broken) {
                  setState(() => _broken = true);
                }
              });
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
