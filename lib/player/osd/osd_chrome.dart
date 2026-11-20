import 'dart:ui' as ui;

import '../../design/ps_tokens.dart';

/// One frame of the independent OSD chrome, drawn with plain `dart:ui`.
///
/// This is the rendering half of the OSD split: the values come from
/// `MpvViewState`, the layout is the same chrome the Lua side used to draw,
/// but the pixels are composited by DWM as 8-bit SDR — mpv's colour pipeline,
/// and with it HDR passthrough, never touches them.
///
/// No Flutter widgets: a `PictureRecorder` canvas rasterizes straight into the
/// layered window's bitmap. Pure functions so the geometry is unit-testable
/// without a renderer.
abstract final class OsdChrome {
  /// Height of the chrome band at the bottom of the stage.
  static const double bandHeight = 150;

  /// The seek bar's interactive strip, slightly taller than its visual line so
  /// a finger or a cursor does not have to land on 8 pixels.
  static const double seekHitHeight = 56;

  static const double safeX = 96;

  /// The rectangles that answer `HTCLIENT`. Everything else in the OSD window
  /// lets the pointer fall through to the video window below.
  static List<ui.Rect> hotZones(ui.Size size) {
    final double y = size.height - bandHeight;
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
  static void paint(
    ui.Canvas canvas,
    ui.Size size,
    OsdChromeModel model,
  ) {
    final double y = size.height - bandHeight;

    // A single soft plate under the band. Half the density of the Lua scrim:
    // this chrome is 8-bit SDR composited by DWM, not a 203-nit passenger in a
    // PQ swapchain, so it does not need the legibility crutch.
    final ui.Paint scrim = ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(0, y),
        ui.Offset(0, size.height),
        <ui.Color>[
          const ui.Color(0x00000000),
          ui.Color.fromARGB(120, 5, 6, 12),
          ui.Color.fromARGB(190, 5, 6, 12),
        ],
        <double>[0, 0.45, 1],
      );
    canvas.drawRect(ui.Rect.fromLTWH(0, y, size.width, bandHeight), scrim);

    final double innerBottom = size.height - 34;

    _text(
      canvas,
      _clock(model.position),
      ui.Offset(safeX, innerBottom - 18),
      24,
      PsColor.text.withValues(alpha: 0.95),
      weight: ui.FontWeight.w600,
    );

    final double totalWidth = _textWidth(_clock(model.duration), 20);
    _text(
      canvas,
      _clock(model.duration),
      ui.Offset(size.width - safeX - totalWidth, innerBottom - 16),
      20,
      PsColor.text.withValues(alpha: 0.62),
    );

    // Seek line between the two clocks.
    final double seekLeft = safeX + 96;
    final double seekRight = size.width - safeX - 96 - totalWidth - 40;
    final double seekY = innerBottom - 8;
    final double progress =
        model.duration > 0 ? (model.position / model.duration).clamp(0.0, 1.0) : 0;
    if (model.scrubbing != null) {
      final double scrub = model.scrubbing!.clamp(0.0, 1.0);
      _seekLine(canvas, seekLeft, seekRight, seekY, scrub, model.accent,
          hover: true);
    } else {
      _seekLine(canvas, seekLeft, seekRight, seekY, progress, model.accent,
          hover: model.hoverSeek);
    }

    // Left badges: what the file is being decoded as. Mirrors the Lua badge
    // row but at half the ink, for the same SDR reason as the scrim above.
    final double badgeY = innerBottom - 74;
    double bx = safeX;
    for (final String badge in model.badges) {
      final double width = _textWidth(badge, 15) + 22;
      final ui.Rect box = ui.Rect.fromLTWH(bx, badgeY, width, 30);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(box, const ui.Radius.circular(6)),
        ui.Paint()..color = ui.Color.fromARGB(60, 255, 255, 255),
      );
      _text(canvas, badge, ui.Offset(bx + 11, badgeY + 7), 15,
          PsColor.text.withValues(alpha: 0.88));
      bx += width + 10;
    }

    // Volume, right of the badges on the same line.
    if (!model.muted) {
      const double volumeWidth = 220;
      final double vx = size.width - safeX - volumeWidth;
      const double vy = badgeY + 14;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(vx, vy - 3, volumeWidth, 6),
          const ui.Radius.circular(3),
        ),
        ui.Paint()..color = ui.Color.fromARGB(46, 255, 255, 255),
      );
      final double filled = (model.volume / 100).clamp(0.0, 1.0) * volumeWidth;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(vx, vy - 3, filled, 6),
          const ui.Radius.circular(3),
        ),
        ui.Paint()..color = PsColor.text,
      );
      _text(
        canvas,
        '${model.volume.round()}',
        ui.Offset(vx + volumeWidth + 14, vy - 11),
        17,
        PsColor.text.withValues(alpha: 0.7),
      );
    }

    // Pause state, dead centre of the picture area.
    if (model.paused) {
      final double cx = size.width / 2;
      final double cy = (size.height - bandHeight) / 2;
      _text(
        canvas,
        '已暂停',
        ui.Offset(cx - 46, cy - 22),
        44,
        PsColor.text,
        weight: ui.FontWeight.w600,
      );
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
        ui.Paint()..color = ui.Color.fromARGB(215, 5, 6, 12),
      );
      _text(canvas, message, ui.Offset(left + 28, 40 + 17), 22, PsColor.text);
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
      ui.Paint()..color = ui.Color.fromARGB(46, 255, 255, 255),
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
      ui.Paint()..color = PsColor.text,
    );
  }

  static const ui.TextStyle _white = ui.TextStyle(color: ui.Color(0xFFFFFFFF));

  static double _textWidth(String text, double size, {ui.FontWeight weight = ui.FontWeight.w400}) {
    final ui.ParagraphBuilder builder = _builder(size, weight);
    builder.addText(text);
    final ui.Paragraph paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 4000));
    return paragraph.maxIntrinsicWidth;
  }

  static ui.ParagraphBuilder _builder(double size, ui.FontWeight weight) {
    return ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: size,
      fontFamily: 'Segoe UI',
      fontWeight: weight,
      textAlign: ui.TextAlign.left,
    ))
      ..pushStyle(ui.TextStyle(
        color: ui.Color(0xFFFFFFFF),
        fontSize: size,
        fontWeight: weight,
        fontFamily: 'Segoe UI',
      ));
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
    final String two(int v) => v.toString().padLeft(2, '0');
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
