#!/usr/bin/env python3
"""Review sheets for an app icon change: size ladder + side-by-side comparison.

usage: python3 scripts/icon/preview_icon.py OLD.png NEW.png OUT_DIR
Writes OUT_DIR/comparison.png and OUT_DIR/size-ladder.png. Icons are masked with
an iOS-like continuous-corner shape (superellipse, n=5) and downscaled with
Lanczos, on light and dark home-screen-like grounds.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SIZES = [180, 120, 87, 60, 40]


def font(size):
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default(size=size)


def mask(size, ss=4):
    n = size * ss
    y, x = np.mgrid[0:n, 0:n].astype(np.float64) + 0.5
    u, v = np.abs(2 * x / n - 1), np.abs(2 * y / n - 1)
    m = ((u ** 5 + v ** 5) <= 1).astype(np.uint8) * 255
    return Image.fromarray(m).reduce(ss)


def icon_at(img, size):
    return img.resize((size, size), Image.LANCZOS), mask(size)


def ground(w, h, dark):
    top, bot = ((0x0B, 0x10, 0x18), (0x24, 0x2E, 0x3C)) if dark else ((0xEE, 0xF2, 0xF8), (0xC9, 0xD5, 0xE4))
    t = np.linspace(0, 1, h)[:, None, None]
    arr = np.array(top) * (1 - t) + np.array(bot) * t
    return Image.fromarray(np.ascontiguousarray(np.broadcast_to(arr, (h, w, 3))).astype(np.uint8))


def ladder_block(old, new, dark, gap=28):
    w = 2 * (sum(SIZES) + gap * len(SIZES)) + 3 * gap
    h = max(SIZES) + 3 * gap + 40
    g = ground(w, h, dark)
    d = ImageDraw.Draw(g)
    ink = (235, 240, 245) if dark else (30, 40, 52)
    x = gap
    for label, img in (("1.1.4", old), ("1.1.5", new)):
        d.text((x, 10), label, fill=ink, font=font(20))
        for s in SIZES:
            ic, m = icon_at(img, s)
            y = 40 + gap + (max(SIZES) - s)
            g.paste(ic, (x, y), m)
            d.text((x, y + s + 4), f"{s}", fill=ink, font=font(12))
            x += s + gap
        x += gap
    return g


def main():
    old = Image.open(sys.argv[1]).convert("RGB")
    new = Image.open(sys.argv[2]).convert("RGB")
    out = sys.argv[3]
    os.makedirs(out, exist_ok=True)

    light, dark = ladder_block(old, new, False), ladder_block(old, new, True)

    # Size ladder: the two grounds plus 4x nearest-neighbour zooms of 60 and 40 px.
    zooms = []
    for s in (60, 40):
        for img in (old, new):
            ic, m = icon_at(img, s)
            tile = ground(s, s, True)
            tile.paste(ic, (0, 0), m)
            zooms.append(tile.resize((s * 4, s * 4), Image.NEAREST))
    zw = sum(z.width for z in zooms) + 28 * (len(zooms) + 1)
    zh = 60 * 4 + 90
    zrow = Image.new("RGB", (max(zw, light.width), zh), (24, 28, 34))
    d = ImageDraw.Draw(zrow)
    d.text((28, 12), "4x zoom (nearest): 60 px old, new | 40 px old, new", fill=(230, 235, 240), font=font(20))
    x = 28
    for z in zooms:
        zrow.paste(z, (x, 50))
        x += z.width + 28
    W = max(light.width, zrow.width)
    lad = Image.new("RGB", (W, light.height + dark.height + zrow.height), (24, 28, 34))
    lad.paste(light, (0, 0))
    lad.paste(dark, (0, light.height))
    lad.paste(zrow, (0, light.height + dark.height))
    lad.save(os.path.join(out, "size-ladder.png"), optimize=True)

    # Comparison: 512 px masked icons side by side + 1:1 crops of the card top + ladders.
    big = 512
    pad = 40
    head = Image.new("RGB", (2 * big + 3 * pad, big + 2 * pad + 30), (0x2A, 0x31, 0x3B))
    d = ImageDraw.Draw(head)
    for i, (label, img) in enumerate((("1.1.4 (current)", old), ("1.1.5 (new)", new))):
        ic, m = icon_at(img, big)
        x = pad + i * (big + pad)
        head.paste(ic, (x, pad + 30), m)
        d.text((x, 12), label, fill=(240, 244, 248), font=font(24))
    crop_box = (300, 150, 900, 450)
    cw = crop_box[2] - crop_box[0]
    crops = Image.new("RGB", (2 * cw + 3 * pad, crop_box[3] - crop_box[1] + pad + 30), (0x2A, 0x31, 0x3B))
    d = ImageDraw.Draw(crops)
    for i, (label, img) in enumerate((("1.1.4 card top, 1:1 of 1024", old), ("1.1.5 card top, 1:1 of 1024", new))):
        x = pad + i * (cw + pad)
        crops.paste(img.crop(crop_box), (x, 30))
        d.text((x, 4), label, fill=(240, 244, 248), font=font(20))
    W = max(head.width, crops.width, light.width)
    sheet = Image.new("RGB", (W, head.height + crops.height + light.height + dark.height), (0x2A, 0x31, 0x3B))
    y = 0
    for part in (head, crops, light, dark):
        sheet.paste(part, (0, y))
        y += part.height
    sheet.save(os.path.join(out, "comparison.png"), optimize=True)
    print(os.path.join(out, "comparison.png"))
    print(os.path.join(out, "size-ladder.png"))


if __name__ == "__main__":
    main()
