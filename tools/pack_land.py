#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Pack a TCL2 land for fpga/raster.sv's land store.

The fabric keeps a vertex as one 16-bit word, {colour, altitude}, and a
cell's three flag bits as one nibble, two cells a byte. The upload takes
two vertex words or eight nibbles a 32-bit write, so this writes a count
line and then the words:

    <vertex words> <flag words>
    <vertex word 0>
    ...
    <flag word 0>
    ...

Vertex words pair consecutive grid vertices, low word first; an odd final
vertex leaves the high half zero. Flag words pack cells in row-major order,
four bits each, low nibble first. Only bits 0 to 2 of a cell's flags are
kept: bit 0 the split, bit 1 the first triangle, bit 2 the second.

The land is the user's converted data and is never committed.
"""
import struct
import sys
import zlib


def main(argv):
    if len(argv) != 3:
        sys.exit("usage: pack_land.py <land.tcl> <land.hex>")
    data = open(argv[1], "rb").read()
    if len(data) < 32 or data[:4] != b"TCL2":
        sys.exit("not a TCL2 land")
    version, = struct.unpack_from("<I", data, 4)
    if version != 2:
        sys.exit("TCL2 version %d, expected 2" % version)
    cells_x, cells_z, origin_x, origin_z = struct.unpack_from("<HHHH", data, 8)
    body, crc, colours, first = struct.unpack_from("<IIHH", data, 16)
    if body != len(data) - 32:
        sys.exit("body length %d, file has %d" % (body, len(data) - 32))
    if zlib.crc32(data[32:]) != crc:
        sys.exit("body CRC does not match")
    vx, vz = cells_x + 1, cells_z + 1
    vertices, cells = vx * vz, cells_x * cells_z
    if body != 4 * colours + 2 * vertices + cells:
        sys.exit("body does not match %d colours, %d vertices, %d cells"
                 % (colours, vertices, cells))
    off = 32 + 4 * colours
    altitude = data[off:off + vertices]
    off += vertices
    colour = data[off:off + vertices]
    off += vertices
    flags = data[off:off + cells]

    vwords = []
    for i in range(0, vertices, 2):
        w = altitude[i] | colour[i] << 8
        if i + 1 < vertices:
            w |= (altitude[i + 1] | colour[i + 1] << 8) << 16
        vwords.append(w)
    fwords = []
    for i in range(0, cells, 8):
        w = 0
        for k in range(8):
            if i + k < cells:
                w |= (flags[i + k] & 7) << (4 * k)
        fwords.append(w)

    with open(argv[2], "w") as f:
        f.write("%d %d\n" % (len(vwords), len(fwords)))
        for w in vwords + fwords:
            f.write("%08x\n" % w)
    print("land %dx%d: %d vertices, %d cells, %d vertex words, %d flag words"
          % (cells_x, cells_z, vertices, cells, len(vwords), len(fwords)))


if __name__ == "__main__":
    main(sys.argv)
