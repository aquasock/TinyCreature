#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Turn a 32 by 32 tile sheet into indexed tiles the terrain renderer can plant.
#
#   tools/convert_tiles.py --sheet <png> --out <header.h> [--preview <png>]
#
# Meph's tileset and Dungeon Crawl Stone Soup both draw at 32 by 32; Meph
# ships its art as 512 by 512 sheets, which is 256 tiles on a 16 by 16 grid,
# with `-top` and `-bg` variants for Dwarf Fortress's layered drawing.  One
# sheet is converted here, its blank tiles dropped, and what is left is
# quantised together into the palette entries above the land's own -- the pool
# entry 31 freed by fitting the island to 192 -- so that a whole set of tiles
# shares one small palette the way the island shares another.
#
# The output is a C header holding that palette and, per tile and per mosaic
# cell, the palette entry the cell takes.  It is a build product and never
# committed, because the art is Meph's, Vordak's and Denzi's and not ours; see
# THIRD_PARTY.md for the credit and the source.
#
# The cell grid is the shape the renderer plants today, one flat quad a cell,
# so the same header serves the mosaic now and a fabric texture store later
# when the tile pixels themselves move into BSRAM.

import argparse
import sys
from PIL import Image

EMPTY = 0xFF
TILE = 32


def die(message):
    print(f"convert_tiles: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_sheet(path, tile=TILE):
    """Every 32 by 32 tile of a sheet, in reading order, blanks dropped."""
    try:
        image = Image.open(path).convert("RGBA")
    except OSError as error:
        die(f"{path}: {error}")
    if image.size[0] % tile or image.size[1] % tile:
        die(f"{path}: {image.size[0]} by {image.size[1]} is not a whole "
            f"number of {tile} by {tile} tiles")
    across, down = image.size[0] // tile, image.size[1] // tile
    tiles = []
    for ty in range(down):
        for tx in range(across):
            box = (tx * tile, ty * tile, tx * tile + tile, ty * tile + tile)
            crop = image.crop(box)
            crop.load()
            opaque = sum(1 for y in range(tile) for x in range(tile)
                         if crop.getpixel((x, y))[3] > 0)
            if opaque == 0:
                continue
            tiles.append(((tx, ty), crop, opaque))
    return tiles


def median_cut(weighted, count):
    """weighted: {colour: weight} -> (palette, {colour: index}).

    The same fitter the land's converter uses, so that a tile palette and a
    land palette are chosen the same way and their errors are comparable.
    """
    boxes = [sorted(weighted)]
    while len(boxes) < count:
        best, best_range, best_channel = None, 0, 0
        for i, box in enumerate(boxes):
            if len(box) < 2:
                continue
            for channel in range(3):
                values = [c[channel] for c in box]
                spread = max(values) - min(values)
                if spread > best_range:
                    best, best_range, best_channel = i, spread, channel
        if best is None:
            break
        box = sorted(boxes[best], key=lambda c: (c[best_channel], c))
        total = sum(weighted[c] for c in box)
        running, cut = 0, 1
        for i, colour in enumerate(box[:-1]):
            running += weighted[colour]
            if running * 2 >= total:
                cut = i + 1
                break
        boxes[best:best + 1] = [box[:cut], box[cut:]]
    palette, index = [], {}
    for i, box in enumerate(boxes):
        total = sum(weighted[c] for c in box)
        palette.append(tuple(
            (sum(c[ch] * weighted[c] for c in box) + total // 2) // total
            for ch in range(3)))
        for colour in box:
            index[colour] = i
    return palette, index


def fit_error(weighted, palette, index):
    total, weight, worst = 0, 0, 0
    for colour, w in weighted.items():
        p = palette[index[colour]]
        d2 = sum((colour[ch] - p[ch]) ** 2 for ch in range(3))
        total += d2 * w
        weight += w
        worst = d2 if d2 > worst else worst
    return ((total / weight) ** 0.5 if weight else 0.0), worst ** 0.5


def cell_grid(tile_image, cell, palette):
    """One palette index a cell, or EMPTY, over a whole tile."""
    across = TILE // cell
    grid = []
    for cy in range(across):
        for cx in range(across):
            total, count = 0, 0
            for y in range(cy * cell, (cy + 1) * cell):
                for x in range(cx * cell, (cx + 1) * cell):
                    pixel = tile_image.getpixel((x, y))
                    if pixel[3] == 0:
                        continue
                    total += pixel[0] * 299 + pixel[1] * 587 + pixel[2] * 114
                    count += 1
            if count * 2 < cell * cell:
                grid.append(EMPTY)
                continue
            # The cell takes the entry nearest its own mean colour.
            r = g = b = 0
            n = 0
            for y in range(cy * cell, (cy + 1) * cell):
                for x in range(cx * cell, (cx + 1) * cell):
                    pixel = tile_image.getpixel((x, y))
                    if pixel[3] == 0:
                        continue
                    r += pixel[0]
                    g += pixel[1]
                    b += pixel[2]
                    n += 1
            mean = (r // n, g // n, b // n)
            best, best_d = 0, None
            for i in range(len(palette)):
                p = palette[i]
                d = sum((mean[ch] - p[ch]) ** 2 for ch in range(3))
                if best_d is None or d < best_d:
                    best, best_d = i, d
            grid.append(best)
    return grid


def main():
    parser = argparse.ArgumentParser(
        description="Convert a 32 by 32 tile sheet into indexed tiles.")
    parser.add_argument("--sheet", required=True, help="the 32 by 32 tile sheet")
    parser.add_argument("--out", required=True, help="the C header to write")
    parser.add_argument("--first", type=int, default=211,
                        help="the pool's first palette entry (default 211)")
    parser.add_argument("--colours", type=int, default=45,
                        help="the pool's size (default 45, entries 211 to 255)")
    parser.add_argument("--cell", type=int, default=4,
                        help="source pixels a mosaic cell covers (default 4)")
    parser.add_argument("--limit", type=int,
                        help="convert at most this many tiles")
    parser.add_argument("--mosaic", action="store_true",
                        help="also write the per-cell mosaic grids, which the "
                             "renderer's flat-quad path plants")
    parser.add_argument("--preview", help="a PNG of the tiles as they will plant")
    args = parser.parse_args()

    if TILE % args.cell:
        die(f"cell {args.cell} does not divide the tile's {TILE} pixels")
    if args.first + args.colours > 256:
        die(f"entries {args.first} to {args.first + args.colours} run past 255")

    tiles = load_sheet(args.sheet)
    if args.limit:
        tiles = tiles[:args.limit]
    if not tiles:
        die(f"{args.sheet}: no tile in the sheet has a pixel in it")

    weighted = {}
    for _, crop, _ in tiles:
        for y in range(TILE):
            for x in range(TILE):
                pixel = crop.getpixel((x, y))
                if pixel[3] == 0:
                    continue
                colour = (pixel[0], pixel[1], pixel[2])
                weighted[colour] = weighted.get(colour, 0) + 1
    palette, index = median_cut(weighted, args.colours)
    mean, worst = fit_error(weighted, palette, index)

    lines = []
    lines.append("// Generated by tools/convert_tiles.py from a 32 by 32 tile")
    lines.append("// sheet, quantised into the palette entries above the land's.")
    lines.append("// Not committed: the art is not this project's.  See the tool.")
    lines.append("")
    lines.append(f"#define TC_TILES_FIRST {args.first}")
    lines.append(f"#define TC_TILES_COLOURS {len(palette)}")
    lines.append(f"#define TC_TILE_SIZE {TILE}")
    lines.append(f"#define TC_TILE_CELL {args.cell}")
    lines.append(f"#define TC_TILE_CELLS {TILE // args.cell}")
    lines.append(f"#define TC_TILE_EMPTY 0x{EMPTY:02x}")
    lines.append(f"#define TC_TILE_COUNT {len(tiles)}")
    lines.append("")
    lines.append("/* The pool's colours, in the entries the land does not use. */")
    lines.append("static const uint32_t tc_tile_palette[] = {")
    for i, (r, g, b) in enumerate(palette):
        lines.append(f"\t0x{r:02x}{g:02x}{b:02x}, /* {args.first + i} */")
    lines.append("};")
    lines.append("")
    lines.append("/* The tiles themselves, one palette-relative index a pixel, row")
    lines.append(" * major, a tile at a time: what the textured quad command reads. */")
    lines.append("static const uint8_t tc_tile_pixels[] = {")
    for (tx, ty), crop, _ in tiles:
        lines.append(f"\t/* sheet {tx},{ty} */")
        for y in range(TILE):
            row = []
            for x in range(TILE):
                pixel = crop.getpixel((x, y))
                if pixel[3] == 0:
                    # A card is opaque: what the art leaves transparent takes
                    # the palette's darkest entry rather than nothing.
                    row.append("0x00")
                    continue
                colour = (pixel[0], pixel[1], pixel[2])
                row.append(f"0x{index[colour]:02x}")
            lines.append("\t" + ", ".join(row) + ",")
    lines.append("};")
    lines.append("")
    if args.mosaic:
        lines.append("/* One index a cell, tile by tile, row major, 0xff empty. */")
        lines.append("static const uint8_t tc_tile_cells[] = {")
    row_cells = TILE // args.cell
    for (tx, ty), crop, _ in tiles:
        if not args.mosaic:
            break
        grid = cell_grid(crop, args.cell, palette)
        lines.append(f"\t/* sheet {tx},{ty} */")
        for y in range(row_cells):
            cells = grid[y * row_cells:(y + 1) * row_cells]
            lines.append("\t" + ", ".join(
                "0xff" if v == EMPTY else f"0x{v:02x}" for v in cells) + ",")
    if args.mosaic:
        lines.append("};")
        lines.append("")
    summary = (f"{args.sheet}: {len(tiles)} tiles of {TILE} by {TILE} pixels, "
               f"{len(weighted)} source colours fitted to {len(palette)} entries "
               f"at {args.first}, error {mean:.2f} mean and {worst:.1f} worst of "
               f"255")
    lines.append("/* " + summary.replace("*/", "* /") + " */")
    lines.append("")
    with open(args.out, "w") as out:
        out.write("\n".join(lines))

    if args.preview:
        side = TILE // args.cell
        scale = 4
        across = 16
        previews = [cell_grid(crop, args.cell, palette) for _, crop, _ in tiles]
        down = (len(previews) + across - 1) // across
        image = Image.new("RGB", (across * side * scale, down * side * scale),
                          (0, 0, 0))
        for i, grid in enumerate(previews):
            px, py = (i % across) * side * scale, (i // across) * side * scale
            for cy in range(side):
                for cx in range(side):
                    v = grid[cy * side + cx]
                    if v == EMPTY:
                        continue
                    colour = palette[v]
                    for y in range(cy * scale, (cy + 1) * scale):
                        for x in range(cx * scale, (cx + 1) * scale):
                            image.putpixel((px + x, py + y), colour)
        image.save(args.preview)

    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
