#!/usr/bin/env python3
"""Recolor app art into the approved Huawei orange palette (idempotent, --check mode)."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def _hsv(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx, mn = a.max(-1), a.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rc, gc, bc = (mx == r) & m, (mx == g) & m & (mx != r), (mx == b) & m & (mx != r) & (mx != g)
    h[rc] = ((g - b)[rc] / d[rc]) % 6
    h[gc] = (b - r)[gc] / d[gc] + 2
    h[bc] = (r - g)[bc] / d[bc] + 4
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h * 60, s, mx


def _rgb(h, s, v):
    c = v * s
    x = c * (1 - np.abs((h / 60) % 2 - 1))
    m = v - c
    z = np.zeros_like(h)
    k = (h // 60).astype(int) % 6
    r = np.select([k == 0, k == 1, k == 2, k == 3, k == 4, k == 5], [c, x, z, z, x, c])
    g = np.select([k == 0, k == 1, k == 2, k == 3, k == 4, k == 5], [x, c, c, x, z, z])
    b = np.select([k == 0, k == 1, k == 2, k == 3, k == 4, k == 5], [z, z, x, c, c, x])
    return np.stack([r + m, g + m, b + m], -1)


def to_orange(im, lo=60, hi=330, h0=14, h1=40, smin=0.15, sat=1.08):
    """Map hues in [lo, hi] (greens, cyans, blues, purples) onto [h0, h1] (red-orange .. amber); warm hues and greys stay."""
    rgba = im.convert("RGBA")
    a = np.asarray(rgba).astype(np.float64) / 255
    h, s, v = _hsv(a[..., :3])
    cool = (s > smin) & (h >= lo) & (h <= hi)
    nh = h0 + (h - lo) / (hi - lo) * (h1 - h0)
    # feather the saturation edge so anti-aliased outlines do not keep a blue fringe
    w = np.clip((s - smin) / 0.08, 0, 1) * cool
    out_h = np.where(cool, nh, h)
    out_s = np.where(cool, np.minimum(1, s * sat), s)
    rgb = _rgb(out_h, out_s, v)
    rgb = rgb * w[..., None] + a[..., :3] * (1 - w[..., None])
    out = np.dstack([np.clip(rgb, 0, 1), a[..., 3:]])
    return Image.fromarray((out * 255 + .5).astype(np.uint8), "RGBA").copy()


def muscles_to_orange(im):
    """Exercise art: the blue target-muscle layer becomes the Move orange; the grey figure stays."""
    return to_orange(im, lo=180, hi=265, h0=16, h1=20, smin=0.07, sat=1.0)


def icon_to_orange(im):
    """Clay icons -> Huawei orange 3D: blues/purples become orange, greens become brightened amber-orange (no browns)."""
    rgba = im.convert("RGBA")
    a = np.asarray(rgba).astype(np.float64) / 255
    h, s, v = _hsv(a[..., :3])
    blue = (h >= 180) & (h <= 330)
    green = (h >= 60) & (h < 180)
    cool = (s > 0.12) & (blue | green)
    w = np.clip((s - 0.12) / 0.08, 0, 1) * cool
    nh = np.where(blue, 24.0, 33.0)
    nv = np.where(green, np.minimum(1, v * 1.24 + 0.02), v)
    ns = np.minimum(1, np.where(s > 0.3, np.maximum(s, 0.62), s) * 1.06)
    rgb = _rgb(np.where(cool, nh, h), np.where(cool, ns, s), np.where(cool, nv, v))
    rgb = rgb * w[..., None] + a[..., :3] * (1 - w[..., None])
    out = np.dstack([np.clip(rgb, 0, 1), a[..., 3:]])
    return Image.fromarray((out * 255 + .5).astype(np.uint8), "RGBA").copy()


ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App/Forge/Assets.xcassets"
EXERCISE = sorted(ASSETS.glob("ExerciseArt/*.imageset/*.jpg"))
CLAY = sorted(
    list(ASSETS.glob("art-*.imageset/*.png"))
    + list(ASSETS.glob("eq-*.imageset/*.png"))
    + list(ASSETS.glob("goal-*.imageset/*.png"))
    + list(ASSETS.glob("medal-*.imageset/*.png"))
)


def cool_count(im, lo, hi, alpha=False):
    a = np.asarray(im.convert("RGBA")).astype(np.float64) / 255
    h, s, _ = _hsv(a[..., :3])
    m = (s > 0.25) & (h >= lo) & (h <= hi)
    if alpha:
        m &= a[..., 3] > 0.5
    return int(m.sum())


def process(files, fn, lo, hi, alpha, check_only):
    written = still = 0
    for p in files:
        n = cool_count(Image.open(p), lo, hi, alpha)
        if n < 40:
            continue
        if check_only:
            still += 1
            print(f"  still cool: {p.relative_to(ROOT)} ({n}px)")
        else:
            out = fn(Image.open(p))
            if not alpha:
                out = out.convert("RGB")
                out.save(p, quality=92, subsampling=0)
            else:
                out.save(p)
            written += 1
    return written, still


def main():
    check = "--check" in sys.argv
    any_still = 0
    for files, fn, lo, hi, alpha, label in [
        (EXERCISE, muscles_to_orange, 180, 265, False, "exercise"),
        (CLAY, icon_to_orange, 60, 330, True, "clay"),
    ]:
        written, still = process(files, fn, lo, hi, alpha, check)
        any_still += still
        print(f"{label}: {len(files)} files, {'still cool' if check else 'written'}: {still if check else written}")
    if check and any_still:
        sys.exit(1)


if __name__ == "__main__":
    main()
