import 'dart:math' as math;
import 'dart:ui' as ui;

/// One clickable region of the independent chrome.
class OsdZone {
  const OsdZone(this.id, this.rect);

  /// `seek`, `play`, `back10`, `fwd10`, or `menu:<id>`.
  final String id;
  final ui.Rect rect;
}

/// How truthfully a format badge can be claimed.
///
/// Mirrors the Lua stage: `fact` is a property of the file (resolution, codec,
/// fps) and always reads the same; `lit` means the output chain really carries
/// the format — a tinted plate and a bright ring; `dim` means the file has it
/// but the chain is tone-mapping or decoding it away, so only a faint ring is
/// drawn. Never claim a format the player is not delivering.
enum OsdBadgeTier { fact, lit, dim }

/// One format badge with its own accent and truthfulness tier.
class OsdBadge {
  const OsdBadge(this.label, this.color, this.tier);

  final String label;
  final ui.Color color;
  final OsdBadgeTier tier;

  /// Accents from the Lua stage, kept in sync so both engines look identical.
  static const ui.Color hdrGold = ui.Color(0xFFFABE3C);
  static const ui.Color dvPurple = ui.Color(0xFFA078FF);
  static const ui.Color hlgCyan = ui.Color(0xFF50DCDC);
  static const ui.Color dtsAmber = ui.Color(0xFFFF963F);
  static const ui.Color dolbyBlue = ui.Color(0xFF2E8BFF);
  static const ui.Color plainWhite = ui.Color(0xFFFFFFFF);
}

/// One row of the popup menu, as Lua reports it.
///
/// `act` never crosses the boundary — it is a Lua closure. Dart draws the row
/// and forwards the click; Lua still decides what the row does.
class OsdMenuRow {
  const OsdMenuRow({
    required this.kind,
    required this.label,
    this.value = '',
    this.active = false,
  });

  /// `item`, `adjust` or `header`.
  final String kind;
  final String label;

  /// Right-aligned value (`开启`, `1.5x`, `简体中文`). Empty when absent.
  final String value;

  /// The row is the currently applied choice; drawn with a dot.
  final bool active;

  bool get isHeader => kind == 'header';
  bool get isAdjust => kind == 'adjust';
}

/// The popup menu state: title, selected row, rows. Index is 0-based here and
/// converted back to Lua's 1-based indexing when a command is sent.
class OsdMenu {
  const OsdMenu({
    required this.title,
    required this.index,
    required this.rows,
  });

  final String title;
  final int index;
  final List<OsdMenuRow> rows;

  int get selected => rows.isEmpty ? 0 : index.clamp(0, rows.length - 1).toInt();
}

/// One chapter mark: a start time and the name mpv reports for it.
class OsdChapter {
  const OsdChapter(this.time, this.title);

  /// Seconds from the start of the file.
  final double time;
  final String title;
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

  /// Menu geometry, identical to the Lua stage's so the panel lands where the
  /// old one did: right-aligned above the transport, 520 design units wide.
  static const double menuW = 520;
  static const double menuRowH = 60;
  static const double menuHeaderH = 40;
  static const double menuBottom = 862;
  static const double menuBudget = 620;

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

  /// Sizes (type, glyphs, control height, radii) use one scale, the horizontal
  /// one. The old vertical scale squeezed every control into a thin strip when
  /// the window was stretched wide-but-short: sy fell to a fraction of sx
  /// while text kept a legibility floor, so labels overflowed their buttons.
  /// On a 16:9 stage both scales are equal, so this changes nothing there.
  static double _sy(ui.Size size) => _sx(size);

  /// Y for the bottom band, anchored to the window's bottom edge.
  ///
  /// Design coordinates below are measured from the top of a 1920x1080 frame,
  /// but the chrome lives in the bottom 380 of it. Anchoring that band to the
  /// bottom keeps seek/transport/hint together at any window aspect ratio;
  /// multiplying by a height-derived scale pushed them into each other.
  /// Algebraically identical to `v * sy` when the window is 16:9.
  static double _bottom(ui.Size size, double v) =>
      size.height - (designH - v) * _sx(size);

