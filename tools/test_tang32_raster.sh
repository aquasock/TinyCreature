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

python3 -I "$root/tools/convert_land.py" "$lnd" "$land"
make -s -C "$root/firmware/terrain" BUILD="$out" host
# Frame 0 sees the whole island; frame 75 is close in, with triangles cut
# at the near plane.
"$out/host/terrain_host" "$land" 600 "$out/f" 0 75
iverilog -g2012 -s raster_tb -o "$out/raster_tb" \
    "$root/tests/raster_tb.sv" "$root/fpga/raster.sv"
vvp -n "$out/raster_tb" +cmd0="$out/f0000.cmd" +cmd1="$out/f0075.cmd" \
    +fb0="$out/f0000.fb" +fb1="$out/f0075.fb" | tee "$out/raster_tb.log"
grep -q '^PASS raster_tb' "$out/raster_tb.log"
