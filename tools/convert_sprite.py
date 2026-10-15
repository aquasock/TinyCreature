#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Turn a Dungeon Crawl Stone Soup two-tile emissary into a tall sprite the
# terrain renderer can plant on the land.
#
#   tools/convert_sprite.py <dir> <name> --out <header.h> [--preview <png>]
#
# DCSS draws its tall creatures as a pair of 32 by 32 tiles, `<name>_top.png`
# stacked on `<name>_bottom.png`, which is 32 by 64 of RGBA.  The emissaries
# are recolourable masks: nearly every pixel is grey, r = g = b, in a handful
# of steps, and the creature covers a third to a half of the tile.  So one
# luminance ramp describes the whole tile, and one palette of seven entries
# describes the ramp -- the seven the sea gave up, entries 9 to 15, which
# terrain.h names as TC_SPRITE_FIRST.
#
# The output is a C header, generated and never committed, holding the ramp's
# seven colours and the cell grid the renderer plants: one square per cell,
# 0xff meaning the cell holds nothing, which is how this sprite is transparent
# without the fabric having an alpha test.  The ramp lives in the header so
# that the palette the renderer loads and the preview this tool draws cannot
# drift apart; they are the same seven numbers.
#
# The tiles are Dungeon Crawl Stone Soup's art, so the header is a build
# product and the input is never copied into the repository, exactly as the
# game's own landscape file is not.

import argparse
import sys
from PIL import Image

EMPTY = 0xFF


