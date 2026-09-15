#!/usr/bin/env python3
"""EconByte app icon generator (1.1.5).

Rebuilds EconByte/Assets.xcassets/AppIcon.appiconset/icon-1024.png from vectors,
so the icon stays crisp instead of being resampled again:

* Artwork geometry is the design master `vault/design/econbyte/icon/icon-v2.svg`
  (Dudley-Development repo), transcribed below 1:1: tide back card at -12deg
  with ghost bars, white front card with teal stripe, border, three amber bars,
  the dot on the tallest bar, and the card's feDropShadow.
* The 1.1.4 icon (commit 20fe218) was that SVG render zoomed as a bitmap. The
  zoom was measured from its bar edges: icon_px = 1.3474 * svg + (-100.96, -182.0).
  The background (ocean fill, glow, vignette = the "glass edge") is drawn in
  exactly that frame, so it is unchanged; its pixels match 1.1.4 within +-1
  level (checked by --check-against).
* The artwork (both cards, bars, dot, shadow) is scaled a further ART_SCALE
  about its own bounding-box centre (Owner order 2026-09-15: "slightly
  increase the size of the graphics").
* The card's old plain "EconByte" text is gone (the card is redrawn, so nothing
  of it can ghost). In its place is the in-app wordmark rendered by the app's
  own SwiftUI code (EconByte/Theme/EconWordmark.swift via render_wordmark.swift),
  with "Econ" in EconBrand.navy (the card is white) and "Byte" + swoosh in the
  in-app gold.
* Output: 1024x1024 RGB PNG, no alpha, sRGB ICC profile.

usage: python3 scripts/icon/build_icon.py [--out PATH] [--check-against OLD.png]
Needs: macOS with swiftc (SwiftUI), python3 with numpy, scipy, Pillow.
"""

import argparse
import io
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageCms, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
ICON = os.path.join(REPO, "EconByte/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

N = 1024          # output size
SS = 8            # supersampling for shape coverage
WM_SS = 4         # supersampling for the wordmark render

# 1.1.4 frame (bitmap zoom of the SVG render, measured from the bar edges)
BG_S, BG_TX, BG_TY = 1.3474, -100.96, -182.0
ART_SCALE = 1.10  # Owner order 2026-09-15

# Chart (baseline, bars, dot) moved down inside the card, SVG units, to give the
# larger wordmark air: the card had 58 units under the baseline and 114 above the
# tallest bar.
CHART_DY_SVG = 14.0

# Wordmark on the card, in SVG units (card interior is x 349..707, the stripe ends
# at y 286, the dot on the tallest bar starts at y 374 + CHART_DY_SVG). Its ink
# (letters + swoosh) is centred between those two, horizontally on the card.
WM_FONT_SVG = 46.0      # font size
WM_ECON = "navy"        # EconBrand.navy
WM_SWOOSH_BOOST = 0.025 # extra swoosh stroke, fraction of font size (small-size legibility)
CARD_CENTER_X_SVG = 528.0
STRIPE_BOTTOM_SVG = 286.0
DOT_TOP_SVG = 374.0


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)


# ---------------------------------------------------------------- geometry
def mat_translate(tx, ty):
    return np.array([[1, 0, tx], [0, 1, ty], [0, 0, 1]], dtype=np.float64)


def mat_scale(s):
    return np.array([[s, 0, 0], [0, s, 0], [0, 0, 1]], dtype=np.float64)


