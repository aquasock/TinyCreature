#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Simulate fpga/raster.sv on two real Land 1 frames from the user's game,
# drawn by terrain_host, and require the same pixels from the fabric.
# TINYCREATURE_LND picks another .lnd; the frames come from build/land/.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
game="$root/build/wineprefix/drive_c/Program Files (x86)/Lionhead Studios Ltd/Black & White"
lnd="${TINYCREATURE_LND:-$game/Data/Landscape/Land1.lnd}"
out="$root/build/raster-tb"
mkdir -p "$out" "$root/build/land"
land="$root/build/land/$(basename "${lnd%.*}").tcl"
frame0="${TINYCREATURE_RASTER_FRAME0:-0}"
frame1="${TINYCREATURE_RASTER_FRAME1:-75}"
printf -v dump0 'f%04d' "$frame0"
printf -v dump1 'f%04d' "$frame1"

python3 -I "$root/tools/convert_land.py" "$lnd" "$land"
make -s -C "$root/firmware/terrain" BUILD="$out" \
    CARDS="${TINYCREATURE_CARDS:-0}" \
    CARDS_N="${TINYCREATURE_CARDS_N:-64}" \
    TREES="${TINYCREATURE_TREES:-0}" \
    TREES_N="${TINYCREATURE_TREES_N:-16}" \
    TILES="${TINYCREATURE_TILES:-0}" \
    TREE_ART="${TINYCREATURE_TREE_ART:-0}" \
    CARD_TEX="${TINYCREATURE_CARD_TEX:-0}" \
    CARD_UNITS="${TINYCREATURE_CARD_UNITS:-480}" \
    CARD_YAW="${TINYCREATURE_CARD_YAW:-0}" \
    CARD_DEPTH="${TINYCREATURE_CARD_DEPTH:-48}" \
    CARD_EDGE="${TINYCREATURE_CARD_EDGE:-0}" clean host
# The defaults retain the two established views: frame 0 sees the whole
# island; frame 75 is close in, with triangles cut at the near plane. The
# overrides let a new primitive be checked at other points around the orbit.
"$out/host/terrain_host" "$land" 600 "$out/f" "$frame0" "$frame1"
# What the fabric's checksum must produce, from the same bytes: the standard
# CRC-32 terrain_host uses, per frame and chained across both.
crcs=$(python3 -I - "$out/$dump0.fb" "$out/$dump1.fb" <<'PY'
import sys, zlib
def load(p):
    return bytes(int(x, 16) for x in open(p).read().split())
a, b = load(sys.argv[1]), load(sys.argv[2])
print("0x%08x 0x%08x %d %d" % (zlib.crc32(a), zlib.crc32(a + b),
                                sum(1 for x in a if x), sum(1 for x in b if x)))
PY
)
read -r crc0 crc01 nz0 nz1 <<<"$crcs"
iverilog -g2012 -s raster_tb -o "$out/raster_tb" \
    "$root/tests/raster_tb.sv" "$root/fpga/raster.sv"
vvp -n "$out/raster_tb" +cmd0="$out/$dump0.cmd" +cmd1="$out/$dump1.cmd" \
    +fb0="$out/$dump0.fb" +fb1="$out/$dump1.fb" +crc0="$crc0" +crc01="$crc01" \
    +pal="$out/fpal.hex" +lut="$out/flut.hex" +tiles="$out/ftiles.hex" \
    +nz0="$nz0" +nz1="$nz1" +dump="$out/wrong.txt" \
    +framedump="$out/$dump0.sim.fb" \
    | tee "$out/raster_tb.log"
grep -q '^PASS raster_tb' "$out/raster_tb.log"
