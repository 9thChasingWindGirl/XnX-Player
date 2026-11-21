import 'package:material_ui/material_ui.dart';

import '../../design/ps_tokens.dart';
import '../core/tv_focusable.dart';

/// Console-style action button.
///
/// Two variants only: a solid white primary (one per region, the reference uses
/// it for "Play") and a hairline-bordered secondary. The focus ring is drawn by
/// the stage, so the button itself stays a plain surface.
class PsButton extends StatelessWidget {
  const PsButton({
    super.key,
    required this.label,
    this.icon,
    this.primary = false,
    this.onSelect,
    this.width,
    this.height = 64,
    this.enabled = true,
    this.accent,
    this.focusId,
  });

  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback? onSelect;
  final double? width;
  final double height;
  final bool enabled;
  final Color? accent;

  /// Optional stable address (see `FocusIds`), so a page can come back to this
  /// button — the hero's Play button is the one that matters.
  final String? focusId;

  @override
  Widget build(BuildContext context) {
    // A white primary fill turns the white focus ring into a second, slightly
    // larger outline around the same pill — two rounded shapes with nothing
    // between them. The accent fill keeps the ring legible as a ring.
    const Color foreground = PsColor.text;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: TvFocusable(
        enabled: enabled,
        focusId: focusId,
        radius: PsRadius.pill,
        accent: accent ?? PsColor.focusRing,
        onSelect: onSelect,
        child: Container(
          width: width,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: primary ? 30 : 24),
          decoration: BoxDecoration(
            color: primary ? PsColor.accent : PsColor.text.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(PsRadius.pill),
            border: primary
                ? Border.all(color: PsColor.text.withValues(alpha: 0.22), width: 1.5)
                : Border.all(color: PsColor.text.withValues(alpha: 0.18), width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 26, color: foreground),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: PsType.meta.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round icon-only button, used beside a primary action.
class PsIconButton extends StatelessWidget {
  const PsIconButton({
    super.key,
    required this.icon,
    this.onSelect,
    this.size = 64,
    this.accent,
    this.selected = false,
    this.focusId,
  });

  final IconData icon;
  final VoidCallback? onSelect;
  final double size;
  final Color? accent;
  final bool selected;
  final String? focusId;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: PsRadius.pill,
      focusId: focusId,
      onSelect: onSelect,
      accent: accent ?? PsColor.focusRing,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? PsColor.accent : PsColor.text.withValues(alpha: 0.08),
          border: Border.all(
            color: selected
                ? PsColor.text.withValues(alpha: 0.22)
                : PsColor.text.withValues(alpha: 0.18),
            width: selected ? 1.5 : 2,
          ),
        ),
        child: Icon(
          icon,
          size: size * 0.42,
          color: PsColor.text,
        ),
      ),
    );
  }
}
