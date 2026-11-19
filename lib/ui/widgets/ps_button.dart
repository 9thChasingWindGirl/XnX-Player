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
  });

  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback? onSelect;
  final double? width;
  final double height;
  final bool enabled;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Color foreground = primary ? const Color(0xFF0B0D16) : PsColor.text;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: TvFocusable(
        enabled: enabled,
        radius: PsRadius.pill,
        accent: accent ?? PsColor.focusRing,
        onSelect: onSelect,
        child: Container(
          width: width,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: primary ? 30 : 24),
          decoration: BoxDecoration(
            color: primary ? PsColor.text : PsColor.text.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(PsRadius.pill),
            border: primary
                ? null
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
  });

  final IconData icon;
  final VoidCallback? onSelect;
  final double size;
  final Color? accent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: PsRadius.pill,
      onSelect: onSelect,
      accent: accent ?? PsColor.focusRing,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? PsColor.text : PsColor.text.withValues(alpha: 0.08),
          border: selected ? null : Border.all(color: PsColor.text.withValues(alpha: 0.18), width: 2),
        ),
        child: Icon(
          icon,
          size: size * 0.42,
          color: selected ? const Color(0xFF0B0D16) : PsColor.text,
        ),
      ),
    );
  }
}
