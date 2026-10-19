#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read a Black & White level script's plants into a card table for the firmware.

    tools/convert_plants.py --script Land1.txt --land Land1.lnd \
        --units 160 --out build/plants/land1-plants.h

Black & White does not store its trees in the landscape file; the level script
places them, one command each:

    CREATE_NEW_TREE(forestId, "x,z", type, nonScenic, rotation, size, maxSize)
    CREATE_DEAD_TREE("x,z", player, type, scale, roll, yaw, pitch)

The rotation is in radians and the size a multiplier on the mesh's own size;
openblack hands both to its tree archetype unchanged.  This tool keeps the
positions, rotations and scales as the original states them, converts the
world position to the land grid the same way tools/convert_land.py does -- the
.lnd's block table sets the origin, and the firmware's world is that island
origin at 0,0 -- and writes a C table sorted by grid cell, so the firmware can
find a cell's plants with a binary search during its walk.

One card a plant, the tile chosen by the script's type, and the card's size is
--units (Q4 at scale 1.0) times the script's size.
"""

import argparse
import importlib.util
import math
import re
import sys
from pathlib import Path

TURN = 65536                      # yaw units in a full turn
Q4 = 16                           # world units to Q4, since CELL is 160 Q4 / 10
CELL_UNITS = 10                   # world units in a terrain cell

NEW_TREE = re.compile(
    r'CREATE_NEW_TREE\(\s*-?\d+,\s*"(-?[\d.]+),(-?[\d.]+)",\s*(\d+),'
    r'\s*-?\d+,\s*(-?[\d.]+),\s*([-\d.]+),\s*[-\d.]+\)')
DEAD_TREE = re.compile(
    r'CREATE_DEAD_TREE\(\s*"(-?[\d.]+),(-?[\d.]+)",\s*"[^"]*",\s*(\d+),'
    r'\s*([-\d.]+),\s*[-\d.]+,\s*([-\d.]+),\s*[-\d.]+\)')


def die(message):
    print(f"convert_plants: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_land_module():
    path = Path(__file__).resolve().parent / "convert_land.py"
    spec = importlib.util.spec_from_file_location("convert_land", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_script(path):
    """[(x, z, type, rotation, scale)] from the level script, in file order."""
    plants = []
    try:
        lines = open(path, errors="replace")
    except OSError as error:
        die(f"{path}: {error}")
    with lines:
        for line in lines:
            match = NEW_TREE.match(line)
            if match:
                plants.append((float(match.group(1)), float(match.group(2)),
                               int(match.group(3)), float(match.group(4)),
                               float(match.group(5))))
                continue
            match = DEAD_TREE.match(line)
            if match:
                plants.append((float(match.group(1)), float(match.group(2)),
                               int(match.group(3)), float(match.group(5)),
                               float(match.group(4))))
    return plants


def land_origin(land_path):
    land = load_land_module()
    try:
        data = Path(land_path).read_bytes()
    except OSError as error:
        die(f"{land_path}: {error}")
    _lut, blocks, _countries, _materials, _noise, _bump = land.read_lnd(data)
    xs = [block[0] for block in blocks]
    zs = [block[1] for block in blocks]
    return (min(xs) * 16, min(zs) * 16,
            (max(xs) - min(xs) + 1) * 16, (max(zs) - min(zs) + 1) * 16)


def main():
    parser = argparse.ArgumentParser(
        description="Turn a level script's trees into a C card table.")
    parser.add_argument("--script", required=True,
                        help="the level script, for example Scripts/Land1.txt")
    parser.add_argument("--land", required=True,
                        help="the .lnd the script loads, for the grid origin")
    parser.add_argument("--units", type=int, default=160,
                        help="card size in Q4 at scale 1.0 (default 160, "
                             "ten world units)")
    parser.add_argument("--tiles", type=int, default=16,
                        help="tiles in the sheet; the script's types are "
                             "mapped onto them in type order (default 16)")
    parser.add_argument("--out", required=True, help="the C header to write")
    args = parser.parse_args()
    if args.units < 1:
        die("--units must be positive")

    origin_x, origin_z, cells_x, cells_z = land_origin(args.land)
    plants = []
    outside = 0
    for x, z, kind, rotation, scale in read_script(args.script):
        gx = math.floor(x / CELL_UNITS) - origin_x
        gz = math.floor(z / CELL_UNITS) - origin_z
        if not (0 <= gx < cells_x and 0 <= gz < cells_z):
            outside += 1
            continue
        # The firmware's terrain starts at the island's own origin, so the
        # absolute script position moves with it before it is stored.
        x -= origin_x * CELL_UNITS
        z -= origin_z * CELL_UNITS
        yaw = int(round(rotation / (2.0 * math.pi) * TURN)) % TURN
        units = max(1, min(32767, int(round(args.units * scale))))
        plants.append((gz, gx, int(round(x * Q4)), int(round(z * Q4)),
                       yaw, units, kind & 0xFF))
    plants.sort()

    kinds = sorted({plant[6] for plant in plants})
    slot = {kind: i % args.tiles for i, kind in enumerate(kinds)}
    plants = [plant[:6] + (slot[plant[6]], plant[6]) for plant in plants]
    plants.sort()

    lines = [
        "// Generated by tools/convert_plants.py from a level script.",
        "// Not committed: the game's data is not this project's.  See the tool.",
        f"#define TC_PLANT_COUNT {len(plants)}",
        "struct tc_plant {",
        "\tint32_t x, z;",
        "\tuint16_t gx, gz;",
        "\tuint16_t yaw;",
        "\tint16_t units;",
        "\tuint8_t tile, kind;",
        "};",
        "static const struct tc_plant tc_plants[TC_PLANT_COUNT] = {",
    ]
    for gz, gx, x, z, yaw, units, tile, kind in plants:
        lines.append(f"\t{{{x}, {z}, {gx}u, {gz}u, {yaw}u, {units}, "
                     f"{tile}u, {kind}u}},")
    lines.append("};")
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")

    counts = {}
    tiles = set()
    for plant in plants:
        counts[plant[7]] = counts.get(plant[7], 0) + 1
        tiles.add(plant[6])
    sizes = [plant[5] for plant in plants]
    print(f"{out}: {len(plants)} plants, {outside} outside the land, "
          f"{len(counts)} types on {len(tiles)} tiles, "
          f"units {min(sizes)} to {max(sizes)}")


if __name__ == "__main__":
    main()
