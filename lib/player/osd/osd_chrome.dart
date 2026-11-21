import 'dart:math' as math;
import 'dart:ui' as ui;

/// One clickable region of the independent chrome.
class OsdZone {
  const OsdZone(this.id, this.rect);

  /// `seek`, `play`, `back10`, `fwd10`, or `menu:<id>`.
  final String id;
  final ui.Rect rect;
}

/// One frame of the independent OSD chrome, drawn with plain `dart:ui`.
///
/// The layout mirrors the Lua stage in design units: the same title, badge and
/// seek lines, plus the transport and menu row. It is painted by DWM as 8-bit
/// SDR, outside mpv's colour pipeline, which is what keeps it crisp when HDR
/// passthrough is on.
abstract final class OsdChrome {
  static const double designW = 1920;
  static const double designH = 1080;
  static const double safeX = 96;

  static const double titleY = 770;
  static const double metaY = 832;
  static const double barY = 884;
  static const double ctrlY = 902;
  static const double ctrlH = 66;
  static const double hintY = 992;

  /// Height of the scrim, in design units from the bottom.
  static const double bandHeight = 380;

  static const double seekHitHeight = 56;

  static const Map<String, String> menuLabels = <String, String>{
    'audio': '音轨',
    'subtitle': '字幕',
    'chapters': '章节',
    'speed': '速度',
    'playlist': '列表',
    'video': '画面',
    'stats': '统计',
    'more': '更多',
  };

  static const String hint =
      '空格 暂停   ←→ 快退/快进   ↑↓ 音量   Tab 隐藏界面   H 快捷键   Esc 返回';

  static double _sx(ui.Size size) => size.width / designW;

  static double _sy(ui.Size size) => size.height / designH;

  /// The seek line's rectangle — one source of truth for paint, hit testing and
  /// pointer-to-fraction conversion.
  static ui.Rect seekTrack(ui.Size size) {
    final double sx = _sx(size);
    final double sy = _sy(size);
    final double left = safeX * sx;
    final double right = math.max(left + 40, size.width - safeX * sx);
    return ui.Rect.fromLTRB(left, (barY - 6) * sy, right, (barY + 6) * sy);
  }

  static double fractionAt(ui.Size size, double x) {
    final ui.Rect track = seekTrack(size);
    return ((x - track.left) / track.width).clamp(0.0, 1.0);
  }

  /// The seek strip, kept for the geometry tests and the wheel zone.
  static List<ui.Rect> hotZones(ui.Size size) {
    final ui.Rect track = seekTrack(size);
    const double half = seekHitHeight / 2;
    return <ui.Rect>[
      ui.Rect.fromLTRB(
        track.left,
        track.center.dy - half,
        track.right,
        track.center.dy + half,
      ),
    ];
  }

  /// Every interactive rectangle, in paint coordinates. Painting and input use
  /// this one list, so a drawn button is always the button that answers.
  static List<OsdZone> zones(ui.Size size) {
    final double sx = _sx(size);
    final double sy = _sy(size);
    final List<OsdZone> out = <OsdZone>[];
    final ui.Rect track = seekTrack(size);
    out.add(OsdZone(
      'seek',
      ui.Rect.fromLTRB(track.left, (barY - 18) * sy, track.right, (barY + 18) * sy),
    ));

    final double top = ctrlY * sy;
    final double height = ctrlH * sy;
    out.add(OsdZone('play', ui.Rect.fromLTWH(safeX * sx, top, 62 * sx, height)));
    out.add(OsdZone('back10', ui.Rect.fromLTWH((safeX + 68) * sx, top, 58 * sx, height)));
    out.add(OsdZone('fwd10', ui.Rect.fromLTWH((safeX + 132) * sx, top, 58 * sx, height)));

    final double labelWidth = 80 * sx;
    double right = size.width - safeX * sx;
    for (final String id in menuLabels.keys.toList().reversed) {
      right -= labelWidth;
      out.add(OsdZone('menu:$id', ui.Rect.fromLTWH(right, top, labelWidth, height)));
      right -= 6 * sx;
    }
    return out;
  }

