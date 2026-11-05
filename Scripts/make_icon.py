#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Scripts/make_icon.py — a Cortex AI app ikonja.

MIÉRT ÚJ IKON: az előző vékony neonvonalakból állt fekete alapon. 60×60 ponton
(ami a valódi méret a home screenen) a vonalak eltűnnek, és marad egy sötét folt.
Ez a verzió kitöltött formákra épül: egy vastag gyűrű, ami „C" alakban nyílik,
közepén izzó mag. Kicsiben is olvasható, mert nincs benne 40 px-nél vékonyabb elem.

Három változat készül (iOS 18 megjelenések):
  appicon-1024.png        — alap
  appicon-1024-dark.png   — sötét
  appicon-1024-tinted.png — színezhető (grayscale, átlátszó háttérrel)

    python3 Scripts/make_icon.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Resources/Assets.xcassets/AppIcon.appiconset"
S = 4                      # supersampling
N = 1024 * S               # munkavászon
CX = CY = N // 2

# A márka színei (ugyanazok, mint a Theme.swift-ben)
CYAN    = (0x22, 0xD3, 0xEE)
VIOLET  = (0x8B, 0x5C, 0xF6)
MAGENTA = (0xE8, 0x79, 0xF9)
INK     = (0x05, 0x05, 0x06)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def wheel(t: float):
    """0..1 → cián → ibolya → magenta → cián, körbe."""
    t = t % 1.0
    if t < 1 / 3:
        return lerp(CYAN, VIOLET, t * 3)
    if t < 2 / 3:
        return lerp(VIOLET, MAGENTA, (t - 1 / 3) * 3)
    return lerp(MAGENTA, CYAN, (t - 2 / 3) * 3)


def background(dark: bool) -> Image.Image:
    """Átlós gradiens + lágy fény a jel mögött."""
    base = Image.new("RGB", (N, N), INK)
    d = ImageDraw.Draw(base)
    top = (0x14, 0x10, 0x2E) if not dark else (0x0A, 0x08, 0x14)
    bot = (0x05, 0x05, 0x0A) if not dark else (0x02, 0x02, 0x03)
    for y in range(N):
        t = y / N
        for_x = lerp(top, bot, t)
        d.line([(0, y), (N, y)], fill=for_x)

    # radiális fény a mark mögött — ez adja a mélységet
    glow = Image.new("RGB", (N, N), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for r in range(int(N * 0.62), 0, -max(1, N // 220)):
        t = 1 - r / (N * 0.62)
        col = lerp((0, 0, 0), (0x2A, 0x18, 0x5A) if not dark else (0x14, 0x0C, 0x2C), t ** 1.7)
        gd.ellipse([CX - r, CY - r, CX + r, CY + r], fill=col)
    glow = glow.filter(ImageFilter.GaussianBlur(N * 0.05))
    return Image.blend(base, Image.new("RGB", (N, N), (0, 0, 0)), 0.0).point(lambda v: v) if False else \
        Image.eval(base, lambda v: v).convert("RGB") if False else _screen(base, glow)


def _screen(a: Image.Image, b: Image.Image) -> Image.Image:
    from PIL import ImageChops
    inv_a = ImageChops.invert(a)
    inv_b = ImageChops.invert(b)
    return ImageChops.invert(ImageChops.multiply(inv_a, inv_b))


def ring_layer(gap_deg: float = 74.0, tinted: bool = False) -> Image.Image:
    """Vastag gyűrű színgradienssel, „C" nyílással. Átlátszó vászon."""
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    outer = N * 0.335
    width = N * 0.098
    start = gap_deg / 2
    end = 360 - gap_deg / 2

    steps = int((end - start) * 2)          # fél fokonként
    for i in range(steps):
        a0 = start + (end - start) * i / steps
        a1 = start + (end - start) * (i + 1) / steps + 0.35
        col = (235, 235, 240) if tinted else wheel(a0 / 360)
        d.arc([CX - outer, CY - outer, CX + outer, CY + outer],
              a0, a1, fill=col + (255,), width=int(width))

    # lekerekített végek
    for a in (start, end):
        rad = math.radians(a)
        r_mid = outer - width / 2
        x, y = CX + r_mid * math.cos(rad), CY + r_mid * math.sin(rad)
        col = (235, 235, 240) if tinted else wheel(a / 360)
        d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=col + (255,))
    return layer


def core_layer(tinted: bool = False) -> Image.Image:
    """A középső mag: kitöltött kör, belül világosabb."""
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = N * 0.125
    if tinted:
        d.ellipse([CX - r, CY - r, CX + r, CY + r], fill=(255, 255, 255, 255))
        return layer
    for i in range(int(r), 0, -1):
        t = i / r
        col = lerp((255, 255, 255), VIOLET, t ** 0.85)
        d.ellipse([CX - i, CY - i, CX + i, CY + i], fill=col + (255,))
    return layer


def render(dark: bool, tinted: bool) -> Image.Image:
    if tinted:
        canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    else:
        canvas = background(dark).convert("RGBA")

    ring = ring_layer(tinted=tinted)
    core = core_layer(tinted=tinted)

    if not tinted:
        # ragyogás: a jel másolata elmosva, screen-nel ráégetve
        glow = ring.copy()
        glow.alpha_composite(core)
        glow = glow.filter(ImageFilter.GaussianBlur(N * 0.028))
        from PIL import ImageChops
        rgb = Image.alpha_composite(canvas, glow)
        canvas = ImageChops.screen(rgb.convert("RGB"), glow.convert("RGB")).convert("RGBA")
        canvas.putalpha(255)

    canvas.alpha_composite(ring)
    canvas.alpha_composite(core)
    return canvas


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    jobs = [
        ("appicon-1024.png", False, False),
        ("appicon-1024-dark.png", True, False),
        ("appicon-1024-tinted.png", True, True),
    ]
    for name, dark, tinted in jobs:
        img = render(dark, tinted)
        img = img.resize((1024, 1024), Image.LANCZOS)
        path = OUT / name
        img.save(path, optimize=True)
        print(f"{name}: {path.stat().st_size/1024:.0f} kB")

    # előnézet 60 pt-on (a valódi home screen méret)
    small = render(False, False).resize((180, 180), Image.LANCZOS)
    preview = Image.new("RGB", (560, 200), (0x1C, 0x1C, 0x1E))
    preview.paste(small.convert("RGB"), (20, 10))
    s60 = render(False, False).resize((60, 60), Image.LANCZOS)
    preview.paste(s60.convert("RGB"), (230, 70))
    s40 = render(False, False).resize((40, 40), Image.LANCZOS)
    preview.paste(s40.convert("RGB"), (320, 80))
    prev_path = Path("/home/user/web/brand/icon-preview.png")
    prev_path.parent.mkdir(parents=True, exist_ok=True)
    preview.save(prev_path)
    print("előnézet:", prev_path)


if __name__ == "__main__":
    main()
