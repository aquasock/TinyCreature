#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Compose a 32 by 32 tile sheet out of a directory of 32 by 32 icons.
#
#   tools/make_animal_sheet.py <dir> <out.png> [--count 64] [--side 8]
#
# Dungeon Crawl Stone Soup's monster art is one 32 by 32 PNG an icon, and
# tools/convert_tiles.py reads one sheet, so the two need a step between them:
# this lays the icons out on a square grid in sorted filename order, which is
# what makes the result the same picture every time, and pads the grid with
# transparent tiles when there are fewer icons than cells.
#
# 64 is the default count because that is what fpga/raster.sv's tile store
# holds; convert_tiles.py drops blank tiles and the terrain renderer walks the
# tiles it has, so the count here is an upper bound and not a promise.
#
# The output is a build product and is never committed, because the art is not
# this project's; see THIRD_PARTY.md for the credit.

import argparse
import sys
from pathlib import Path

from PIL import Image

TILE = 32


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", help="directory of 32 by 32 PNG icons")
    ap.add_argument("out", help="the sheet to write")
    ap.add_argument("--count", type=int, default=64)
    ap.add_argument("--side", type=int, default=8)
    args = ap.parse_args()

    icons = sorted(Path(args.dir).glob("*.png"))
    if not icons:
        print(f"make_animal_sheet: no .png icons in {args.dir}", file=sys.stderr)
        return 1

    cells = args.side * args.side
    if args.count > cells:
        print(f"make_animal_sheet: --count {args.count} needs --side at least "
              f"{int(args.count ** 0.5) + 1}", file=sys.stderr)
        return 1

    sheet = Image.new("RGBA", (args.side * TILE, args.side * TILE), (0, 0, 0, 0))
    used = 0
    for icon in icons[:args.count]:
        image = Image.open(icon).convert("RGBA")
        if image.size != (TILE, TILE):
            print(f"make_animal_sheet: {icon.name} is {image.size[0]} by "
                  f"{image.size[1]}, not {TILE} by {TILE}", file=sys.stderr)
            return 1
        sheet.paste(image, ((used % args.side) * TILE, (used // args.side) * TILE))
        used += 1

    sheet.save(args.out)
    print(f"make_animal_sheet: {used} icon(s) of {len(icons)} into "
          f"{args.side} by {args.side} at {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
