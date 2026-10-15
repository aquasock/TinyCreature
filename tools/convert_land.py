#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Convert a Black & White .lnd landscape to TinyCreature's TCL1 terrain file.

The terrain is read as openblack a243c6b2 reads it
(components/lnd/src/LNDFile.cpp) and each vertex is coloured as its terrain
shader would colour it in daylight (src/3D/LandBlock.cpp BuildVertexList,
assets/shaders/fs_terrain.sc): the cell's country, altitude and noise pick a
pair of materials blended by the pair's coefficient, scaled by the bump map's
mean and by clamp(2 * luminosity, 0.5, 1). Each material is reduced to its
mean colour, each triangle to the mean of its three vertices, and the
triangles' colours are fitted to TERRAIN_COLOURS palette entries by median
cut, so the output is deterministic for a given .lnd file.

TCL1, little-endian, is a 32-byte header

    0  "TCL1"           12  origin x, z (u16 each, island cells)
    4  version (1)       16  body bytes
    8  cells x, z (u16)  20  CRC-32 of the body
                         24  palette entries, first index (u16 each)
                         28  0

followed by the body: the palette as u32 0x00RRGGBB, the (x + 1) * (z + 1)
vertex altitudes as u8, row z then column x, and per cell, row-major, a
flags byte (bit 0 split, bit 1 first triangle drawn, bit 2 second triangle
drawn) and the two triangles' palette indices. A triangle whose three
vertices are all water is not drawn, as openblack discards it. The game's
data is copyrighted: write the output under build/, never into the
repository.

    python3 -I tools/convert_land.py <Land1.lnd> <out.tcl>
"""

import argparse
import struct
import sys
import zlib

HEADER = struct.Struct("<I1024s6I")
BLOCK_BYTES = 2520
COUNTRY_BYTES = 3076
MATERIAL_BYTES = 0x20002
NOISE_BYTES = 0x10000
CELLS_PER_BLOCK = 16
TERRAIN_COLOURS = 239
FIRST_COLOUR = 17
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


def mean_colour(texels):
    # B5G5R5A1, normalised per channel as the GPU samples it.
    r = g = b = 0
    for t in texels:
        b += t & 31
        g += (t >> 5) & 31
        r += (t >> 10) & 31
    n = len(texels) * 31
    return (r * 255 / n, g * 255 / n, b * 255 / n)


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


def convert(data):
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

    means = [mean_colour(m) for m in materials]
    bump_scale = sum(bump) * 2 / 255 / len(bump)

    def vertex_colour(x, z):
        altitude, properties, luminosity = cell(x, z)
        country = countries[properties & 15]
        # GetNoise takes a u8vec2, so the cell coordinates wrap at 256.
        n = noise[(x & 255) * 256 + (z & 255)]
        first, second, coefficient = country[(altitude + n) % 256]
        if (first & 255) >= len(means) or (second & 255) >= len(means):
            raise LandError(f"material out of range at {x},{z}")
        a, b = means[first & 255], means[second & 255]
        blend = (coefficient & 255) / 255
        light = min(max(luminosity * 2 / 255, 0.5), 1.0) * bump_scale
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

    # Each cell's two triangles, as LandBlock::BuildVertexList splits it.
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
                if all(water[v] for v in corners):
                    out.append(None)
                    continue
                out.append(tuple(
                    round(sum(colours[v][ch] for v in corners) / 3)
                    for ch in range(3)))
            triangles.append(out)

    weighted = {}
    for t in triangles:
        for colour in (t or [None])[1:]:
            if colour is not None:
                weighted[colour] = weighted.get(colour, 0) + 1
    palette, index = median_cut(weighted, TERRAIN_COLOURS)

    cell_bytes = bytearray()
    drawn = 0
    for t in triangles:
        if t is None:
            cell_bytes += bytes(3)
            continue
        flags = 1 if t[0] else 0
        pair = []
        for bit, colour in ((2, t[1]), (4, t[2])):
            if colour is None:
                pair.append(0)
            else:
                flags |= bit
                drawn += 1
                pair.append(FIRST_COLOUR + index[colour])
        cell_bytes += bytes([flags] + pair)

    body = b"".join(struct.pack("<I", r << 16 | g << 8 | b)
                    for r, g, b in palette)
    body += bytes(altitudes) + bytes(cell_bytes)
    header = struct.pack("<4sI4H2I2HI", b"TCL1", 1, cells_x, cells_z,
                         origin_x, origin_z, len(body), zlib.crc32(body),
                         len(palette), FIRST_COLOUR, 0)
    summary = {
        "blocks": len(blocks), "cells": f"{cells_x}x{cells_z}",
        "origin": f"{origin_x},{origin_z}", "triangles": drawn,
        "colours": len(weighted), "palette": len(palette),
        "bytes": len(header) + len(body),
    }
    return header + body, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("lnd")
    parser.add_argument("out")
    args = parser.parse_args()
    with open(args.lnd, "rb") as f:
        data = f.read()
    try:
        out, summary = convert(data)
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
