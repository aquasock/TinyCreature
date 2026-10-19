#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Flatten two aligned Meph tree cells into a two-tile tree sheet.

The source art stays outside this repository.  Meph's base, background-mask
and top sheets share the same 16 by 16 grid; this tool turns a lower trunk cell
and an upper fork cell into tiles for TinyCreature's texture store.  The base
layer of the current Meph sheet is opaque and its -bg layer is uniform white,
so the result is still an opaque square: this tool does not invent a tree
silhouette the source does not have.  What alpha the layers do carry is kept,
and convert_tiles.py turns it into the rasterizer's transparent key; the animal
icons are the art that has it.  The dark tint is what makes the unavoidable
square read as dense foliage rather than an accidental black key colour.
"""

import argparse
import sys
from pathlib import Path

from PIL import Image

TILE = 32


def die(message):
    print(f"make_tree_sheet: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_cell(value):
    try:
        x, y = (int(part, 0) for part in value.split(",", 1))
    except ValueError:
        raise argparse.ArgumentTypeError("cell must be X,Y") from None
    if not 0 <= x < 16 or not 0 <= y < 16:
        raise argparse.ArgumentTypeError("cell must be inside the 16 by 16 sheet")
    return x, y


def parse_colour(value):
    value = value.removeprefix("#")
    if len(value) != 6:
        raise argparse.ArgumentTypeError("tint must be six hexadecimal digits")
    try:
        return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        raise argparse.ArgumentTypeError("tint must be six hexadecimal digits") from None


def load(path):
    try:
        image = Image.open(path).convert("RGBA")
    except OSError as error:
        die(f"{path}: {error}")
    if image.size != (16 * TILE, 16 * TILE):
        die(f"{path}: expected a 512 by 512 sheet, got {image.size[0]} by {image.size[1]}")
    return image


def crop(image, cell):
    x, y = cell
    return image.crop((x * TILE, y * TILE, (x + 1) * TILE, (y + 1) * TILE))


def flatten(base, background, top, cell, tint, base_alpha):
    mask = crop(background, cell).getchannel("A")
    backing = Image.new("RGBA", (TILE, TILE), tint + (0,))
    backing.putalpha(mask)

    colour = crop(base, cell)
    alpha = colour.getchannel("A").point(lambda value: value * base_alpha // 255)
    colour.putalpha(alpha)
    result = Image.alpha_composite(backing, colour)
    return Image.alpha_composite(result, crop(top, cell))


def main():
    parser = argparse.ArgumentParser(
        description="Make a cutout two-tile tree sheet from Meph's layers.")
    parser.add_argument("--base", required=True)
    parser.add_argument("--background", required=True)
    parser.add_argument("--top", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--lower", type=parse_cell, default=(6, 2),
                        help="lower trunk cell X,Y (default: 6,2)")
    parser.add_argument("--upper", type=parse_cell, default=(5, 2),
                        help="upper fork cell X,Y (default: 5,2)")
    parser.add_argument("--tint", type=parse_colour, default=(16, 36, 20),
                        help="foliage backing RRGGBB (default: 102414)")
    parser.add_argument("--base-alpha", type=int, default=208,
                        help="base-layer opacity from 0 to 255 (default: 208)")
    args = parser.parse_args()
    if not 0 <= args.base_alpha <= 255:
        die("--base-alpha must be between 0 and 255")

    base = load(args.base)
    background = load(args.background)
    top = load(args.top)
    tiles = [flatten(base, background, top, cell, args.tint, args.base_alpha)
             for cell in (args.lower, args.upper)]
    sheet = Image.new("RGBA", (2 * TILE, TILE), (0, 0, 0, 0))
    for x, tile in enumerate(tiles):
        sheet.paste(tile, (x * TILE, 0))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"{out}: lower {args.lower[0]},{args.lower[1]}, "
          f"upper {args.upper[0]},{args.upper[1]}, tint "
          f"{args.tint[0]:02x}{args.tint[1]:02x}{args.tint[2]:02x}")


if __name__ == "__main__":
    main()
