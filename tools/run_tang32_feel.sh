#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the terrain program for the board's mouse, load it, and hand the link
# back so the mouse can drive it. One command a tuning change: edit the TC_*
# constants in firmware/terrain/terrain.h or the frame hold in
# firmware/terrain/main.c, run this, and drive.
#
# The loader holds the board's link for as long as its port is open, and the
# board cannot send input frames while it does (core-reference TANG-001), so
# the program is loaded with a short window and the host then lets go of the
# port; the program itself runs on afterwards. Its report line comes when the
# run ends, which is why the frame count is large by default.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="${TINYCREATURE_TANG_SOURCE:-$root/build/tang32-src}"
out="${TINYCREATURE_TANG_BUILD:-$root/build/tang32}"
game="$root/build/wineprefix/drive_c/Program Files (x86)/Lionhead Studios Ltd/Black & White"
lnd="${TINYCREATURE_LND:-$game/Data/Landscape/Land1.lnd}"
frames="${TINYCREATURE_FEEL_FRAMES:-200000}"
handover="${TINYCREATURE_FEEL_HANDOVER:-20}"
port="${TINYTANG_PORT:-/dev/ttyACM0}"
build="$root/build/feel"
tinytang="${TINYTANG_DIR:-$(dirname "$root")/TinyTang}"
remote=/root/cores/console138k/tinycreature-tang32.bin

[[ -f "$lnd" ]] || {
    echo "Land file missing: $lnd (set TINYCREATURE_LND)" >&2
    exit 2
}
land="$root/build/land/$(basename "${lnd%.*}").tcl"
mkdir -p "$(dirname "$land")"
python3 -I "$root/tools/convert_land.py" "$lnd" "$land"

[[ -f "$out/ae350_soc.bin" ]] || {
    echo "Tang32 core missing; run tools/build_tang32.sh" >&2
    exit 2
}
[[ -f "$tinytang/tools/tinytang_put.py" ]] || {
    echo "TinyTang tools missing in $tinytang" >&2
    exit 2
}

echo "Building for $frames frames"
make -C "$root/firmware/terrain" TINYNES="$source_dir" BUILD="$build" \
    FRAMES="$frames" CARDS="${TINYCREATURE_CARDS:-0}" \
    CARDS_N="${TINYCREATURE_CARDS_N:-64}" \
    TREES="${TINYCREATURE_TREES:-0}" \
    TREES_N="${TINYCREATURE_TREES_N:-16}" \
    TILES="${TINYCREATURE_TILES:-0}" \
    TREE_ART="${TINYCREATURE_TREE_ART:-0}" \
    READOUT="${TINYCREATURE_READOUT:-1}" \
    PIN_X="${TINYCREATURE_PIN_X:-0xffff}" \
    PIN_Z="${TINYCREATURE_PIN_Z:-0xffff}" \
    PIN_DIST="${TINYCREATURE_PIN_DIST:-3200}" \
    PIN_PITCH="${TINYCREATURE_PIN_PITCH:-2731}" \
    CARD_UNITS="${TINYCREATURE_CARD_UNITS:-480}" \
    CARD_YAW="${TINYCREATURE_CARD_YAW:-0}" \
    CARD_DEPTH="${TINYCREATURE_CARD_DEPTH:-48}" \
    CARD_COLUMN_PX="${TINYCREATURE_CARD_COLUMN_PX:-3}" \
    CARD_TEX="${TINYCREATURE_CARD_TEX:-0}" clean all >/dev/null

echo "Loading the core"
python3 "$tinytang/tools/tinytang_run.py" --port "$port" --seconds 1 \
    "mkdir -p /root/cores/console138k" >/dev/null
python3 "$tinytang/tools/tinytang_put.py" --port "$port" \
    "$out/ae350_soc.bin" "$remote" >/dev/null
python3 "$tinytang/tools/tinytang_run.py" --port "$port" --wait 120 --seconds 1 \
    "tangload $remote" "echo core-loaded" >/dev/null

echo "Running; the link is handed back after ${handover}s"
# The loader is expected to give up on the run and exit: leaving is the point.
python3 "$source_dir/tools/load_ae350.py" "$build/terrain.elf" --file "$land" \
    --tinytang --port "$port" --run-timeout "$handover" \
    --expect "TinyCreature TERRAIN OK" || true

cat <<'EOF'
The board's mouse is driving the camera: middle-drag turns and tilts it, left-drag
slides the land, the wheel moves in and out. Where the eye and its focus are, in
the island's cells, and the bearing in degrees, are drawn along the bottom of the
frame. Change the TC_* constants in firmware/terrain/terrain.h and run this
again to try another feel.
EOF
