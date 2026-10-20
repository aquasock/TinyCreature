#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reproduce terrain.c's cell walk and check it against a CPU trace.

terrain_host writes a trace when TC_CELL_TRACE names a file:

    T <cells_x> <cells_z> <blocks_x> <blocks_z> <cx> <cz>
    B <block shown bits, 32 a word>
    C <gx> <gz> <front> <tl> <tr> <bl> <br>

This reads the same TCL2 land and the trace, walks the cells in
terrain.c's order -- rows farthest from the camera row first, and in each
row the columns farthest from its column first -- and compares every
drawn cell and its four vertex-store slot keys. It is the model the
fabric front end will be written against.
"""
import struct
import sys


def load_land(path):
    data = open(path, "rb").read()
    if len(data) < 32 or data[:4] != b"TCL2":
        sys.exit("not a TCL2 land: %s" % path)
    body = struct.unpack_from("<I", data, 16)[0]
    if body != len(data) - 32:
        sys.exit("TCL2 body length does not match")
    colours = struct.unpack_from("<H", data, 24)[0]
    cells_x, cells_z = struct.unpack_from("<HH", data, 8)
    vx, vz = cells_x + 1, cells_z + 1
    off = 32 + 4 * colours + 2 * vx * vz
    return cells_x, cells_z, data[off:off + cells_x * cells_z]


def farther(lo, hi, c):
    # terrain.c's farther(): the end farther from c, moving toward it.
    a, b = abs(c - lo), abs(hi - c)
    if a >= b:
        return lo, lo + 1, hi
    return hi, lo, hi - 1


def main(argv):
    if len(argv) != 3:
        sys.exit("usage: land_walk.py <land.tcl> <cells.txt>")
    cx = cz = None
    blocks_x = blocks_z = 0
    shown = []
    traced = []
    for line in open(argv[2]):
        f = line.split()
        if not f:
            continue
        if f[0] == "T":
            cells_x, cells_z, blocks_x, blocks_z, cx, cz = map(int, f[1:])
        elif f[0] == "B":
            shown.append(int(f[1], 16))
        elif f[0] == "C":
            traced.append(tuple(map(int, f[1:])))
    if cx is None:
        sys.exit("trace has no T header")
    lx, lz, flags = load_land(argv[1])
    if (lx, lz) != (cells_x, cells_z):
        sys.exit("land is %dx%d, trace is %dx%d" % (lx, lz, cells_x, cells_z))

    def is_shown(b):
        return (shown[b >> 5] >> (b & 31)) & 1

    expected = []
    zlo, zhi = 0, cells_z - 1
    while zlo <= zhi:
        gz, zlo, zhi = farther(zlo, zhi, cz)
        front = 0 if gz < cz else 1
        row0 = (front << 9) | ((gz & 1) << 8)
        row1 = (front << 9) | (((gz + 1) & 1) << 8)
        xlo, xhi = 0, cells_x - 1
        while xlo <= xhi:
            gx, xlo, xhi = farther(xlo, xhi, cx)
            if not is_shown((gz >> 4) * blocks_x + (gx >> 4)):
                continue
            if not (flags[gz * cells_x + gx] & 6):
                continue
            expected.append((gx, gz, front,
                             row0 | (gx & 255), row0 | ((gx + 1) & 255),
                             row1 | (gx & 255), row1 | ((gx + 1) & 255)))

    if len(expected) != len(traced):
        print("FAIL: model has %d cells, CPU trace has %d"
              % (len(expected), len(traced)))
        for i in range(min(len(expected), len(traced))):
            if expected[i] != traced[i]:
                print("  first difference at %d: model %s, CPU %s"
                      % (i, expected[i], traced[i]))
                break
        return 1
    for i, (a, b) in enumerate(zip(expected, traced)):
        if a != b:
            print("FAIL: cell %d: model %s, CPU %s" % (i, a, b))
            return 1
    print("cell walk: %d drawn cells match the CPU trace" % len(expected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
