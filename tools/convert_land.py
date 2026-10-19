#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Convert a Black & White .lnd landscape to TinyCreature's TCL1 terrain file.

The terrain is read as openblack a243c6b2 reads it
(components/lnd/src/LNDFile.cpp) and each vertex is coloured as its terrain
shader would colour it in daylight (src/3D/LandBlock.cpp BuildVertexList,
assets/shaders/fs_terrain.sc): the cell's country, altitude and noise pick a
pair of materials blended by the pair's coefficient; each material is sampled
at the vertex's block-local UV, the bump map is sampled at the same UV, and
the result is scaled by clamp(2 * luminosity, 0.5, 1). Each *vertex* is given
its own colour, and those colours are
fitted to TERRAIN_COLOURS palette entries by median cut weighted by how many
drawn triangles use the vertex, so the output is deterministic for a given
.lnd file. A vertex carries one colour rather than a triangle one mean,
because the renderer interpolates the three corners of each triangle.

TCL2, little-endian, is a 32-byte header

    0  "TCL2"           12  origin x, z (u16 each, island cells)
    4  version (2)       16  body bytes
    8  cells x, z (u16)  20  CRC-32 of the body
                         24  palette entries, first index (u16 each)
                         28  0

followed by the body: the palette as u32 0x00RRGGBB, the (x + 1) * (z + 1)
vertex altitudes as u8, row z then column x, the same vertices' palette
indices as u8 in the same order, and per cell, row-major, a flags byte
(bit 0 split, bit 1 first triangle drawn, bit 2 second triangle drawn). The
corner order of a cell's triangles is the one LNDFile.cpp builds and the
renderer submits: a split cell is (bot-left, top-left, top-right) then
(bot-left, bot-right, top-right), and an unsplit one (top-left, top-right,
bot-right) then (top-left, bot-left, bot-right). A triangle whose three
vertices are all water is not drawn, as openblack discards it. The game's
data is copyrighted: write the output under build/, never into the
repository.

    python3 -I tools/convert_land.py <Land1.lnd> <out.tcl>
