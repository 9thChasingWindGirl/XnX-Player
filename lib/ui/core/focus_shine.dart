import 'package:flutter/widgets.dart';

import '../../design/ps_tokens.dart';

/// The diagonal light sweep PS5 uses on the focused tile. It is deliberately a
/// slow, low-contrast band: the point is a hint of glass, not a highlight.
class FocusShine extends StatefulWidget {
  const FocusShine({
    super.key,
    required this.active,
    this.radius = PsRadius.card,
    this.intensity = 0.36,
  });

  final bool active;
  final double radius;
  final double intensity;

  @override
  State<FocusShine> createState() => _FocusShineState();
}

class _FocusShineState extends State<FocusShine> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PsMotion.shineCycle,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(FocusShine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.active ? 1 : 0,
        duration: PsMotion.base,
        curve: PsMotion.curve,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              return CustomPaint(
                painter: _ShinePainter(
                  progress: _controller.value,
                  radius: widget.radius,
                  intensity: widget.intensity,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ShinePainter extends CustomPainter {
  _ShinePainter({
    required this.progress,
    required this.radius,
    required this.intensity,
  });

  final double progress;
  final double radius;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final RRect clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    canvas.save();
    canvas.clipRRect(clip);

    final Offset center = size.center(Offset.zero);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.62);
    canvas.translate(-center.dx, -center.dy);

    final double bandWidth = size.width * 0.34;
    final double travel = size.width + bandWidth * 2;
    final double left = -bandWidth + progress * travel;
    final Rect band = Rect.fromLTWH(left, -size.height, bandWidth, size.height * 3);

    final Paint paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[
          const Color(0x00FFFFFF),
          Color.fromRGBO(255, 255, 255, intensity),
          const Color(0x00FFFFFF),
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      ).createShader(band);

    canvas.drawRect(band, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShinePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.radius != radius ||
        oldDelegate.intensity != intensity;
  }
}
