#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Load the Tang32 core and run its ten-second landscape/video integrity test.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="${TINYCREATURE_TANG_SOURCE:-$root/build/tang32-src}"
out="${TINYCREATURE_TANG_BUILD:-$root/build/tang32}"
mode="${1:-auto}"

[[ -f "$out/ae350_soc.fs" && -f "$out/ae350_soc.bin" &&
   -f "$out/app/video_test.elf" ]] || {
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

case "$mode" in
one-wire)
    openFPGALoader -b tangmega138k "$out/ae350_soc.fs"
    python3 "$source_dir/tools/load_ae350.py" "$out/app/video_test.elf" \
        --port "${TINYCREATURE_TANG_UART:-/dev/ttyUSB1}" \
        --run-timeout 30 --expect "TinyCreature TANG32 OK"
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
    python3 "$source_dir/tools/load_ae350.py" "$out/app/video_test.elf" \
        --tinytang --port "$port" --run-timeout 30 \
        --expect "TinyCreature TANG32 OK"
    ;;
*)
    echo "usage: $0 [auto|one-wire|two-wire]" >&2
    exit 2
    ;;
esac