  static void paint(ui.Canvas canvas, ui.Size size, OsdChromeModel model) {
    final double sx = _sx(size);
    final double sy = _sy(size);
    double x(double v) => v * sx;
    double y(double v) => v * sy;
    double font(double v) => v * sy;

    // Scrim: the chrome must read over a bright frame.
    final ui.Paint scrim = ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(0, y(700)),
        ui.Offset(0, size.height),
        const <ui.Color>[
          ui.Color(0x00000000),
          ui.Color(0x8C05060C),
          ui.Color(0xC805060C),
        ],
        const <double>[0, 0.45, 1],
      );
    canvas.drawRect(ui.Rect.fromLTRB(0, y(700), size.width, size.height), scrim);

    if (model.title.isNotEmpty) {
      _textEllipsis(
        canvas,
        model.title,
        ui.Offset(x(safeX), y(titleY)),
        font(40),
        size.width - x(safeX) * 2,
        weight: ui.FontWeight.w600,
      );
    }

    // Format badges, one pill each.
    double bx = x(safeX);
    for (final String badge in model.badges) {
      final double width = _textWidth(badge, font(16)) + x(22);
      final ui.Rect box = ui.Rect.fromLTWH(bx, y(metaY), width, font(28));
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(box, ui.Radius.circular(x(6))),
        ui.Paint()..color = const ui.Color(0x3CFFFFFF),
      );
      _text(canvas, badge, ui.Offset(bx + x(11), y(metaY) + font(6)), font(16),
          color: const ui.Color(0xE6FFFFFF));
      bx += width + x(8);
    }

    // Seek line.
    final ui.Rect track = seekTrack(size);
    final double progress =
        model.duration > 0 ? (model.position / model.duration).clamp(0.0, 1.0) : 0;
    final double knob = model.scrubbing ?? progress;
    _seekLine(canvas, track, knob, model.accent,
        hover: model.hoverSeek || model.scrubbing != null, radius: font(8));

    // Transport and menus, drawn from the same zones input tests.
    final List<OsdZone> buttonZones = zones(size);
    for (final OsdZone zone in buttonZones) {
      switch (zone.id) {
        case 'play':
          _playGlyph(canvas, zone.rect, model.paused, font(20));
          break;
        case 'back10':
          _centeredText(canvas, '-10', zone.rect, font(21));
          break;
        case 'fwd10':
          _centeredText(canvas, '+10', zone.rect, font(21));
          // The clock sits after the three transport buttons.
          final double timeX = x(safeX + 206);
          final ui.Paragraph time = _paragraph(
            '${_clock(model.position)} / ${_clock(model.duration)}',
            font(21),
            ui.FontWeight.w500,
            const ui.Color(0xE6F2F4F8),
            monospace: true,
          );
          canvas.drawParagraph(time, ui.Offset(timeX, zone.rect.center.dy - font(12)));
          break;
        default:
          if (zone.id.startsWith('menu:')) {
            final String label = menuLabels[zone.id.substring(5)] ?? '';
            _centeredText(canvas, label, zone.rect, font(20), dim: true);
          }
          break;
      }
    }

    _text(canvas, hint, ui.Offset(x(safeX), y(hintY)), font(16),
        color: const ui.Color(0x8AFFFFFF));

    if (model.paused) {
      _centeredText(
        canvas,
        '已暂停',
        ui.Rect.fromCenter(
          center: ui.Offset(size.width / 2, y(500)),
          width: size.width,
          height: font(60),
        ),
        font(44),
      );
    }

    if ((model.toast ?? '').isNotEmpty) {
      final String message = model.toast!;
      final double width = _textWidth(message, font(22)) + x(56);
      final double left = (size.width - width) / 2;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(left, y(40), width, font(56)),
          ui.Radius.circular(x(14)),
        ),
        ui.Paint()..color = const ui.Color(0xD705060C),
      );
      _text(canvas, message, ui.Offset(left + x(28), y(57)), font(22),
          color: const ui.Color(0xFFFFFFFF));
    }
  }

  static void _seekLine(
    ui.Canvas canvas,
    ui.Rect track,
    double progress,
    ui.Color accent, {
    required bool hover,
    required double radius,
  }) {
    final double height = track.height / 2;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(track, ui.Radius.circular(height)),
      ui.Paint()..color = const ui.Color(0x2EFFFFFF),
    );
    final ui.Rect fill = ui.Rect.fromLTRB(
      track.left,
      track.top,
      track.left + track.width * progress,
      track.bottom,
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(fill, ui.Radius.circular(height)),
      ui.Paint()..color = accent,
    );
    canvas.drawCircle(
      ui.Offset(track.left + track.width * progress, track.center.dy),
      hover ? radius * 1.6 : radius,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  }

  static void _playGlyph(ui.Canvas canvas, ui.Rect zone, bool paused, double size) {
    final ui.Offset center = zone.center;
    final ui.Paint paint = ui.Paint()..color = const ui.Color(0xFFF2F4F8);
    if (paused) {
      final double w = size * 0.32;
      final double h = size;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(center.dx - w * 1.6, center.dy - h / 2, w, h),
          ui.Radius.circular(w * 0.25),
        ),
        paint,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(center.dx + w * 0.6, center.dy - h / 2, w, h),
          ui.Radius.circular(w * 0.25),
        ),
        paint,
      );
      return;
    }
    final ui.Path triangle = ui.Path()
      ..moveTo(center.dx - size * 0.36, center.dy - size * 0.6)
      ..lineTo(center.dx + size * 0.6, center.dy)
      ..lineTo(center.dx - size * 0.36, center.dy + size * 0.6)
      ..close();
    canvas.drawPath(triangle, paint);
  }

  static void _centeredText(
    ui.Canvas canvas,
    String text,
    ui.Rect zone,
    double size, {
    bool dim = false,
  }) {
    final ui.Paragraph paragraph = _paragraph(
      text,
      size,
      ui.FontWeight.w600,
      dim ? const ui.Color(0xCCF2F4F8) : const ui.Color(0xFFF2F4F8),
    );
    canvas.drawParagraph(
      paragraph,
      ui.Offset(
        zone.center.dx - paragraph.maxIntrinsicWidth / 2,
        zone.center.dy - paragraph.height / 2,
      ),
    );
  }

  static ui.Paragraph _paragraph(
    String text,
    double size,
    ui.FontWeight weight,
    ui.Color color, {
    bool monospace = false,
  }) {
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: size,
        fontFamily: monospace ? 'Consolas' : 'Microsoft YaHei UI',
        fontWeight: weight,
        textAlign: ui.TextAlign.left,
      ),
    )..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: monospace ? 'Consolas' : 'Microsoft YaHei UI',
        ),
      );
    builder.addText(text);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: 4000.0));
  }

  static double _textWidth(String text, double size) {
    return _paragraph(text, size, ui.FontWeight.w400, const ui.Color(0xFFFFFFFF)).maxIntrinsicWidth;
  }

  static void _text(
    ui.Canvas canvas,
    String text,
    ui.Offset at,
    double size, {
    ui.Color color = const ui.Color(0xFFFFFFFF),
    ui.FontWeight weight = ui.FontWeight.w400,
  }) {
    canvas.drawParagraph(
      _paragraph(text, size, weight, color),
      at,
    );
  }

  static void _textEllipsis(
    ui.Canvas canvas,
    String text,
    ui.Offset at,
    double size,
    double maxWidth, {
    ui.FontWeight weight = ui.FontWeight.w400,
  }) {
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: size,
        fontFamily: 'Microsoft YaHei UI',
        fontWeight: weight,
        maxLines: 1,
        ellipsis: '…',
        textAlign: ui.TextAlign.left,
      ),
    )..pushStyle(
        ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontSize: size,
          fontWeight: weight,
          fontFamily: 'Microsoft YaHei UI',
        ),
      );
    builder.addText(text);
    final ui.Paragraph paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: math.max(1.0, maxWidth)));
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
    required this.title,
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

  final String title;
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
