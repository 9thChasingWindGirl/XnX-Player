"""Render the ASS payload from player_osd.lua to a PNG.

There is no mpv on this machine, so the only way to look at the OSD before
shipping it is to draw it ourselves. This is not a libass replacement: it
handles exactly the tags our script emits (``\\pos``, ``\\an7``, ``\\p1`` paths,
``\\1c``/``\\1a``, ``\\blur``, ``\\fs``/``\\fn``/``\\b``), which is all we need to
answer "does the gradient band?" and "are the badges where I think they are?".

Usage:  python tool/osd_render.py [--bg contrast|photo] [-o out.png]
"""

from __future__ import annotations

import argparse
import math
import re

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1920, 1080

FONTS = {
    'Microsoft YaHei UI': r'C:\Windows\Fonts\msyh.ttc',
    'Consolas': r'C:\Windows\Fonts\consola.ttf',
}

TAG = re.compile(r'\{([^}]*)\}(.*)')
PATH_TOKEN = re.compile(r'([mlb])((?:\s*-?\d+(?:\.\d+)?)+)')


def parse_color(value: str) -> tuple[int, int, int]:
    """ASS colours are &HBBGGRR&."""
    raw = value.strip().strip('&').lstrip('Hh')
    b, g, r = int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16)
    return r, g, b


def parse_tags(tags: str) -> dict:
    out: dict = {'align': 7, 'blur': 0.0, 'alpha': 0, 'color': (255, 255, 255)}

    def grab(pattern: str) -> str | None:
        found = re.search(pattern, tags)
        return found.group(1) if found else None

    # Matched one tag at a time: a single "\\name(args)" split cannot tell
    # `\p1` from `\1a&H79&`, and silently turned drawings into text.
    pos = grab(r'\\pos\(([-\d.,]+)\)')
    if pos:
        x, y = pos.split(',')
        out['pos'] = (float(x), float(y))
    for key, pattern, cast in (
        ('align', r'\\an(\d+)', int),
        ('blur', r'\\blur([\d.]+)', float),
        ('size', r'\\fs([\d.]+)', float),
    ):
        value = grab(pattern)
        if value is not None:
            out[key] = cast(value)
    font = grab(r'\\fn([^\\}]+)')
    if font:
        out['font'] = font
    out['bold'] = re.search(r'\\b1', tags) is not None
    color = grab(r'\\1c&H([0-9A-Fa-f]{6})&')
    if color:
        out['color'] = parse_color(color)
    alpha = grab(r'\\1a&H([0-9A-Fa-f]{2})&')
    if alpha:
        out['alpha'] = int(alpha, 16)
    # Outline: `\bord` width, `\3c` colour, `\3a` alpha. The OSD relies on this
    # for legibility now that the scrim is almost gone, so the preview has to
    # reproduce it or the judgement about contrast is worthless.
    border = grab(r'\\bord([\d.]+)')
    if border:
        out['border'] = float(border)
    border_color = grab(r'\\3c&H([0-9A-Fa-f]{6})&')
    if border_color:
        out['border_color'] = parse_color(border_color)
    border_alpha = grab(r'\\3a&H([0-9A-Fa-f]{2})&')
    if border_alpha:
        out['border_alpha'] = int(border_alpha, 16)
    out['draw'] = grab(r'\\p([1-9])') is not None
    return out


def path_polygon(path: str) -> list[tuple[float, float]]:
    """Flatten an ASS drawing into a point list (beziers are sampled)."""
    points: list[tuple[float, float]] = []
    for cmd, nums in PATH_TOKEN.findall(path):
        values = [float(v) for v in nums.split()]
        if cmd == 'm':
            points.append((values[0], values[1]))
        elif cmd == 'l':
            for i in range(0, len(values), 2):
                points.append((values[i], values[i + 1]))
        elif cmd == 'b':
            for i in range(0, len(values), 6):
                c1x, c1y, c2x, c2y, px, py = values[i:i + 6]
                sx, sy = points[-1]
                for step in range(1, 9):
                    t = step / 8
                    mt = 1 - t
                    points.append((
                        mt ** 3 * sx + 3 * mt ** 2 * t * c1x + 3 * mt * t ** 2 * c2x + t ** 3 * px,
                        mt ** 3 * sy + 3 * mt ** 2 * t * c1y + 3 * mt * t ** 2 * c2y + t ** 3 * py,
                    ))
    return points


