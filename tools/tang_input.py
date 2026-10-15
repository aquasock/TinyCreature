#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A run's mouse input for firmware/terrain.

One report is six bytes: the frame it belongs to and the mouse's HID boot
report -- buttons, dx, dy, wheel. A run's whole sequence is appended to the
TCL2 land file the program asks for with its TinyNES WANT line, and
terrain_host reads the same file, so the board and the PC draw the same
frames however the link was paced. The board applies a report at the frame
it names, so nothing depends on when the bytes arrive.

    tang_input.py pattern <out> <frames> [step]
    tang_input.py append <land.tcl> <input.bin> <out>

`pattern` writes a sequence that turns the camera with the middle button,
slides it with the left one, and rolls the wheel, which is every way the
camera is moved.
"""
import struct
import sys

REPORT = "<BBbbbb"  # frame low, frame high, buttons, dx, dy, wheel
LEFT, MIDDLE = 0x01, 0x04
PHASE = 240  # frames one turn of the pattern takes


def pattern(frames, step):
    """A hand on the mouse: the middle button turning the camera, the left one
    dragging the land, and the wheel rolling in and out, which is every way
    openblack's camera is moved (core-reference OB-005)."""
    out = bytearray()
    for frame in range(frames):
        phase = frame % PHASE
        if phase < 80:
            buttons, dx, dy, wheel = MIDDLE, step, step // 2, 0
        elif phase < 160:
            buttons, dx, dy, wheel = LEFT, step, step, 0
        else:
            roll = 1 if (phase // 20) % 2 == 0 else -1
            buttons, dx, dy, wheel = LEFT, 0, 0, roll
        out += struct.pack(REPORT, frame & 0xFF, (frame >> 8) & 0xFF, buttons,
                           dx, dy, wheel)
    return bytes(out)


def reports(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) % 6:
        raise SystemExit(f"{path}: {len(data)} bytes is not whole reports")
    return data


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__.strip())
    what = argv[1]
    if what == "pattern" and len(argv) in (4, 5):
        frames = int(argv[3], 0)
        step = int(argv[4], 0) if len(argv) == 5 else 4
        data = pattern(frames, step)
        with open(argv[2], "wb") as f:
            f.write(data)
        print(f"{argv[2]}: {frames} reports, {len(data)} bytes, step {step}")
        return 0
    if what == "append" and len(argv) == 5:
        with open(argv[2], "rb") as f:
            land = f.read()
        data = reports(argv[3])
        if not land.startswith(b"TCL2"):
            raise SystemExit(f"{argv[2]} is not a TCL2 land file")
        with open(argv[4], "wb") as f:
            f.write(land + data)
        print(f"{argv[4]}: {len(land)} land bytes, {len(data) // 6} reports")
        return 0
    raise SystemExit(__doc__.strip())


if __name__ == "__main__":
    sys.exit(main(sys.argv))