  /// The seek line's rectangle — one source of truth for paint, hit testing and
  /// pointer-to-fraction conversion.
  static ui.Rect seekTrack(ui.Size size) {
    final double sx = _sx(size);
    final double center = _bottom(size, barY);
    final double left = safeX * sx;
    final double right = math.max(left + 40, size.width - safeX * sx);
    return ui.Rect.fromLTRB(left, center - 6 * sx, right, center + 6 * sx);
  }

  static double fractionAt(ui.Size size, double x) {
    final ui.Rect track = seekTrack(size);
    return ((x - track.left) / track.width).clamp(0.0, 1.0);
  }

  /// The seek strip, kept for the geometry tests and the wheel zone.
  static List<ui.Rect> hotZones(ui.Size size) {
    final ui.Rect track = seekTrack(size);
    final double half = seekHitHeight * _sx(size) / 2;
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
  static List<OsdZone> zones(ui.Size size, {OsdMenu? menu}) {
    final double sx = _sx(size);
    final double sy = _sy(size);
    final List<OsdZone> out = <OsdZone>[];
    final ui.Rect track = seekTrack(size);
    final double seekCenter = _bottom(size, barY);
    out.add(OsdZone(
      'seek',
      ui.Rect.fromLTRB(
        track.left,
        seekCenter - 18 * sy,
        track.right,
        seekCenter + 18 * sy,
      ),
    ));

    final double top = _bottom(size, ctrlY);
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
    if (menu != null) {
      out.addAll(menuZones(size, menu));
    }
    return out;
  }

  /// Rows visible around the selection, as an inclusive index range.
  ///
  /// A 40-chapter file must not push the panel off the top of the screen, so
  /// the list is windowed around the cursor exactly as the Lua stage did.
  static (int, int) menuWindow(OsdMenu menu) {
    double rowH(OsdMenuRow row) => row.isHeader ? menuHeaderH : menuRowH;
    final int sel = menu.selected;
    int first = sel;
    int last = sel;
    double used = rowH(menu.rows[sel]);
    for (int i = sel - 1; i >= 0; i--) {
      final double h = rowH(menu.rows[i]);
      if (used + h > menuBudget) {
        break;
      }
      used += h;
      first = i;
    }
    for (int j = sel + 1; j < menu.rows.length; j++) {
      final double h = rowH(menu.rows[j]);
      if (used + h > menuBudget) {
        break;
      }
      used += h;
      last = j;
    }
    return (first, last);
  }

  /// The panel rectangle: right-aligned, sitting above the transport row.
  static ui.Rect menuPanel(ui.Size size, OsdMenu menu) {
    if (menu.rows.isEmpty) {
      return ui.Rect.zero;
    }
    final double sx = _sx(size);
    final double sy = _sy(size);
    final (int first, int last) = menuWindow(menu);
    double used = 0;
    for (int i = first; i <= last; i++) {
      used += menu.rows[i].isHeader ? menuHeaderH : menuRowH;
    }
    final double height = (62 + used + 20) * sy;
    return ui.Rect.fromLTWH(
      size.width - safeX * sx - menuW * sx,
      _bottom(size, menuBottom) - height,
      menuW * sx,
      height,
    );
  }

  /// Clickable row rectangles, keyed `menurow:<index>` with a 0-based index.
  static List<OsdZone> menuZones(ui.Size size, OsdMenu menu) {
    if (menu.rows.isEmpty) {
      return const <OsdZone>[];
    }
    final double sx = _sx(size);
    final double sy = _sy(size);
    final ui.Rect panel = menuPanel(size, menu);
    final (int first, int last) = menuWindow(menu);
    final List<OsdZone> out = <OsdZone>[];
    double y = panel.top + 62 * sy;
    for (int i = first; i <= last; i++) {
      final OsdMenuRow row = menu.rows[i];
      final double h = (row.isHeader ? menuHeaderH : menuRowH) * sy;
      if (!row.isHeader) {
        out.add(OsdZone(
          'menurow:$i',
          ui.Rect.fromLTWH(panel.left + 12 * sx, y, panel.width - 24 * sx, h),
        ));
      }
      y += h;
    }
    return out;
  }

  static void paint(ui.Canvas canvas, ui.Size size, OsdChromeModel model) {
    final double sx = _sx(size);
    final double sy = _sy(size);
    double x(double v) => v * sx;
    double y(double v) => v * sy;
    double b(double v) => _bottom(size, v);
    // 12 px floor keeps a small badge legible. The scale is now the horizontal
    // one, so a short-wide window no longer shrinks type below its controls.
    double font(double v) => math.max(v * sy, 12);

    // Scrim: the chrome must read over a bright frame. Never dim more than the
    // lower half of a squeezed window, or the picture itself disappears.
    final double scrimTop = math.max(b(700), size.height * 0.5);
    final ui.Paint scrim = ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(0, scrimTop),
        ui.Offset(0, size.height),
        const <ui.Color>[
          ui.Color(0x00000000),
          ui.Color(0x8C05060C),
          ui.Color(0xC805060C),
        ],
        const <double>[0, 0.45, 1],
      );
    canvas.drawRect(
        ui.Rect.fromLTRB(0, scrimTop, size.width, size.height), scrim);

    if (model.title.isNotEmpty) {
      _textEllipsis(
        canvas,
        model.title,
        ui.Offset(x(safeX), b(titleY)),
        font(40),
        size.width - x(safeX) * 2,
        weight: ui.FontWeight.w600,
      );
    }

    // Format badges. A `lit` badge really is being delivered by the output
    // chain and gets a tinted plate + bright ring; `dim` means the file has the
    // format but the chain tone-maps or decodes it away, so only a faint ring
    // is drawn. The distinction is what "是否点亮" asks for — an HDR file on
    // an SDR desktop must not look like a live HDR output.
    double bx = x(safeX);
    final double badgeInk = font(16);
    // The plate has to grow with the floored text, and the text is centred in
    // it: a fixed 28-unit box with a 12 px label would clip the descenders.
    final double badgeH = math.max(28 * sy, badgeInk + 6);
    for (final String label in model.badges) {
      final OsdBadge badge = model.badgeFor(label);
      final double width = _textWidth(label, badgeInk) + x(22);
      final ui.Rect box = ui.Rect.fromLTWH(bx, b(metaY), width, badgeH);
      final ui.RRect rounded = ui.RRect.fromRectAndRadius(box, ui.Radius.circular(x(6)));
      switch (badge.tier) {
        case OsdBadgeTier.lit:
          canvas.drawRRect(
            rounded,
            ui.Paint()..color = badge.color.withValues(alpha: 0.25),
          );
          canvas.drawRRect(
            rounded,
            ui.Paint()
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = x(1.5)
              ..color = badge.color.withValues(alpha: 0.85),
          );
          break;
        case OsdBadgeTier.dim:
          canvas.drawRRect(
            rounded,
            ui.Paint()
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = x(1)
              ..color = const ui.Color(0x8CE6E9F2),
          );
          break;
        case OsdBadgeTier.fact:
          canvas.drawRRect(
            rounded,
            ui.Paint()..color = const ui.Color(0x14FFFFFF),
          );
          break;
      }
      final ui.Color ink = switch (badge.tier) {
        OsdBadgeTier.lit => badge.color,
        OsdBadgeTier.dim => const ui.Color(0x9EE6E9F2),
        OsdBadgeTier.fact => const ui.Color(0xE6FFFFFF),
      };
      _text(canvas, label, ui.Offset(bx + x(11), box.top + (badgeH - badgeInk) / 2),
          badgeInk, color: ink);
      bx += width + x(8);
    }

    // Seek line.
    final ui.Rect track = seekTrack(size);
    final double progress =
        model.duration > 0 ? (model.position / model.duration).clamp(0.0, 1.0) : 0;
    final double knob = model.scrubbing ?? progress;
    // Demuxed lead-in, the way Kodi shows what a stream has buffered. A local
    // file reports nothing useful here, so it stays at 0 and draws nothing.
    final double bufferedFraction = model.duration > 0
        ? (model.buffered / model.duration).clamp(0.0, 1.0).toDouble()
        : 0;
    // The knob is a shape, not text: it keeps its own scale so the 12 px font
    // floor does not turn a 4.5 px dot into a 24 px disc.
    _seekLine(canvas, track, knob, model.accent,
        hover: model.hoverSeek || model.scrubbing != null,
        radius: math.max(8 * sy, 5),
        buffered: math.max(bufferedFraction, progress),
        marks: <double>[
          if (model.duration > 0)
            for (final OsdChapter chapter in model.chapters)
              (chapter.time / model.duration).clamp(0.0, 1.0).toDouble(),
        ]);

    // Dragging the bar answers with the time it is dragging to — the only
    // readout that makes a long seek predictable. The chapter name goes with
    // it, the way Kodi labels the chapter being scrubbed into.
    if (model.scrubbing != null) {
      final double target = model.scrubbing! * model.duration;
      final OsdChapter? chapter = model.chapterAt(target);
      final String name =
          chapter == null ? '' : '${_clip(chapter.title, 14)}   ';
      _scrubBubble(canvas, track, knob, '$name${_clock(target)}', font(18));
    }

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
          // Centre on the text's own height rather than a design-unit offset:
          // the 12 px floor makes the two disagree in a small window.
          canvas.drawParagraph(time, ui.Offset(timeX, zone.rect.center.dy - font(21) / 2));
          break;
        default:
          if (zone.id.startsWith('menu:')) {
            final String label = menuLabels[zone.id.substring(5)] ?? '';
            _centeredText(canvas, label, zone.rect, font(20), dim: true);
          }
          break;
      }
    }

    _text(canvas, hint, ui.Offset(x(safeX), b(hintY)), font(16),
        color: const ui.Color(0x8AFFFFFF));

    // Above the pause badge (y 500) so the two never share a line.
    final double? volume = model.volumeHint;
    if (volume != null) {
      _volumeBar(canvas, size, volume,
          muted: model.muted, ink: font(18), sx: sx, sy: sy);
    }

    if (model.paused) {
      // Centred on the picture, like the volume readout — a bottom-anchored
      // design Y would land above the top edge in a short window.
      _centeredText(
        canvas,
        '已暂停',
        ui.Rect.fromCenter(
          center: ui.Offset(size.width / 2, size.height * 0.42),
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

    // The menu is the topmost surface: it is modal in intent even though the
    // transport stays visible behind it.
    final OsdMenu? menu = model.menu;
    if (menu != null) {
      _paintMenu(canvas, size, menu, sx, sy, model.menuHover);
    }
  }

  /// Draws the popup panel. Geometry comes from [menuPanel]/[menuZones], so the
  /// rows painted here are the rows that take the click.
  static void _paintMenu(ui.Canvas canvas, ui.Size size, OsdMenu menu,
      double sx, double sy, int? hoverRow) {
    if (menu.rows.isEmpty) {
      return;
    }
    double x(double v) => v * sx;
    double y(double v) => v * sy;
    double font(double v) =>
        math.max(v * sy, math.min(v * sx, 20));

    final ui.Rect panel = menuPanel(size, menu);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(panel, ui.Radius.circular(x(18))),
      ui.Paint()..color = const ui.Color(0xF205060C),
    );
    canvas.drawLine(
      ui.Offset(panel.left + x(24), panel.top + y(46)),
      ui.Offset(panel.right - x(24), panel.top + y(46)),
      ui.Paint()
        ..color = const ui.Color(0x1EFFFFFF)
        ..strokeWidth = math.max(sy, 1),
    );
    _text(canvas, menu.title, ui.Offset(panel.left + x(28), panel.top + y(16)),
        font(22), color: const ui.Color(0xFF8C8C8C), weight: ui.FontWeight.w600);

    int count = 0;
    for (final OsdMenuRow row in menu.rows) {
      if (!row.isHeader) {
        count++;
      }
    }
    final ui.Paragraph marker = _paragraph(
        '$count  项', font(18), ui.FontWeight.w400, const ui.Color(0xFF8C8C8C));
    canvas.drawParagraph(
      marker,
      ui.Offset(
          panel.right - x(28) - marker.maxIntrinsicWidth, panel.top + y(18)),
    );

    final (int first, int last) = menuWindow(menu);
    double rowTop = panel.top + y(62);
    for (int i = first; i <= last; i++) {
      final OsdMenuRow row = menu.rows[i];
      final double h = y(row.isHeader ? menuHeaderH : menuRowH);
      if (row.isHeader) {
        _text(canvas, row.label, ui.Offset(panel.left + x(28), rowTop + y(10)),
            font(17),
            color: const ui.Color(0xFF8C8C8C), weight: ui.FontWeight.w600);
        rowTop += h;
        continue;
      }
      final bool selected = i == menu.selected;
      if (selected) {
        // Same language as the Lua panel: a washed accent plate plus a spine,
        // never a solid white bar (that was the jarring part).
        final ui.RRect plate = ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(
              panel.left + x(12), rowTop + y(4), panel.width - x(24), h - y(8)),
          ui.Radius.circular(x(12)),
        );
        canvas.drawRRect(
          plate,
          ui.Paint()..color = OsdBadge.hdrGold.withValues(alpha: 0.18),
        );
        canvas.drawRRect(
          plate,
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = math.max(sx, 1)
            ..color = OsdBadge.hdrGold.withValues(alpha: 0.55),
        );
        canvas.drawRect(
          ui.Rect.fromLTWH(
              panel.left + x(12), rowTop + y(10), x(3.5), h - y(20)),
          ui.Paint()..color = OsdBadge.hdrGold.withValues(alpha: 0.9),
        );
      } else if (i == hoverRow) {
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(panel.left + x(12), rowTop + y(4),
                panel.width - x(24), h - y(8)),
            ui.Radius.circular(x(12)),
          ),
          ui.Paint()..color = const ui.Color(0x14FFFFFF),
        );
      }
      double tx = panel.left + x(28);
      if (row.active && !selected) {
        canvas.drawCircle(
          ui.Offset(panel.left + x(27), rowTop + h / 2),
          math.max(sy * 3, 2.5),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
        tx = panel.left + x(42);
      }
      _text(canvas, _clip(row.label, 24), ui.Offset(tx, rowTop + (h - font(22)) / 2),
          font(22), color: const ui.Color(0xFFF2F4F8));
      if (row.value.isNotEmpty) {
        final ui.Paragraph value = _paragraph(
          row.value,
          font(20),
          ui.FontWeight.w400,
          selected ? const ui.Color(0xFFBEBEBE) : const ui.Color(0xFF8C8C8C),
        );
        canvas.drawParagraph(
          value,
          ui.Offset(
            panel.right - x(28) - value.maxIntrinsicWidth,
            rowTop + (h - font(20)) / 2,
          ),
        );
      }
      rowTop += h;
    }
  }

  static void _seekLine(
    ui.Canvas canvas,
    ui.Rect track,
    double progress,
    ui.Color accent, {
    required bool hover,
    required double radius,
    double buffered = 0,
    List<double> marks = const <double>[],
  }) {
    final double height = track.height / 2;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(track, ui.Radius.circular(height)),
      ui.Paint()..color = const ui.Color(0x2EFFFFFF),
    );
    // Buffered lead-in sits between the empty track and the played fill: light
    // enough not to compete with the accent, bright enough to read as "ready".
    if (buffered > 0.001) {
      final ui.Rect lead = ui.Rect.fromLTRB(
        track.left,
        track.top,
        track.left + track.width * math.min(buffered, 1.0),
        track.bottom,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(lead, ui.Radius.circular(height)),
        ui.Paint()..color = const ui.Color(0x59FFFFFF),
      );
    }
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
    // Chapter marks sit on top of the fill: they are boundaries, not progress,
    // so they must stay readable whatever has been played.
    for (final double mark in marks) {
      if (mark <= 0.001 || mark >= 0.999) {
        continue;
      }
      final double cx = track.left + track.width * mark;
      canvas.drawLine(
        ui.Offset(cx, track.top - 3),
        ui.Offset(cx, track.bottom + 3),
        ui.Paint()
          ..color = const ui.Color(0xE6FFFFFF)
          ..strokeWidth = math.max(track.height * 0.26, 1),
      );
    }
    canvas.drawCircle(
      ui.Offset(track.left + track.width * progress, track.center.dy),
      hover ? radius * 1.6 : radius,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  }

  /// A time tag above the knob while the bar is being dragged.
  ///
  /// Kodi answers a scrub with the target time; without it a long seek is a
  /// guess until the picture catches up.
  static void _scrubBubble(
      ui.Canvas canvas, ui.Rect track, double fraction, String label, double ink) {
    final double w = _textWidth(label, ink) + 24;
    final double h = ink + 12;
    final double wanted = track.left + track.width * fraction - w / 2;
    final double left =
        wanted.clamp(track.left, math.max(track.left, track.right - w)).toDouble();
    final ui.Rect box = ui.Rect.fromLTWH(left, track.top - h - 10, w, h);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(box, ui.Radius.circular(h / 2)),
      ui.Paint()..color = const ui.Color(0xE605060C),
    );
    _text(canvas, label, ui.Offset(box.left + 12, box.top + 6), ink,
        color: const ui.Color(0xFFFFFFFF));
  }

  /// The volume readout: speaker, level, percentage.
  ///
  /// This is the one piece of state the chrome always carried but never showed.
  /// Kodi answers every volume key with this bar, which is why a change there
  /// never feels like it went nowhere.
  static void _volumeBar(
    ui.Canvas canvas,
    ui.Size size,
    double value, {
    required bool muted,
    required double ink,
    required double sx,
    required double sy,
  }) {
    double x(double v) => v * sx;
    double y(double v) => v * sy;
    final double h = math.max(y(56), 40);
    // The volume readout is centred on the picture, not part of the bottom
    // band: anchoring it would send it off-screen in a short window.
    final ui.Rect box = ui.Rect.fromCenter(
      center: ui.Offset(size.width / 2, size.height * 0.5),
      width: x(420),
      height: h,
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(box, ui.Radius.circular(h / 2)),
      ui.Paint()..color = const ui.Color(0xD905060C),
    );

    final ui.Offset c = ui.Offset(box.left + x(34), box.center.dy);
    final double icon = math.max(y(22), 15);
    final ui.Paint body = ui.Paint()..color = const ui.Color(0xFFF2F4F8);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: ui.Offset(c.dx - icon * 0.26, c.dy),
          width: icon * 0.32,
          height: icon * 0.42,
        ),
        ui.Radius.circular(icon * 0.08),
      ),
      body,
    );
    canvas.drawPath(
      ui.Path()
        ..moveTo(c.dx - icon * 0.12, c.dy - icon * 0.2)
        ..lineTo(c.dx + icon * 0.24, c.dy - icon * 0.46)
        ..lineTo(c.dx + icon * 0.24, c.dy + icon * 0.46)
        ..lineTo(c.dx - icon * 0.12, c.dy + icon * 0.2)
        ..close(),
      body,
    );
    if (muted) {
      canvas.drawLine(
        ui.Offset(c.dx - icon * 0.08, c.dy + icon * 0.12),
        ui.Offset(c.dx + icon * 0.46, c.dy - icon * 0.46),
        ui.Paint()
          ..color = const ui.Color(0xFFF05A5A)
          ..strokeWidth = math.max(sy * 2, 2)
          ..strokeCap = ui.StrokeCap.round,
      );
    }

    final double barH = math.max(y(8), 5);
    final double left = box.left + x(70);
    final double right = box.right - x(86);
    final ui.Rect track = ui.Rect.fromLTRB(
        left, box.center.dy - barH / 2, right, box.center.dy + barH / 2);
    final double radius = barH / 2;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(track, ui.Radius.circular(radius)),
      ui.Paint()..color = const ui.Color(0x2EFFFFFF),
    );
    final double fraction = value.clamp(0.0, 1.0).toDouble();
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTRB(left, track.top, left + track.width * fraction, track.bottom),
        ui.Radius.circular(radius),
      ),
      ui.Paint()
        ..color = muted ? const ui.Color(0xFF8C8C94) : const ui.Color(0xFFF2F4F8),
    );

    final String label = muted ? '静音' : '${(fraction * 100).round()}%';
    _text(canvas, label, ui.Offset(right + x(14), box.center.dy - ink / 2), ink,
        color: const ui.Color(0xFFC8CDD6));
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

  /// Truncates a chapter title so a long scraped name cannot push the time out
  /// of the bubble.
  static String _clip(String text, int max) {
    return text.length <= max ? text : '${text.substring(0, max)}…';
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
    this.badgeStyles = const <String, OsdBadge>{},
    this.scrubbing,
    this.hoverSeek = false,
    this.toast,
    this.volumeHint,
    this.buffered = 0,
    this.chapters = const <OsdChapter>[],
    this.menu,
    this.menuHover,
  });

  final String title;
  final double position;
  final double duration;
  final bool paused;
  final double volume;
  final bool muted;
  final List<String> badges;
  final ui.Color accent;

  /// 0..1 while the volume bar is on screen, null when it is not.
  ///
  /// Kodi answers every volume key with a bar instead of moving a number
  /// somewhere; the chrome otherwise has no way to say "this got quieter".
  final double? volumeHint;

  /// Seconds already demuxed, drawn as a lighter lead-in on the seek line.
  /// Zero means "unknown or local file" and draws nothing.
  final double buffered;

  /// Chapter marks from `chapter-list`, in file order.
  final List<OsdChapter> chapters;

  /// The popup menu currently open, or null. Owned by Lua, drawn here.
  final OsdMenu? menu;

  /// Row under the pointer, 0-based. Purely local hover feedback: it must not
  /// move Lua's selection, or a mouse drifting across the panel would re-run
  /// the arrow-key logic.
  final int? menuHover;

  /// The chapter a position falls in, or null before the first mark.
  ///
  /// A file often opens a little before chapter 1, so "no chapter yet" is a
  /// real answer and must not borrow the first title.
  OsdChapter? chapterAt(double seconds) {
    OsdChapter? found;
    for (final OsdChapter chapter in chapters) {
      if (chapter.time <= seconds) {
        found = chapter;
      } else {
        break;
      }
    }
    return found;
  }

  /// Which labels carry an accent and a truthfulness tier. Labels absent from
  /// this map fall back to a neutral `fact` badge, so callers that only supply
  /// plain strings (tests, the minimal fallback) keep their old appearance.
  final Map<String, OsdBadge> badgeStyles;

  OsdBadge badgeFor(String label) =>
      badgeStyles[label] ?? OsdBadge(label, OsdBadge.plainWhite, OsdBadgeTier.fact);

  /// 0..1 while the pointer is dragging the seek bar; null otherwise.
  final double? scrubbing;

  /// Whether the pointer sits on the seek strip — a slightly larger knob.
  final bool hoverSeek;
  final String? toast;
}