def background(kind: str) -> Image.Image:
    img = Image.new('RGB', (W, H), (10, 12, 16))
    draw = ImageDraw.Draw(img)
    if kind == 'contrast':
        # The worst case for a stepped gradient: bright horizontal bands with
        # hard edges, exactly like the train interior in the bug report.
        for i in range(0, H, 90):
            shade = 150 if (i // 90) % 2 == 0 else 40
            draw.rectangle([0, i, W, i + 88], fill=(shade, shade - 8, shade - 16))
        draw.ellipse([520, 180, 1420, 900], fill=(190, 186, 178))
    else:
        for y in range(H):
            v = int(30 + 90 * (y / H))
            draw.line([(0, y), (W, y)], fill=(v, v - 4, v - 8))
        for x in range(0, W, 240):
            draw.rectangle([x, 0, x + 120, H], fill=(70, 66, 60))
    return img


def render(data_path: str, bg_kind: str, out_path: str) -> None:
    canvas = background(bg_kind).convert('RGBA')
    lines = [line for line in open(data_path, encoding='utf-8').read().splitlines() if line.strip()]

    for line in lines:
        match = TAG.match(line)
        if not match:
            continue
        tags, body = match.group(1), match.group(2)
        body = re.sub(r'\{\\p0\}$', '', body)
        info = parse_tags(tags)
        pos = info.get('pos', (0, 0))
        opacity = 255 - info['alpha']
        stroke = int(round(info.get('border', 0)))
        border_alpha = 255 - info.get('border_alpha', 0)

        layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        drawer = ImageDraw.Draw(layer)

        if info.get('draw'):
            # Stroke-only shapes (`\1a&HFF&` + `\bord`) are how every "not
            # delivered yet" badge is drawn. Skipping them on opacity alone
            # made the outline pills invisible in the preview and very nearly
            # got the Lua changed for a bug that did not exist.
            poly = [(x + pos[0], y + pos[1]) for x, y in path_polygon(body)]
            if len(poly) >= 3:
                if opacity > 0:
                    drawer.polygon(poly, fill=(*info['color'], opacity))
                if stroke > 0 and border_alpha > 0:
                    bc = info.get('border_color', (0, 0, 0))
                    drawer.line(poly + [poly[0]], fill=(*bc, border_alpha),
                                width=stroke, joint='curve')
            if info['blur'] > 0 and len(poly) >= 3:
                layer = layer.filter(ImageFilter.GaussianBlur(info['blur'] * 0.5))
        else:
            if opacity <= 0:
                continue
            text = body.replace('\\N', '\n')
            if not text:
                continue
            font_path = FONTS.get(info.get('font', ''), FONTS['Microsoft YaHei UI'])
            size = int(info.get('size', 20))
            font = ImageFont.truetype(font_path, size)
            anchor = {7: 'la', 8: 'ma', 9: 'ra', 5: 'mm', 4: 'lm', 6: 'rm'}.get(info['align'], 'la')
            stroke_fill = None
            if stroke > 0:
                bc = info.get('border_color', (0, 0, 0))
                ba = 255 - info.get('border_alpha', 0)
                stroke_fill = (*bc, ba)
            drawer.text(pos, text, font=font, fill=(*info['color'], opacity), anchor=anchor,
                        stroke_width=stroke, stroke_fill=stroke_fill)

        canvas = Image.alpha_composite(canvas, layer)

    canvas.convert('RGB').save(out_path)
    print('wrote', out_path)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default='_osd_chrome.txt')
    ap.add_argument('--bg', default='contrast', choices=['contrast', 'photo'])
    ap.add_argument('-o', '--out', default='_osd_render.png')
    args = ap.parse_args()
    render(args.data, args.bg, args.out)