def mat_rotate(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def apply(m, pts):
    p = np.asarray(pts, dtype=np.float64)
    return p @ m[:2, :2].T + m[:2, 2]


def rrect(x, y, w, h, rx, ry=None, seg=48):
    """SVG <rect> outline: ry defaults to rx, both clamped to half the side."""
    if ry is None:
        ry = rx
    rx, ry = min(rx, w / 2), min(ry, h / 2)
    if rx <= 0 or ry <= 0:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    pts = []
    for cx, cy, a0 in ((x + w - rx, y + ry, -90), (x + w - rx, y + h - ry, 0),
                       (x + rx, y + h - ry, 90), (x + rx, y + ry, 180)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    return pts


def circle(cx, cy, r, seg=256):
    return [(cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg))
            for i in range(seg)]


def coverage(*layers):
    """layers: (points_in_icon_px, fill 255|0) drawn in order at SS, box-reduced."""
    img = Image.new("L", (N * SS, N * SS), 0)
    d = ImageDraw.Draw(img)
    for pts, fill in layers:
        d.polygon([(px * SS, py * SS) for px, py in pts], fill=fill)
    return np.asarray(img.reduce(SS), dtype=np.float64) / 255.0


def coverage_intersect(pts_a, pts_b):
    a = Image.new("L", (N * SS, N * SS), 0)
    ImageDraw.Draw(a).polygon([(px * SS, py * SS) for px, py in pts_a], fill=255)
    b = Image.new("L", (N * SS, N * SS), 0)
    ImageDraw.Draw(b).polygon([(px * SS, py * SS) for px, py in pts_b], fill=255)
    a = Image.fromarray(np.minimum(np.asarray(a), np.asarray(b)))
    return np.asarray(a.reduce(SS), dtype=np.float64) / 255.0


# ---------------------------------------------------------------- paint helpers
class Layer:
    """Premultiplied RGBA layer at N x N."""

    def __init__(self):
        self.p = np.zeros((N, N, 3))
        self.a = np.zeros((N, N))

    def paint(self, cov, color, opacity=1.0):
        a = cov * opacity
        col = color if np.ndim(color) == 3 else np.broadcast_to(color, (N, N, 3))
        self.p = col * a[..., None] + self.p * (1 - a[..., None])
        self.a = a + self.a * (1 - a)


def over(dst_rgb, layer):
    return layer.p + dst_rgb * (1 - layer.a[..., None])


def vertical_gradient(m, top, height, stops):
    """SVG linearGradient x1=0 y1=0 x2=0 y2=1 on an unrotated rect (objectBoundingBox)."""
    ys = np.arange(N) + 0.5
    sy = (ys - m[1, 2]) / m[1, 1]
    t = np.clip((sy - top) / height, 0, 1)
    offs = [s[0] for s in stops]
    cols = np.stack([hexc(s[1]) for s in stops])
    rgb = np.stack([np.interp(t, offs, cols[:, k]) for k in range(3)], axis=-1)  # (N,3)
    return np.broadcast_to(rgb[:, None, :], (N, N, 3))


def radial(m_inv_scale, m_inv_tx, m_inv_ty, cx, cy, r, stops):
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64) + 0.5
    sx, sy = (xx - m_inv_tx) / m_inv_scale, (yy - m_inv_ty) / m_inv_scale
    t = np.sqrt((sx - cx) ** 2 + (sy - cy) ** 2) / r
    offs = [s[0] for s in stops]
    t = np.clip(t, offs[0], offs[-1])
    cols = np.stack([hexc(s[1]) for s in stops])
    rgb = np.stack([np.interp(t, offs, cols[:, k]) for k in range(3)], axis=-1)
    op = np.interp(t, offs, [s[2] for s in stops])
    return rgb, op


# ---------------------------------------------------------------- wordmark
def render_wordmark(font_px):
    src = [os.path.join(REPO, "EconByte/Theme/EconWordmark.swift"), os.path.join(HERE, "render_wordmark.swift")]
    with tempfile.TemporaryDirectory() as tmp:
        exe = os.path.join(tmp, "render_wordmark")
        subprocess.run(["swiftc", "-O", "-parse-as-library", "-module-cache-path", os.path.join(tmp, "mc"),
                        *src, "-o", exe], check=True)
        out = os.path.join(tmp, "wordmark.png")
        meta = subprocess.run([exe, out, f"{font_px:.4f}", WM_ECON, f"{WM_SWOOSH_BOOST}"],
                              check=True, capture_output=True, text=True).stdout
        img = Image.open(out).convert("RGBA")
        img.load()
    return img, json.loads(meta)