def die(message):
    print(f"convert_sprite: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_stack(directory, name, side=32):
    """The top tile over the bottom tile, 32 wide and two tiles tall."""
    tiles = []
    for part in ("top", "bottom"):
        path = f"{directory}/{name}_{part}.png"
        try:
            image = Image.open(path).convert("RGBA")
        except OSError as error:
            die(f"{path}: {error}")
        if image.size != (side, side):
            die(f"{path}: {image.size[0]} by {image.size[1]}, expected {side} by {side}")
        tiles.append(image)

    out = Image.new("RGBA", (side, side * len(tiles)), (0, 0, 0, 0))
    for row, tile in enumerate(tiles):
        out.paste(tile, (0, row * side))
    return out


def trim(image, cell):
    """The art's own bounding box, grown out to whole cells.

    The lower tile pads seventeen transparent rows below the base, so a
    sprite anchored on the tile's edge stands in the air.  Cropping to what
    is drawn makes the sprite's bottom its base, which is what a placement
    on the ground wants.
    """
    side_x, side_y = image.size
    xs = []
    ys = []
    for y in range(side_y):
        for x in range(side_x):
            if image.getpixel((x, y))[3] > 0:
                xs.append(x)
                ys.append(y)
    if not xs:
        return image
    left = min(xs) // cell * cell
    top = min(ys) // cell * cell
    right = min(side_x, (max(xs) // cell + 1) * cell)
    bottom = min(side_y, (max(ys) // cell + 1) * cell)
    return image.crop((left, top, right, bottom)), (left, top, right, bottom)


def luminance(pixel):
    """The mask's own level: the emissaries are grey, so one channel says it.

    A few pixels carry a hue -- trog's arm is dark red -- and this reads them
    by their brightness alone, which loses their colour to the ramp.  Worth
    knowing rather than worth a second palette: the ramp is one hue by
    construction, and a mask is meant to be tinted, not to keep its accents.
    """
    r, g, b, a = pixel
    return (r * 299 + g * 587 + b * 114) // 1000


def ramp_colours(tint, steps, low, high):
    """Seven steps from the mask's darkest level to its lightest, tinted."""
    r = int(tint[0:2], 16)
    g = int(tint[2:4], 16)
    b = int(tint[4:6], 16)
    colours = []
    for i in range(steps):
        level = low + (high - low) * i // (steps - 1) if steps > 1 else high
        colours.append((
            min(255, r * level // 255),
            min(255, g * level // 255),
            min(255, b * level // 255),
        ))
    return colours


def cell_grid(image, cell, steps, low, high):
    """One ramp index a cell, or EMPTY, over the whole tall tile."""
    side = image.size[0]
    cells_x = side // cell
    cells_y = image.size[1] // cell
    grid = []
    for cy in range(cells_y):
        for cx in range(cells_x):
            total = 0
            count = 0
            for y in range(cy * cell, (cy + 1) * cell):
                for x in range(cx * cell, (cx + 1) * cell):
                    pixel = image.getpixel((x, y))
                    if pixel[3] == 0:
                        continue
                    total += luminance(pixel)
                    count += 1
            if count * 2 < cell * cell:
                # Less than half the cell is creature: leave it out, which is
                # this sprite's transparency and its silhouette at once.
                grid.append(EMPTY)
                continue
            mean = total // count
            span = high - low
            index = 0 if span <= 0 else (mean - low) * (steps - 1) // span
            grid.append(max(0, min(steps - 1, index)))
    return grid, cells_x, cells_y


def write_header(path, ramp, grid, cells_x, cells_y, cell, name, stats):
    lines = []
    lines.append("// Generated by tools/convert_sprite.py from Dungeon Crawl")
    lines.append(f"// Stone Soup's {name}_top.png over {name}_bottom.png.  Not committed:")
    lines.append("// the tiles are that project's art.  See the tool for the format.")
    lines.append("")
    lines.append(f"#define TC_SPRITE_NAME \"{name}\"")
    lines.append(f"#define TC_SPRITE_CELLS_X {cells_x}")
    lines.append(f"#define TC_SPRITE_CELLS_Y {cells_y}")
    lines.append(f"#define TC_SPRITE_CELL {cell}")
    lines.append(f"#define TC_SPRITE_EMPTY 0x{EMPTY:02x}")
    lines.append("")
    lines.append("/* The ramp, brightest last, in the sea's unused entries. */")
    lines.append("static const uint32_t tc_sprite_ramp[] = {")
    for i, (r, g, b) in enumerate(ramp):
        lines.append(f"\t0x{r:02x}{g:02x}{b:02x}, /* {i} */")
    lines.append("};")
    lines.append("")
    lines.append(f"#define TC_SPRITE_COLOURS {len(ramp)}")
    lines.append("")
    lines.append("/* One index a cell, row major, 0xff empty. */")
    lines.append("static const uint8_t tc_sprite_cells[] = {")
    for cy in range(cells_y):
        row = grid[cy * cells_x:(cy + 1) * cells_x]
        text = ", ".join("0xff" if v == EMPTY else f"0x{v:02x}" for v in row)
        lines.append(f"\t{text},")
    lines.append("};")
    lines.append("")
    lines.append("/* " + stats.replace("*/", "* /") + " */")
    lines.append("")
    with open(path, "w") as out:
        out.write("\n".join(lines))


def write_preview(path, ramp, grid, cells_x, cells_y, cell):
    """What the renderer will plant, so an eye can check it without a board."""
    scale = 4
    image = Image.new("RGB", (cells_x * cell * scale, cells_y * cell * scale), (0, 0, 0))
    for cy in range(cells_y):
        for cx in range(cells_x):
            value = grid[cy * cells_x + cx]
            if value == EMPTY:
                continue
            colour = ramp[value]
            for y in range(cy * cell * scale, (cy + 1) * cell * scale):
                for x in range(cx * cell * scale, (cx + 1) * cell * scale):
                    image.putpixel((x, y), colour)
    image.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory", help="the directory holding the two tiles")
    parser.add_argument("name", help="the tile's stem, e.g. okawaru")
    parser.add_argument("--cell", type=int, default=4,
                        help="source pixels a cell covers (default 4)")
    parser.add_argument("--steps", type=int, default=7,
                        help="ramp entries, no more than the free palette (default 7)")
    parser.add_argument("--tint", default="ffffff",
                        help="the mask's tint, RRGGBB (default ffffff, as drawn)")
    parser.add_argument("--low", type=int,
                        help="the ramp's darkest level (default: the mask's own)")
    parser.add_argument("--high", type=int,
                        help="the ramp's lightest level (default: the 95th percentile)")
    parser.add_argument("--out", required=True, help="the C header to write")
    parser.add_argument("--preview", help="a PNG of what will be planted")
    args = parser.parse_args()

    if args.cell <= 0 or args.steps < 2 or args.steps > 16:
        die("cell must be positive and steps between 2 and 16")
    tint = args.tint
    if len(tint) != 6:
        die("tint must be six hex digits")

    image = load_stack(args.directory, args.name)
    if image.size[0] % args.cell or image.size[1] % args.cell:
        die(f"cell {args.cell} does not divide {image.size[0]} by {image.size[1]}")
    image, box = trim(image, args.cell)

    levels = [luminance(image.getpixel((x, y)))
              for y in range(image.size[1]) for x in range(image.size[0])
              if image.getpixel((x, y))[3] > 0]
    if not levels:
        die(f"{args.name}: every pixel is transparent")
    low = args.low if args.low is not None else min(levels)
    # The light end defaults to a percentile, not the maximum: these masks are
    # dark -- half their pixels sit below level 64 and only a tenth above 192,
    # the bright staff among them -- so a ramp spread to the single brightest
    # pixel spends its top entries on nothing a cell average ever reaches.
    if args.high is not None:
        high = args.high
    else:
        ranked = sorted(levels)
        high = ranked[min(len(ranked) - 1, len(ranked) * 95 // 100)]
    if high <= low:
        die(f"{args.name}: nothing to spread a ramp over ({low} to {high})")

    ramp = ramp_colours(tint, args.steps, low, high)
    grid, cells_x, cells_y = cell_grid(image, args.cell, args.steps, low, high)

    opaque = len(levels)
    planted = sum(1 for v in grid if v != EMPTY)
    full = sum(1 for v in grid if v != EMPTY)
    stats = (f"{args.name}: {opaque} opaque source pixels of "
             f"{image.size[0] * image.size[1]}, levels {min(levels)} to {max(levels)}, "
             f"{len(set(levels))} distinct; trimmed to {box[0]},{box[1]} to {box[2]},{box[3]}; "
             f"{cells_x} by {cells_y} cells of {args.cell} px, {planted} planted, "
             f"{cells_x * cells_y - full} empty; ramp {low} to {high} tinted {tint}, "
             f"quads {planted}, triangles {planted * 2}")

    write_header(args.out, ramp, grid, cells_x, cells_y, args.cell, args.name, stats)
    if args.preview:
        write_preview(args.preview, ramp, grid, cells_x, cells_y, args.cell)
    print(stats)


if __name__ == "__main__":
    main()
