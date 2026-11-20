#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Adapts light-background penguin-and-gear artwork (GIF/JPG) for NeuroCore OS
dark #0b0f14 boot surfaces (transparent background, crisp #f1f5f9 penguin
strokes, preserved emerald green gear/accents).

Uses 3x2 linear least-squares unmixing on (background, dark_ink, brand_green)
so anti-aliased edges stay razor sharp with zero off-white fringe.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from PIL import Image, ImageSequence


def _unmix_frame_dark(img: Image.Image) -> tuple[Image.Image, tuple[int, int, int, int]]:
    rgb = img.convert("RGB")
    w, h = rgb.size
    px = rgb.load()

    # Sample background from top-left patch
    bg_r = bg_g = bg_b = 0.0
    n_bg = 0
    for y in range(min(10, h)):
        for x in range(min(10, w)):
            r, g, b = px[x, y]
            bg_r += r
            bg_g += g
            bg_b += b
            n_bg += 1
    bg_r /= max(1, n_bg)
    bg_g /= max(1, n_bg)
    bg_b /= max(1, n_bg)

    # Sample green & black basis colors and find logo bounding box
    gr_r = gr_g = gr_b = 0.0
    n_gr = 0
    bk_r = bk_g = bk_b = 0.0
    n_bk = 0
    min_x, min_y, max_x, max_y = w, h, 0, 0

    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            dist = math.sqrt((r - bg_r) ** 2 + (g - bg_g) ** 2 + (b - bg_b) ** 2)
            if dist > 32.0:
                if x < min_x:
                    min_x = x
                if x > max_x:
                    max_x = x
                if y < min_y:
                    min_y = y
                if y > max_y:
                    max_y = y
            if g - max(r, b) > 85 and g > 150:
                gr_r += r
                gr_g += g
                gr_b += b
                n_gr += 1
            if r < 25 and g < 25 and b < 25:
                bk_r += r
                bk_g += g
                bk_b += b
                n_bk += 1

    if n_gr > 0:
        gr_r, gr_g, gr_b = gr_r / n_gr, gr_g / n_gr, gr_b / n_gr
    else:
        gr_r, gr_g, gr_b = 27.4, 230.7, 109.0
    if n_bk > 0:
        bk_r, bk_g, bk_b = bk_r / n_bk, bk_g / n_bk, bk_b / n_bk
    else:
        bk_r, bk_g, bk_b = 4.0, 4.0, 4.0

    v1r, v1g, v1b = bk_r - bg_r, bk_g - bg_g, bk_b - bg_b
    v2r, v2g, v2b = gr_r - bg_r, gr_g - bg_g, gr_b - bg_b

    a11 = v1r * v1r + v1g * v1g + v1b * v1b
    a12 = v1r * v2r + v1g * v2g + v1b * v2b
    a22 = v2r * v2r + v2g * v2g + v2b * v2b
    det = max(1e-6, a11 * a22 - a12 * a12)

    stroke_r, stroke_g, stroke_b = 241.0, 245.0, 249.0  # #f1f5f9

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opx = out.load()

    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            dr, dg, db = r - bg_r, g - bg_g, b - bg_b
            rhs1 = dr * v1r + dg * v1g + db * v1b
            rhs2 = dr * v2r + dg * v2g + db * v2b
            wb = max(0.0, (a22 * rhs1 - a12 * rhs2) / det)
            wg = max(0.0, (-a12 * rhs1 + a11 * rhs2) / det)
            alpha = wb + wg
            if alpha < 0.06:
                continue
            alpha_clean = min(1.0, max(0.0, (alpha - 0.06) / 0.88))
            fb = wb / alpha
            fg = wg / alpha
            or_ = int(round(min(255.0, max(0.0, fb * stroke_r + fg * gr_r))))
            og_ = int(round(min(255.0, max(0.0, fb * stroke_g + fg * gr_g))))
            ob_ = int(round(min(255.0, max(0.0, fb * stroke_b + fg * gr_b))))
            oa_ = int(round(alpha_clean * 255.0))
            opx[x, y] = (or_, og_, ob_, oa_)

    if max_x <= min_x or max_y <= min_y:
        bbox = (0, 0, w, h)
    else:
        bbox = (min_x, min_y, max_x + 1, max_y + 1)
    return out, bbox


def convert_gif(gif_path: Path, out_dir: Path, size: int) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    with Image.open(gif_path) as im:
        frames = [frame.copy().convert("RGBA") for frame in ImageSequence.Iterator(im)]

    processed: list[Image.Image] = []
    u_min_x, u_min_y, u_max_x, u_max_y = 10**9, 10**9, 0, 0

    for frame in frames:
        rgba, (x0, y0, x1, y1) = _unmix_frame_dark(frame)
        processed.append(rgba)
        u_min_x = min(u_min_x, x0)
        u_min_y = min(u_min_y, y0)
        u_max_x = max(u_max_x, x1)
        u_max_y = max(u_max_y, y1)

    w, h = processed[0].size
    bw = max(1, u_max_x - u_min_x)
    bh = max(1, u_max_y - u_min_y)
    side = int(round(max(bw, bh) * 1.16))
    cx = (u_min_x + u_max_x) // 2
    cy = (u_min_y + u_max_y) // 2

    for idx, rgba in enumerate(processed):
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        paste_x = side // 2 - cx
        paste_y = side // 2 - cy
        square.paste(rgba, (paste_x, paste_y), rgba)
        resized = square.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(out_dir / f"frame-{idx:03d}.png", format="PNG")

    return len(processed)


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert NeuroCore boot GIF into dark-adapted Plymouth PNG frames")
    parser.add_argument("--gif", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--size", type=int, default=256)
    args = parser.parse_args()
    count = convert_gif(args.gif, args.out_dir, args.size)
    print(count)


if __name__ == "__main__":
    main()