def place_wordmark(layer, m_card):
    s = m_card[0, 0]                       # icon px per SVG unit on the card
    font_px = WM_FONT_SVG * s * WM_SS
    img, meta = render_wordmark(font_px)
    rgba = np.asarray(img, dtype=np.float64) / 255.0
    w, h = meta["width"], meta["height"]
    alpha = rgba[..., 3]
    cols = np.where(alpha.max(axis=0) > 0.02)[0]
    ink_l, ink_r = cols[0], cols[-1] + 1
    # Optical centre: halfway between the letters' centre (layout box minus the
    # swoosh's trailing room, 0.38 x font size in EconWordmark) and the ink centre.
    letters_c = (w - 0.38 * font_px) / 2
    ink_c = (ink_l + ink_r) / 2
    cx_local = (letters_c + ink_c) / 2
    # Target in icon px, then snap to the 1/WM_SS grid.
    ink_rows = np.where(alpha.max(axis=1) > 0.02)[0]
    cy_local = (ink_rows[0] + ink_rows[-1] + 1) / 2
    band_mid = (STRIPE_BOTTOM_SVG + DOT_TOP_SVG + CHART_DY_SVG) / 2
    tx, ty = apply(m_card, [(CARD_CENTER_X_SVG, band_mid)])[0]
    ox = int(round((tx - cx_local / WM_SS) * WM_SS))
    oy = int(round((ty - cy_local / WM_SS) * WM_SS))
    bx, by = (ox // WM_SS) - 1, (oy // WM_SS) - 1
    cw, ch = (w // WM_SS) + 4, (h // WM_SS) + 4
    canvas = np.zeros((ch * WM_SS, cw * WM_SS, 4))
    px0, py0 = ox - bx * WM_SS, oy - by * WM_SS
    canvas[py0:py0 + h, px0:px0 + w] = rgba
    prem = canvas[..., :3] * canvas[..., 3:4]
    prem = prem.reshape(ch, WM_SS, cw, WM_SS, 3).mean(axis=(1, 3))
    a = canvas[..., 3].reshape(ch, WM_SS, cw, WM_SS).mean(axis=(1, 3))
    sl = (slice(by, by + ch), slice(bx, bx + cw))
    layer.p[sl] = prem * 255.0 + layer.p[sl] * (1 - a[..., None])
    layer.a[sl] = a + layer.a[sl] * (1 - a)
    return {
        "font_px": font_px / WM_SS,
        "ink_px": [bx + (px0 + ink_l) / WM_SS, by + (py0 + ink_rows[0]) / WM_SS,
                   bx + (px0 + ink_r) / WM_SS, by + (py0 + ink_rows[-1] + 1) / WM_SS],
    }


# ---------------------------------------------------------------- build
def build():
    bg_m = mat_translate(BG_TX, BG_TY) @ mat_scale(BG_S)

    # Art bounding box (SVG): union of the front card (incl. border) and the rotated back card.
    back_local = mat_translate(400, 530) @ mat_rotate(-12) @ mat_translate(-160, -210)
    back_outline = apply(back_local, rrect(0, 0, 320, 420, 22))
    xs = np.concatenate([back_outline[:, 0], [347, 709]])
    ys = np.concatenate([back_outline[:, 1], [271, 753]])
    c_svg = ((xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2)
    c_px = apply(bg_m, [c_svg])[0]
    art = mat_translate(*c_px) @ mat_scale(ART_SCALE) @ mat_translate(-c_px[0], -c_px[1]) @ bg_m
    back = art @ back_local

    # Background: ocean + ambient glow (1.1.4 frame).
    scene = np.broadcast_to(hexc("#0F3D52"), (N, N, 3)).copy()
    g_rgb, g_op = radial(BG_S, BG_TX, BG_TY, 0.52 * 1024, 0.52 * 1024, 0.42 * 1024,
                         [(0.0, "#1A7EA6", 0.22), (1.0, "#0F3D52", 0.0)])
    scene = scene * (1 - g_op[..., None]) + g_rgb * g_op[..., None]

    # Back card. The stripe is clipped to the card's rounded outline (in the SVG its
    # square ends poked past the rounded top corners).
    L = Layer()
    card_b = apply(back, rrect(0, 0, 320, 420, 22))
    L.paint(coverage((card_b, 255)), hexc("#1A7EA6"))
    L.paint(coverage_intersect(apply(back, rrect(0, 0, 320, 12, 0)), card_b), hexc("#5BC4E0"))
    for x, y, w, h in ((56, 200, 52, 140), (128, 148, 52, 192), (200, 96, 52, 244)):
        L.paint(coverage((apply(back, rrect(x, y, w, h, 5)), 255)), hexc("#FFFFFF"), 0.12)
    L.paint(coverage((apply(back, rrect(40, 348, 240, 4, 2)), 255)), hexc("#FFFFFF"), 0.14)
    scene = over(scene, L)

    # Front card group (drawn into its own layer so the drop shadow uses its alpha).
    F = Layer()
    card_f = apply(art, rrect(348, 272, 360, 480, 22))
    F.paint(coverage((card_f, 255)), hexc("#F7F9FC"))
    F.paint(coverage_intersect(apply(art, rrect(348, 272, 360, 14, 22)), card_f), hexc("#1A7EA6"))
    F.paint(coverage_intersect(apply(art, rrect(348, 278, 360, 8, 0)), card_f), hexc("#1A7EA6"))
    F.paint(coverage((apply(art, rrect(347, 271, 362, 482, 23)), 255),
                     (apply(art, rrect(349, 273, 358, 478, 21)), 0)), hexc("#C8DDE8"))
    chart = art @ mat_translate(0, CHART_DY_SVG)
    F.paint(coverage((apply(chart, rrect(388, 690, 280, 4, 2)), 255)), hexc("#C8DDE8"))
    amber_bar = [(0.0, "#F5C842"), (0.6, "#E8A020"), (1.0, "#D08810")]
    amber_top = [(0.0, "#FBE070"), (0.5, "#F5C842"), (1.0, "#E8A020")]
    for x, y, w, h, stops in ((400, 580, 68, 110, amber_bar), (492, 490, 68, 200, amber_bar),
                              (584, 400, 68, 290, amber_top)):
        F.paint(coverage((apply(chart, rrect(x, y, w, h, 6)), 255)), vertical_gradient(chart, y, h, stops))
    F.paint(coverage((apply(chart, circle(618, 390, 16)), 255)), hexc("#F5C842"))
    F.paint(coverage((apply(chart, circle(618, 390, 7)), 255)), hexc("#FFFFFF"), 0.55)
    wm = place_wordmark(F, art)

    # feDropShadow dx=0 dy=14 stdDeviation=28 #061820 @ 0.60 (SVG units -> px).
    s = art[0, 0]
    sh = ndimage.gaussian_filter(F.a, sigma=28 * s, mode="constant")
    sh = ndimage.shift(sh, (14 * s, 0), order=1, mode="constant")
    a = sh * 0.60
    scene = scene * (1 - a[..., None]) + hexc("#061820") * a[..., None]
    scene = over(scene, F)

    # Vignette (1.1.4 frame) over everything.
    v_rgb, v_op = radial(BG_S, BG_TX, BG_TY, 512, 512, 0.70 * 1024,
                         [(0.55, "#0F3D52", 0.0), (1.0, "#061820", 0.55)])
    scene = scene * (1 - v_op[..., None]) + v_rgb * v_op[..., None]

    out = np.clip(np.round(scene), 0, 255).astype(np.uint8)
    info = {
        "art_scale": ART_SCALE,
        "art_center_px": [round(float(c_px[0]), 2), round(float(c_px[1]), 2)],
        "art_bbox_px": [round(float(v), 1) for v in (*apply(art, [(xs.min(), ys.min())])[0],
                                                      *apply(art, [(xs.max(), ys.max())])[0])],
        "card_px": [round(float(v), 1) for v in (*apply(art, [(347, 271)])[0], *apply(art, [(709, 753)])[0])],
        "chart_dy_svg": CHART_DY_SVG,
        "dot_top_px": round(float(apply(art, [(618, DOT_TOP_SVG + CHART_DY_SVG)])[0][1]), 1),
        "baseline_bottom_px": round(float(apply(art, [(0, 694 + CHART_DY_SVG)])[0][1]), 1),
        "stripe_bottom_px": round(float(apply(art, [(0, 286)])[0][1]), 1),
        "wordmark": {k: ([round(float(x), 1) for x in v] if isinstance(v, list) else round(float(v), 2))
                     for k, v in wm.items()},
    }
    return out, info


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=ICON)
    ap.add_argument("--check-against", help="1.1.4 icon: report background difference away from the artwork")
    args = ap.parse_args()

    out, info = build()
    img = Image.fromarray(out)
    icc = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    img.save(args.out, "PNG", icc_profile=icc, optimize=True)
    print(json.dumps(info, indent=2))

    if args.check_against:
        old = np.asarray(Image.open(args.check_against).convert("RGB"), dtype=np.float64)
        yy, xx = np.mgrid[0:N, 0:N]
        # Away from both old and new artwork + shadows.
        far = (xx < 90) | (xx > 934) | (yy < 90) | (yy > 960)
        d = np.abs(old - out.astype(np.float64))[far]
        print(f"background check (outer band, {far.sum()} px): mean {d.mean():.2f}, "
              f"p99 {np.percentile(d, 99):.1f}, max {d.max():.0f}")


if __name__ == "__main__":
    main()
