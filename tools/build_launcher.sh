#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the TinyDesk launcher's fixed Celtic scene and collect every card
# artifact in one directory. Nothing reaches the Tang unless --deploy is
# explicitly given.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mode=build
case "${1:-}" in
    "") ;;
    --deploy) mode=deploy ;;
    *) echo "usage: tools/build_launcher.sh [--deploy]" >&2; exit 2 ;;
esac

source_dir="${TINYCREATURE_TANG_SOURCE:-$root/build/tang32-src}"
core_dir="${TINYCREATURE_LAUNCHER_CORE:-$root/build/tang32/seed1-hold}"
out="${TINYCREATURE_LAUNCHER_BUILD:-$root/build/launcher}"
bundle="$out/card"
game="${TINYCREATURE_GAME:-$root/build/wineprefix/drive_c/Program Files (x86)/Lionhead Studios Ltd/Black & White}"
land_source="${TINYCREATURE_LAUNCHER_LAND:-$game/Data/Landscape/Tribal/2Celticgodland.lnd}"
plant_script="${TINYCREATURE_LAUNCHER_SCRIPT:-$game/Scripts/Playgrounds/2- The Celtic God (OB).txt}"
frames="${TINYCREATURE_LAUNCHER_FRAMES:-864000}"

for path in "$source_dir/firmware/rt/rt.mk" "$core_dir/ae350_soc.bin" \
            "$core_dir/ae350_soc.fs" "$land_source" "$plant_script"; do
    [[ -f "$path" ]] || { echo "launcher input missing: $path" >&2; exit 2; }
done

mkdir -p "$out" "$bundle"
scene="$bundle/celtic.tcl"
python3 -I "$root/tools/convert_land.py" "$land_source" "$scene"

make -C "$root/firmware/terrain" TINYNES="$source_dir" BUILD="$out/player" \
    FRAMES="$frames" FABRIC=1 FABRIC_WALK=1 HANDOVER=1 LAUNCHER=1 \
    TILES=1 PLANTS=1 PLANT_ART=1 PLANT_RANDOM=1 PLANT_SEED=1 \
    PLANT_LOD=9600 "PLANT_SCRIPT=$plant_script" "PLANT_LAND=$land_source" \
    clean all

install -m 0644 "$core_dir/ae350_soc.bin" "$bundle/tinycreature.bin"
gzip -9 -n -c "$core_dir/ae350_soc.fs" >"$bundle/tinycreature.fs.gz"
install -m 0644 "$out/player/terrain.elf" "$bundle/tinycreature-play.elf"

echo "TinyCreature launcher bundle:"
sha256sum "$bundle/tinycreature.bin" "$bundle/tinycreature.fs.gz" \
          "$bundle/tinycreature-play.elf" "$scene"

if [[ "$mode" != deploy ]]; then
    echo "Build only; no Tang files were changed. Use --deploy explicitly to install."
    exit 0
fi

tinytang="${TINYTANG_DIR:-$(dirname "$root")/TinyTang}"
port="${TINYTANG_PORT:-/dev/ttyACM0}"
for path in "$tinytang/tools/tinytang_put.py" "$tinytang/tools/tinytang_run.py"; do
    [[ -f "$path" ]] || { echo "TinyTang tool missing: $path" >&2; exit 2; }
done

python3 "$tinytang/tools/tinytang_run.py" --port "$port" --seconds 1 \
    "mkdir /root/media/tinycreature" "echo launcher-directories-ready" >/dev/null
python3 "$tinytang/tools/tinytang_put.py" --port "$port" \
    "$bundle/tinycreature.bin" /root/cores/console138k/tinycreature.bin
python3 "$tinytang/tools/tinytang_put.py" --port "$port" \
    "$bundle/tinycreature.fs.gz" /root/cores/console138k/tinycreature.fs.gz
python3 "$tinytang/tools/tinytang_put.py" --port "$port" \
    "$bundle/tinycreature-play.elf" /root/ae350/tinycreature-play.elf
python3 "$tinytang/tools/tinytang_put.py" --port "$port" \
    "$scene" /root/media/tinycreature/celtic.tcl
echo "Installed the TinyCreature launcher bundle; open TinyCreature in TinyDesk."
