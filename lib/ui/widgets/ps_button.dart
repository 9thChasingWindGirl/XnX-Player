import 'package:flutter/material.dart';

import '../../design/ps_tokens.dart';
import '../core/tv_focusable.dart';

/// PlayStation-style pill button. The primary variant is solid white with dark
/// text (that is what the console uses for "Play"); everything else is a
/// translucent chip with a hairline border.
class PsButton extends StatelessWidget {
  const PsButton({
    super.key,
    required this.label,
    this.icon,
    this.primary = false,
    this.onTap,
    this.autofocus = false,
    this.compact = false,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color foreground = primary ? const Color(0xFF101216) : PsColor.text;
    final double height = compact ? 48 : 56;

    return TvFocusable(
      autofocus: autofocus,
      enabled: enabled,
      radius: height / 2,
      focusScale: 1.06,
      onSelect: onTap,
      debugLabel: 'button:$label',
      child: AnimatedContainer(
        duration: PsMotion.base,
        curve: PsMotion.curve,
        height: height,
        padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 28),
        decoration: BoxDecoration(
          color: primary ? PsColor.text : const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(height / 2),
          border: primary ? null : Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: compact ? 20 : 22, color: foreground),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: PsType.label.copyWith(
                color: enabled ? foreground : PsColor.textDisabled,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