"""

import argparse
import struct
import sys
import zlib
from pathlib import Path

HEADER = struct.Struct("<I1024s6I")
BLOCK_BYTES = 2520
COUNTRY_BYTES = 3076
MATERIAL_BYTES = 0x20002
NOISE_BYTES = 0x10000
CELLS_PER_BLOCK = 16
# The palette is 256 entries and the program owns the first nineteen: 0 is
# never drawn by the land, 1 to 8 are the sky's ramp, 9 to 16 the sea's, and
# 17 and 18 are the cursor's two colours. Above them sit two blocks: entries
# 192 to 255 are the art's, one 64-colour palette every tile is quantised into
# and the fabric's textured quads read, and entries 19 to 191 are the land's.
#
# The land takes 173 of the 237 it could rather than all of them, because the
# art needs the top 64 and the land gives them up cheaply. Fitting Land 1's 817
# vertex colours to 192, 176, 173 and 168 entries measures a weighted mean
# error of 2.85, 4.03, 4.06 and 4.22 out of 255 with a worst vertex of 30.3,
# 36.6, 36.6 and 36.6 -- about one and a half per cent of range for the
# nineteen entries the art takes -- where fitting to 160, 128, 96, 64 and 48
# costs 6.19, 7.82, 10.01, 13.13 and 14.37. --colours moves it, and took both
# of those tables.
TERRAIN_COLOURS = 173
FIRST_COLOUR = 19
WATER = 0x10 | 0x40  # hasWater, fullWater
SPLIT = 0x80


class LandError(Exception):
    pass


def read_lnd(data):
    (block_count, lut, material_count, country_count, block_size,
     material_size, country_size, low_res_count) = HEADER.unpack_from(data, 0)
    if (block_size, material_size, country_size) != (
            BLOCK_BYTES, MATERIAL_BYTES, COUNTRY_BYTES):
        raise LandError("non-standard block, material or country size")
    offset = HEADER.size
    for _ in range(low_res_count):
        size = struct.unpack_from("<I", data, offset + 16)[0]
        offset += 20 + size - 4
    blocks = []
    for _ in range(block_count - 1):
        cells = data[offset:offset + 17 * 17 * 8]
        block_x, block_z = struct.unpack_from("<2I", data, offset + 2324)
        blocks.append((block_x, block_z, cells))
        offset += BLOCK_BYTES
    countries = []
    for _ in range(country_count):
        entries = struct.unpack_from("<768I", data, offset + 4)
        countries.append([entries[i:i + 3] for i in range(0, 768, 3)])
        offset += COUNTRY_BYTES
    materials = []
    for _ in range(material_count):
        texels = struct.unpack_from("<65536H", data, offset + 2)
        materials.append(texels)
        offset += MATERIAL_BYTES
    if offset + 2 * NOISE_BYTES > len(data):
        raise LandError("file ends before the noise and bump maps")
    noise = data[offset:offset + NOISE_BYTES]
    bump = data[offset + NOISE_BYTES:offset + 2 * NOISE_BYTES]
    return lut, blocks, countries, materials, noise, bump


def texel_colour(t):
    # B5G5R5A1, normalised per channel as the GPU samples it.
    return (((t >> 10) & 31) * 255 / 31,
            ((t >> 5) & 31) * 255 / 31,
            (t & 31) * 255 / 31)


def median_cut(weighted, count):
    """weighted: {colour: weight}. Returns (palette, {colour: index})."""
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


def fit_error(usage, palette, index):
    """What the fit costs, in RGB: the weighted mean error and the worst one.

    This is the number the palette's size is chosen by. The renderer takes a
    vertex's colour as its palette entry and shades between those, so an entry
    further from the colour it stands for is a gradient that leans the wrong
    way, and the land has no dithering to hide it with.
    """
    total, weight, worst = 0, 0, 0
    for colour, w in usage.items():
        p = palette[index[colour]]
        d2 = sum((colour[ch] - p[ch]) ** 2 for ch in range(3))
        total += d2 * w
        weight += w
        if d2 > worst:
            worst = d2
    mean = (total / weight) ** 0.5 if weight else 0.0
    return mean, worst ** 0.5


def load_material_map(path, meph_dir):
    """{material index: (source, tile, gain)} replaced by Meph tile images."""
    from PIL import Image
    overrides = {}
    images = {}
    for line in Path(path).read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        material, source, tile, gain = line.split("\t")
        material, tile, gain = int(material), int(tile), float(gain)
        if source not in images:
            images[source] = Image.open(Path(meph_dir) / source).convert("RGBA")
        x, y = tile % 16, tile // 16
        piece = images[source].crop((x * 32, y * 32, (x + 1) * 32, (y + 1) * 32))
        piece = piece.point(lambda v: min(255, int(v * gain)) if v else 0)
        overrides[material] = piece.resize((256, 256), Image.NEAREST)
    return overrides


def convert(data, terrain_colours=TERRAIN_COLOURS, overrides=None):
    lut, blocks, countries, materials, noise, bump = read_lnd(data)
    by_index = {}
    for i, (block_x, block_z, cells) in enumerate(blocks):
        if lut[block_x << 5 | block_z] != i + 1:
            raise LandError(f"block {i} at {block_x},{block_z} disagrees "
                            "with the lookup table")
        by_index[i + 1] = cells
    xs = [b[0] for b in blocks]
    zs = [b[1] for b in blocks]
    origin_x, origin_z = min(xs) * 16, min(zs) * 16
    cells_x = (max(xs) - min(xs) + 1) * 16
    cells_z = (max(zs) - min(zs) + 1) * 16

    def cell(x, z):
        # LandIsland::GetCell: (altitude, properties, luminosity); outside
        # the blocks it is k_EmptyCell, all zero but fullWater.
        if x > 511 or z > 511:
            return 0, 0x40, 0
        cells = by_index.get(lut[(x >> 4) << 5 | (z >> 4)])
        if cells is None:
            return 0, 0x40, 0
        o = ((x & 15) * 17 + (z & 15)) * 8
        return cells[o + 4], cells[o + 6], cells[o + 3]


    def sample(material, idx):
        if overrides and material in overrides:
            pixel = overrides[material].getpixel((idx % 256, idx // 256))
            if pixel[3] >= 128:
                return pixel[:3]
        return texel_colour(materials[material][idx])

    def vertex_colour(x, z):
        altitude, properties, luminosity = cell(x, z)
        country = countries[properties & 15]
        # GetNoise takes a u8vec2, so the cell coordinates wrap at 256.
        n = noise[(x & 255) * 256 + (z & 255)]
        first, second, coefficient = country[(altitude + n) % 256]
        if (first & 255) >= len(materials) or (second & 255) >= len(materials):
            raise LandError(f"material out of range at {x},{z}")
        # openblack's terrain UV is the vertex's block-local position over
        # the block (vs_terrain.sc), so for a 16-cell block it is
        # (x & 15) / 16 by (z & 15) / 16; the 256-texel maps therefore step
        # 16 texels a cell.  v_texcoord0 is zx / yx, so x picks the row.
        idx = (x & 15) * 16 * 256 + (z & 15) * 16
        a = sample(first & 255, idx)
        b = sample(second & 255, idx)
        blend = (coefficient & 255) / 255
        light = min(max(luminosity * 2 / 255, 0.5), 1.0) * (bump[idx] * 2.0 / 255.0)
        return tuple(min(255.0, (a[i] + (b[i] - a[i]) * blend) * light)
                     for i in range(3))

    vx, vz = cells_x + 1, cells_z + 1
    altitudes = bytearray(vx * vz)
    water = bytearray(vx * vz)
    colours = [None] * (vx * vz)
    for gz in range(vz):
        for gx in range(vx):
            x, z = origin_x + gx, origin_z + gz
            altitude, properties, _ = cell(x, z)
            altitudes[gz * vx + gx] = altitude
            water[gz * vx + gx] = 1 if properties & WATER else 0
            colours[gz * vx + gx] = vertex_colour(x, z)

    # Each cell's two triangles, as LandBlock::BuildVertexList splits it, as
    # the three grid vertices it joins.
    triangles = []
    for gz in range(cells_z):
        for gx in range(cells_x):
            x, z = origin_x + gx, origin_z + gz
            if lut[(x >> 4) << 5 | (z >> 4)] == 0:
                triangles.append(None)
                continue
            tl, tr = gz * vx + gx, gz * vx + gx + 1
            bl, br = tl + vx, tr + vx
            split = bool(cell(x, z)[1] & SPLIT)
            pair = ((bl, tl, tr), (bl, br, tr)) if split else \
                ((tl, tr, br), (tl, bl, br))
            out = [split]
            for corners in pair:
                out.append(None if all(water[v] for v in corners) else corners)
            triangles.append(out)

    # How often each vertex is drawn, and so weights the palette: a vertex
    # gives one colour to the interpolation, but three of the six triangles
    # around it are seen where it is, and the palette is fitted to what the
    # screen shows. A vertex no triangle uses still needs an entry for the
    # array to be complete, so its weight is one.
    rounded = [tuple(round(c) for c in colours[v]) for v in range(vx * vz)]
    usage = {}
    drawn = 0
    for t in triangles:
        for corners in (t or [None])[1:]:
            if corners is None:
                continue
            drawn += 1
            for v in corners:
                colour = rounded[v]
                usage[colour] = usage.get(colour, 0) + 1
    for colour in rounded:
        usage.setdefault(colour, 1)
    palette, index = median_cut(usage, terrain_colours)
    entry = bytes(FIRST_COLOUR + index[colour] for colour in rounded)
    fit_mean, fit_worst = fit_error(usage, palette, index)

    cell_bytes = bytearray()
    for t in triangles:
        if t is None:
            cell_bytes.append(0)
            continue
        flags = 1 if t[0] else 0
        for bit, corners in ((2, t[1]), (4, t[2])):
            if corners is not None:
                flags |= bit
        cell_bytes.append(flags)

    body = b"".join(struct.pack("<I", r << 16 | g << 8 | b)
                    for r, g, b in palette)
    body += bytes(altitudes) + entry + bytes(cell_bytes)
    header = struct.pack("<4sI4H2I2HI", b"TCL2", 2, cells_x, cells_z,
                         origin_x, origin_z, len(body), zlib.crc32(body),
                         len(palette), FIRST_COLOUR, 0)
    summary = {
        "blocks": len(blocks), "cells": f"{cells_x}x{cells_z}",
        "origin": f"{origin_x},{origin_z}", "triangles": drawn,
        "colours": len(usage), "palette": len(palette),
        "fit": f"{fit_mean:.2f}mean/{fit_worst:.1f}worst",
        "bytes": len(header) + len(body),
    }
    return header + body, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("lnd")
    parser.add_argument("out")
    parser.add_argument("--materials-map",
                        help="tools/ground_map.tsv: replace material textures "
                             "with Meph tiles")
    parser.add_argument("--meph-dir",
                        default=str(Path(__file__).resolve().parent.parent /
                                    "build/tiles/Meph/data/art"),
                        help="Meph art directory for --materials-map")
    parser.add_argument("--colours", type=int, default=TERRAIN_COLOURS,
                        help="palette entries fitted to the land (default "
                             f"{TERRAIN_COLOURS}, the ones the program does not own)")
    args = parser.parse_args()
    with open(args.lnd, "rb") as f:
        data = f.read()
    overrides = None
    if args.materials_map:
        overrides = load_material_map(args.materials_map, args.meph_dir)
    try:
        out, summary = convert(data, args.colours, overrides=overrides)
    except (LandError, struct.error, IndexError) as error:
        print(f"{args.lnd}: {error}", file=sys.stderr)
        return 1
    with open(args.out, "wb") as f:
        f.write(out)
    print(" ".join(f"{k}={v}" for k, v in summary.items()),
          f"crc={zlib.crc32(out):08x}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
