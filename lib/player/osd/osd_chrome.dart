import 'dart:ui' as ui;

/// One frame of the independent OSD chrome, drawn with plain `dart:ui`.
///
/// The values come from `MpvViewState`, the layout is the chrome the Lua side
/// used to draw, but the pixels are composited by DWM as 8-bit SDR — mpv's
/// colour pipeline, and with it HDR passthrough, never touches them.
///
/// No Flutter widgets: a `PictureRecorder` canvas rasterizes straight into the
/// layered window's bitmap. Geometry helpers are pure so they are unit-testable
/// without a renderer.
abstract final class OsdChrome {
  /// Height of the chrome band at the bottom of the stage.
  static const double bandHeight = 150;

  /// The seek bar's interactive strip, slightly taller than its visual line so
  /// a cursor does not have to land on 8 pixels.
  static const double seekHitHeight = 56;

  static const double safeX = 96;

  /// The rectangles that answer to the chrome. Everything else in the OSD
  /// window's area belongs to the video below (the layer itself is
  /// see-through; this is what the Dart-side forwarder tests against).
  static List<ui.Rect> hotZones(ui.Size size) {
    return <ui.Rect>[
      ui.Rect.fromLTWH(
        safeX,
        size.height - seekHitHeight - 24,
        size.width - safeX * 2,
        seekHitHeight + 24,
      ),
    ];
  }

