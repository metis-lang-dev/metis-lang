"""make_icons.py — the metis mark's icons from the source picture (brand/metis-icon-source.jpeg).

    python3 brand/make_icons.py [SOURCE] [OUT_DIR]       (Pillow, numpy; defaults: this folder)

The source (a generated design, 1024²) carries a white rounded square and a transparency checkerboard baked into its
pixels, around the mark and inside its circle. The icons drop them: outside the ring the ground is transparent (the
word's ink kept, its faint edge in its own navy, so no light fringe), inside the ring the checkerboard becomes the
design's white. Written:
- metis-logo-512.png      the circle and the word, transparent, 512²
- metis-mark-512.png      the circle alone (the word is navy, faint on dark grounds and at small sizes), 512²
- vscode-icon.png         the logo at 256² (contrib/vscode/images/icon.png)
- favicon-32.png, favicon-192.png   the mark, transparent (the site's <link rel=icon>)
- apple-touch-icon.png    the mark on white, 180² (iOS fills a transparent ground with black)
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def clean(src):
    """→ (RGBA image, circle centre x, y, radius, the word's bottom row)."""
    im = np.asarray(Image.open(src).convert("RGB")).astype(float)
    luma = im @ [0.299, 0.587, 0.114]
    sat = im.max(axis=2) - im.min(axis=2)
    mark = (luma < 140) | (sat > 40)                       # the ring, the strokes, the word (the grounds are grey)
    ys, xs = np.where(mark)
    upper = ys < ys.min() + 0.83 * (ys.max() - ys.min())   # the circle is the upper part, the word below it
    cx = (xs[upper].min() + xs[upper].max()) / 2
    R = (xs[upper].max() - xs[upper].min()) / 2
    cy = ys[upper].max() - R
    bottom = ys.max()
    H, W = luma.shape
    yy, xx = np.mgrid[0:H, 0:W]
    dist = np.hypot(xx - cx, yy - cy)
    inside = dist <= R - 6
    grey = (np.clip((luma - 150) / 60, 0, 1) * np.clip((40 - sat) / 30, 0, 1))[..., None]
    rgb = np.where(inside[..., None], im * (1 - grey) + 255 * grey, im)
    ink = np.clip(np.maximum((205 - luma) / 145, (sat - 25) / 60), 0, 1)
    alpha = np.where(inside, 1.0, ink)
    navy = im[(luma < 90) & (dist > R + 10)].mean(axis=0)
    rgb[(~inside) & (alpha < 0.95)] = navy
    rgba = np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA"), cx, cy, R, bottom


def square(img, cx, cy, side):
    x0, y0 = int(round(cx - side / 2)), int(round(cy - side / 2))
    return img.crop((x0, y0, x0 + int(side), y0 + int(side)))


def main(src=None, out=None):
    src = src or os.path.join(HERE, "metis-icon-source.jpeg")
    out = out or HERE
    img, cx, cy, R, bottom = clean(src)
    top = cy - R
    logo = square(img, cx, (top + bottom) / 2, max(bottom - top, 2 * R) + 24)
    mark = square(img, cx, cy, 2 * R + 16)
    put = lambda im, n, s: im.resize((s, s), Image.LANCZOS).save(os.path.join(out, n))
    put(logo, "metis-logo-512.png", 512)
    put(mark, "metis-mark-512.png", 512)
    put(logo, "vscode-icon.png", 256)
    put(mark, "favicon-32.png", 32)
    put(mark, "favicon-192.png", 192)
    touch = Image.new("RGBA", (180, 180), (255, 255, 255, 255))
    touch.alpha_composite(mark.resize((164, 164), Image.LANCZOS), (8, 8))
    touch.convert("RGB").save(os.path.join(out, "apple-touch-icon.png"))
    print("circle (%.1f, %.1f) r %.1f; written to %s" % (cx, cy, R, out))


if __name__ == "__main__":
    main(*sys.argv[1:3])
