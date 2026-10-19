#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Choose Meph's greenest cutout plants and lay them into a tile sheet.

    tools/make_plant_sheet.py --base _Meph_plants.png --top _Meph_plants-top.png \
        --count 16 --out build/plants/meph-plants.png

Only cells that are sprites are considered: a cell with alpha is a sprite, a
fully opaque cell is a ground tile and a nearly full one is a tile with a
transparent edge, so the two ends are excluded.  The --count greenest are kept,
ranked by how far their opaque pixels run past the red and blue channels, with
partial alpha weighted in.  Their own alpha is preserved, so the fill's key
turns the rest of the square into a hole, and they are written in reading order
of the chosen set, one 32 by 32 tile each.
"""

import argparse
import sys
from pathlib import Path

from PIL import Image

TILE = 32
GRID = 16
NEARLY_FULL = 972             # 95 percent of 1024; row 0's nearly full tiles
WHITE = (255, 255, 255)


def die(message):
    print(f"make_plant_sheet: {message}", file=sys.stderr)
    raise SystemExit(1)


def load(path):
    try:
        image = Image.open(path).convert("RGBA")
    except OSError as error:
        die(f"{path}: {error}")
    if image.size != (GRID * TILE, GRID * TILE):
        die(f"{path}: expected a {GRID * TILE} by {GRID * TILE} sheet, "
            f"got {image.size[0]} by {image.size[1]}")
    return image


def greenness(cell):
    """How green the sprite is: excess green over the stronger other channel."""
    total = 0
    for r, g, b, a in cell.getdata():
        if a == 0:
            continue
        excess = g - max(r, b)
        if excess > 0:
            total += excess * a // 255
    return total


def sprites(base, top):
    found = []
    for y in range(GRID):
        for x in range(GRID):
            box = (x * TILE, y * TILE, (x + 1) * TILE, (y + 1) * TILE)
            body = base.crop(box)
            alpha = body.getchannel("A")
            opaque = sum(1 for value in alpha.getdata() if value > 0)
            if opaque == 0 or opaque >= NEARLY_FULL:
                continue
            found.append((greenness(body), y * GRID + x, x, y,
                          Image.alpha_composite(body, top.crop(box))))
    return found


def main():
    parser = argparse.ArgumentParser(
        description="Pick the greenest plant sprites into a tile sheet.")
    parser.add_argument("--base", required=True)
    parser.add_argument("--top", required=True)
    parser.add_argument("--count", type=int, default=16)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    if args.count < 1:
        die("--count must be positive")

    base = load(args.base)
    top = load(args.top)
    found = sprites(base, top)
    if len(found) < args.count:
        die(f"only {len(found)} sprites, asked for {args.count}")
    found.sort(key=lambda item: (-item[0], item[1]))
    chosen = found[:args.count]
    chosen.sort(key=lambda item: item[1])

    across = 4
    down = (len(chosen) + across - 1) // across
    sheet = Image.new("RGBA", (across * TILE, down * TILE), (0, 0, 0, 0))
    for i, (_score, index, _x, _y, image) in enumerate(chosen):
        sheet.paste(image, ((i % across) * TILE, (i // across) * TILE))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)

    print(f"{out}: {len(chosen)} plants, greenest first")
    for i, (score, index, x, y, _image) in enumerate(chosen):
        print(f"  tile {i:2d}: cell {index:3d} ({x:2d},{y:2d}) "
              f"greenness {score}")


if __name__ == "__main__":
    main()