  /// Rasterizes one chrome frame into [canvas].
  static void paint(ui.Canvas canvas, ui.Size size, OsdChromeModel model) {
    final double bandTop = size.height - bandHeight;

    final ui.Paint scrim = ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(0, 0),
        const ui.Offset(0, bandHeight),
        const <ui.Color>[
          ui.Color(0x00000000),
          ui.Color(0x7805060C),
          ui.Color(0xBE05060C),
        ],
        const <double>[0, 0.45, 1],
      );
    canvas.translate(0, bandTop);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.width, bandHeight),
      scrim,
    );
    canvas.translate(0, -bandTop);

    final double innerBottom = size.height - 34;

    _text(canvas, _clock(model.position), ui.Offset(safeX, innerBottom - 18), 24,
        color: const ui.Color(0xFFF2F4F8), weight: ui.FontWeight.w600);

    final double totalWidth = _textWidth(_clock(model.duration), 20);
    _text(canvas, _clock(model.duration),
        ui.Offset(size.width - safeX - totalWidth, innerBottom - 16), 20,
        color: const ui.Color(0x9EF2F4F8));

    // Seek line between the two clocks.
    const double seekLeft = safeX + 96;
    final double seekRight = size.width - safeX - 96 - totalWidth - 40;
    final double seekY = innerBottom - 8;
    final double progress =
        model.duration > 0 ? (model.position / model.duration).clamp(0.0, 1.0) : 0;
    final double knobValue = model.scrubbing ?? progress;
    _seekLine(canvas, seekLeft, seekRight, seekY, knobValue, model.accent,
        hover: model.hoverSeek || model.scrubbing != null);

    // Left badges: what the file is being decoded as. Half the ink of the Lua
    // badge row, for the same SDR reason as the scrim above.
    const double badgeY = 0;
    double bx = safeX;
    for (final String badge in model.badges) {
      final double width = _textWidth(badge, 15) + 22;
      final ui.Rect box = ui.Rect.fromLTWH(bx, badgeY + 34, width, 30);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(box, const ui.Radius.circular(6)),
        ui.Paint()..color = const ui.Color(0x3CFFFFFF),
      );
      _text(canvas, badge, ui.Offset(bx + 11, badgeY + 41), 15,
          color: const ui.Color(0xE0FFFFFF));
      bx += width + 10;
    }

    // Volume, right-aligned on the badge line.
    if (!model.muted) {
      const double volumeWidth = 220;
      final double vx = size.width - safeX - volumeWidth;
      const double vy = badgeY + 48;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(vx, vy - 3, volumeWidth, 6),
          const ui.Radius.circular(3),
        ),
        ui.Paint()..color = const ui.Color(0x2EFFFFFF),
      );
      final double filled = (model.volume / 100).clamp(0.0, 1.0) * volumeWidth;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(vx, vy - 3, filled, 6),
          const ui.Radius.circular(3),
        ),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      _text(canvas, '${model.volume.round()}', ui.Offset(vx + volumeWidth + 14, vy - 11), 17,
          color: const ui.Color(0xB3FFFFFF));
    }

    // Pause state, centred on the picture area.
    if (model.paused) {
      final double cx = size.width / 2;
      final double cy = (size.height - bandHeight) / 2;
      _text(canvas, '已暂停', ui.Offset(cx - 46, cy - 22), 44,
          color: const ui.Color(0xFFFFFFFF), weight: ui.FontWeight.w600);
    }

    if ((model.toast ?? '').isNotEmpty) {
      final String message = model.toast!;
      final double width = _textWidth(message, 22) + 56;
      final double left = (size.width - width) / 2;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(left, 40, width, 56),
          const ui.Radius.circular(14),
        ),
        ui.Paint()..color = const ui.Color(0xD705060C),
      );
      _text(canvas, message, ui.Offset(left + 28, 57), 22,
          color: const ui.Color(0xFFFFFFFF));
    }
  }

  static void _seekLine(
    ui.Canvas canvas,
    double left,
    double right,
    double y,
    double progress,
    ui.Color accent, {
    bool hover = false,
  }) {
    final ui.Rect track = ui.Rect.fromLTRB(left, y - 4, right, y + 4);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(track, const ui.Radius.circular(4)),
      ui.Paint()..color = const ui.Color(0x2EFFFFFF),
    );
    final ui.Rect fill = ui.Rect.fromLTRB(left, y - 4, left + (right - left) * progress, y + 4);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(fill, const ui.Radius.circular(4)),
      ui.Paint()..color = accent,
    );
    final double knobX = left + (right - left) * progress;
    canvas.drawCircle(
      ui.Offset(knobX, y),
      hover ? 14 : 10,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  }

  static double _textWidth(String text, double size, {ui.FontWeight weight = ui.FontWeight.w400}) {
    final ui.ParagraphBuilder builder = _builder(size, weight);
    builder.addText(text);
    final ui.Paragraph paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 4000));
    return paragraph.maxIntrinsicWidth;
  }

  static ui.ParagraphBuilder _builder(double size, ui.FontWeight weight) {
    return ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: size,
        fontFamily: 'Segoe UI',
        fontWeight: weight,
        textAlign: ui.TextAlign.left,
      ),
    )..pushStyle(
        ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontSize: size,
          fontWeight: weight,
          fontFamily: 'Segoe UI',
        ),
      );
  }

  static void _text(
    ui.Canvas canvas,
    String text,
    ui.Offset at,
    double size, {
    ui.Color color = const ui.Color(0xFFFFFFFF),
    ui.FontWeight weight = ui.FontWeight.w400,
  }) {
    final ui.ParagraphBuilder builder = _builder(size, weight);
    builder.addText(text);
    final ui.Paragraph paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 4000));
    canvas.drawParagraph(paragraph, at);
  }

  static String _clock(double seconds) {
    final int total = seconds < 0 ? 0 : seconds.floor();
    final int h = total ~/ 3600;
    final int m = (total % 3600) ~/ 60;
    final int s = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

/// Everything one chrome frame needs, straight from `MpvViewState` plus the
/// couple of interactive bits the overlay tracks itself.
class OsdChromeModel {
  const OsdChromeModel({
    required this.position,
    required this.duration,
    required this.paused,
    required this.volume,
    required this.muted,
    required this.badges,
    required this.accent,
    this.scrubbing,
    this.hoverSeek = false,
    this.toast,
  });

  final double position;
  final double duration;
  final bool paused;
  final double volume;
  final bool muted;
  final List<String> badges;
  final ui.Color accent;

  /// 0..1 while the pointer is dragging the seek bar; null otherwise.
  final double? scrubbing;

  /// Whether the pointer sits on the seek strip — a slightly larger knob.
  final bool hoverSeek;
  final String? toast;
}
