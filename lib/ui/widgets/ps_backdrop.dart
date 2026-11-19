import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/ps_motion.dart';
import '../../design/ps_tokens.dart';
import '../core/motion_clock.dart';

/// Procedural stage behind every screen.
///
/// Three layers, as the craft guide asks for: a drifting backdrop, the content,
/// then overlays. The backdrop takes the palette of the focused cover and eases
/// toward it (spring frequency 4, i.e. a couple of seconds), so the whole screen
/// answers the selection instead of sitting behind it.
class PsBackdrop extends StatefulWidget {
  const PsBackdrop({
    super.key,
    this.palette,
    this.dim = 0,
    this.animate = true,
  });

  /// `[dark, mid, accent]`. Defaults to the neutral stage.
  final List<Color>? palette;

  /// 0..1 extra dimming, used when a sheet or dialog is open.
  final double dim;

  final bool animate;

  @override
  State<PsBackdrop> createState() => _PsBackdropState();
}

class _PsBackdropState extends State<PsBackdrop> {
  late final SpringColor _dark = SpringColor(_at(0), frequency: 4);
  late final SpringColor _mid = SpringColor(_at(1), frequency: 4);
  late final SpringColor _accent = SpringColor(_at(2), frequency: 4);

  double _last = -1;

  Color _at(int index) {
    final List<Color> palette = widget.palette ?? <Color>[
      PsColor.bgDeep,
      PsColor.bg,
      PsColor.accent,
    ];
    if (palette.isEmpty) {
      return PsColor.bgDeep;
    }
    return palette[index.clamp(0, palette.length - 1).toInt()];
  }

  @override
  void didUpdateWidget(PsBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dark.setTarget(_at(0));
    _mid.setTarget(_at(1));
    _accent.setTarget(_at(2));
  }

  @override
  Widget build(BuildContext context) {
    return MotionBuilder(
      builder: (BuildContext context, double dt) {
        final MotionClock clock = MotionScope.of(context);
        if (clock.time != _last) {
          _last = clock.time;
          _dark.update(dt);
          _mid.update(dt);
          _accent.update(dt);
        }
        return SizedBox.expand(
          child: CustomPaint(
            painter: _AuroraPainter(
              dark: _dark.value,
              mid: _mid.value,
              accent: _accent.value,
              time: widget.animate && !clock.reduceMotion ? clock.time : 0,
              dim: widget.dim,
            ),
          ),
        );
      },
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.dark,
    required this.mid,
    required this.accent,
    required this.time,
    required this.dim,
  });

  final Color dark;
  final Color mid;
  final Color accent;
  final double time;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.lerp(dark, PsColor.bgDeep, 0.15) ?? dark,
            Color.lerp(dark, mid, 0.55) ?? mid,
            PsColor.bgDeep,
          ],
          stops: const <double>[0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    _blob(
      canvas,
      Offset(
        size.width * 0.80 + math.sin(time * 0.07) * 60,
        -size.height * 0.16 + math.cos(time * 0.05) * 40,
      ),
      size.width * 0.58,
      accent,
      0.34,
    );
    _blob(
      canvas,
      Offset(
        size.width * 0.16 + math.cos(time * 0.043) * 80,
        size.height * 1.10,
      ),
      size.width * 0.52,
      mid,
      0.32,
    );
    _blob(
      canvas,
      Offset(
        size.width * 0.52 + math.sin(time * 0.031) * 140,
        size.height * 0.52,
      ),
      size.width * 0.62,
      mid,
      0.14,
    );

    // Left scrim so hero copy always reads, whatever the artwork behind it.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[Color(0xD9000000), Color(0x66000000), Color(0x00000000)],
          stops: <double>[0.0, 0.42, 0.78],
        ).createShader(rect),
    );

    // Vignette: keeps the eye in the middle and hides the window edges.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.92,
          colors: <Color>[
            const Color(0x00000000),
            const Color(0x33000000),
            Color.fromARGB((0x9E + 90 * dim).round().clamp(0, 255).toInt(), 0, 0, 0),
          ],
          stops: const <double>[0.35, 0.74, 1.0],
        ).createShader(rect),
    );

    if (dim > 0) {
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0xFF000000).withValues(alpha: 0.45 * dim),
      );
    }
  }

  void _blob(Canvas canvas, Offset center, double radius, Color color, double alpha) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) {
    return oldDelegate.dark != dark ||
        oldDelegate.mid != mid ||
        oldDelegate.accent != accent ||
        oldDelegate.dim != dim ||
        (oldDelegate.time - time).abs() > 0.008;
  }
}
