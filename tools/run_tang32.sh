#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Load the Tang32 core and run one of its programs:
#   video         the ten-second landscape/video integrity test (the default)
#   terrain       Land 1 from the user's own game, converted here, drawn
#                 by the fabric rasterizer and checked frame for frame
#                 against terrain_host
#   terrain-soft  the same frames drawn by the AE350 in software, for
#                 comparison
# TINYCREATURE_LND picks another .lnd for terrain.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="${TINYCREATURE_TANG_SOURCE:-$root/build/tang32-src}"
out="${TINYCREATURE_TANG_BUILD:-$root/build/tang32}"
game="$root/build/wineprefix/drive_c/Program Files (x86)/Lionhead Studios Ltd/Black & White"
mode=auto
program=video
for arg in "$@"; do
    case "$arg" in
    auto|one-wire|two-wire) mode="$arg" ;;
    video|terrain|terrain-soft) program="$arg" ;;
    *)
        echo "usage: $0 [auto|one-wire|two-wire] [video|terrain|terrain-soft]" >&2
        exit 2
        ;;
    esac
done

case "$program" in
video)
    elf="$out/app/video_test.elf"
    expect="TinyCreature TANG32 OK"
    file_args=()
    run_timeout=30
    ;;
terrain|terrain-soft)
    elf="$out/$program/terrain.elf"
    expect="TinyCreature TERRAIN OK"
    lnd="${TINYCREATURE_LND:-$game/Data/Landscape/Land1.lnd}"
    [[ -f "$lnd" ]] || {
        echo "Land file missing: $lnd (set TINYCREATURE_LND)" >&2
        exit 2
    }
    [[ -x "$out/terrain/host/terrain_host" ]] || {
        echo "terrain_host is missing; run tools/build_tang32.sh" >&2
        exit 2
    }
    land="$root/build/land/$(basename "${lnd%.*}").tcl"
    mkdir -p "$(dirname "$land")"
    python3 -I "$root/tools/convert_land.py" "$lnd" "$land"
    # A run's recorded mouse input rides in the land file's tail, where the
    # program looks for it after the TCL2 header says where the land ends;
    # the PC twin is given the same reports on their own.
    loaded="$land"
    input="${TINYCREATURE_INPUT:-}"
    if [[ -n "$input" ]]; then
        loaded="$root/build/land/$(basename "${lnd%.*}")-input.tcl"
        python3 -I "$root/tools/tang_input.py" append "$land" "$input" "$loaded"
    fi
    host_line=$(TC_INPUT="$input" "$out/terrain/host/terrain_host" "$land")
    echo "$host_line"
    file_args=(--file "$loaded")
    run_timeout=120
    ;;
esac

[[ -f "$out/ae350_soc.fs" && -f "$out/ae350_soc.bin" && -f "$elf" ]] || {
    echo "Tang32 artifacts are missing; run tools/build_tang32.sh" >&2
    exit 2
}
if [[ "$mode" == auto ]]; then
    if [[ -e "${TINYCREATURE_TANG_UART:-/dev/ttyUSB1}" ]]; then
        mode=one-wire
    elif [[ -e "${TINYTANG_PORT:-/dev/ttyACM0}" ]]; then
        mode=two-wire
    else
        echo "No Tang serial port found (/dev/ttyUSB1 or /dev/ttyACM0)" >&2
        exit 2
    fi
fi

log="$out/run-$program.log"
case "$mode" in
one-wire)
    openFPGALoader -b tangmega138k "$out/ae350_soc.fs"
    python3 "$source_dir/tools/load_ae350.py" "$elf" "${file_args[@]}" \
        --port "${TINYCREATURE_TANG_UART:-/dev/ttyUSB1}" \
        --run-timeout "$run_timeout" --expect "$expect" | tee "$log"
    ;;
two-wire)
    tinytang="${TINYTANG_DIR:-$(dirname "$root")/TinyTang}"
    port="${TINYTANG_PORT:-/dev/ttyACM0}"
    remote=/root/cores/console138k/tinycreature-tang32.bin
    [[ -f "$tinytang/tools/tinytang_put.py" ]] || {
        echo "TinyTang tools missing in $tinytang" >&2
        exit 2
    }
    python3 "$tinytang/tools/tinytang_run.py" --port "$port" --seconds 1 \
        "mkdir -p /root/cores/console138k"
    python3 "$tinytang/tools/tinytang_put.py" --port "$port" \
        "$out/ae350_soc.bin" "$remote"
    python3 "$tinytang/tools/tinytang_run.py" --port "$port" --wait 120 --seconds 1 \
        "tangload $remote" "echo tinycreature: core-loaded"
    python3 "$source_dir/tools/load_ae350.py" "$elf" "${file_args[@]}" \
        --tinytang --port "$port" --run-timeout "$run_timeout" \
        --expect "$expect" | tee "$log"
    ;;
esac

if [[ "$program" == terrain* ]]; then
    # The board must draw what this PC drew from the same file.
    field() { tr ' ' '\n' <<<"$1" | sed -n "s/^$2=//p"; }
    board_line=$(grep -a "^$expect" "$log")
    # The camera fields are in both lines because both are the same program:
    # comparing them checks the readout's own numbers, where the CRC checks the
    # pixels it drew from them.
    for name in LAND FRAMES TRIS PIXELS INPUT CRC CAMFOCUS CAMEYE CAMTURN; do
        if [[ "$(field "$board_line" "$name")" != "$(field "$host_line" "$name")" ]]; then
            echo "FAIL: board $name=$(field "$board_line" "$name")," \
                 "host $name=$(field "$host_line" "$name")"
            exit 1
        fi
    done
    echo "terrain: board frames match terrain_host"
fi
