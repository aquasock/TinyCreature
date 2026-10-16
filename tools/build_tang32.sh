#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the 32 MiB Tang core with TinyCreature's raster unit, its 320x180
# landscape test application, and the terrain program, for the fabric and
# in software, with its PC twin.
#
# The core is synthesised once and placed and routed with eight seeds in
# parallel (TINYCREATURE_SEEDS replaces the list). A seed is clean when
# TinyNES's build script accepts it: both clocks meet timing, the AE350
# clock hop and pixel-clock bridge are as measured, and the block RAM rules
# hold. Of the clean seeds the one with the fastest bus clock is kept, then
# the fastest pixel clock, then the first listed; build/tang32/seeds.tsv
# records every seed's result.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="${TINYCREATURE_TANG_SOURCE:-$root/build/tang32-src}"
out="${TINYCREATURE_TANG_BUILD:-$root/build/tang32}"
read -r -a seeds <<<"${TINYCREATURE_SEEDS:-1 2 3 4 5 6 7 8}"

bash "$root/tools/fetch_tang32.sh"
export APICULA_FORK="${APICULA_FORK:-$(dirname "$root")/apicula-mathieufro}"
export TINY_NES_EXTRA_SV="$root/fpga/raster.sv"
build_soc="$source_dir/tools/build_ae350_soc.sh"

mkdir -p "$out"
rm -rf "$out/seeds"
mkdir -p "$out/seeds"
echo "Synthesis"
TINY_NES_STAGE=synth TINY_NES_BUILD_DIR="$out/seeds/synth" "$build_soc" \
    >"$out/seeds/synth.out" 2>&1 || {
        tail -40 "$out/seeds/synth.out" >&2
        exit 1
    }
echo "Placing and routing seeds ${seeds[*]}"
for seed in "${seeds[@]}"; do
    (
        status=0
        TINY_NES_SEED="$seed" TINY_NES_NETLIST="$out/seeds/synth/ae350_soc.json" \
            TINY_NES_BUILD_DIR="$out/seeds/$seed" "$build_soc" \
            >"$out/seeds/$seed.out" 2>&1 || status=$?
        echo "$status" >"$out/seeds/$seed.status"
    ) &
done
wait

# One line per seed: seed, clean, bus and pixel clock Fmax in MHz.
python3 -I - "$out/seeds" "${seeds[@]}" >"$out/seeds.tsv" <<'PY'
import json, pathlib, sys
base = pathlib.Path(sys.argv[1])
print("seed\tclean\tbus_mhz\tpixel_mhz")
for seed in sys.argv[2:]:
    clean = (base / f"{seed}.status").read_text().strip() == "0"
    bus = pixel = 0.0
    try:
        fmax = json.loads((base / seed / "timing.json").read_text())["fmax"]
        bus = fmax["bus_clk"]["achieved"]
        pixel = min(t["achieved"] for t in fmax.values()
                    if abs(t["constraint"] - 74.25) < 0.05)
    except (OSError, KeyError, ValueError):
        clean = False
    print(f"{seed}\t{'yes' if clean else 'no'}\t{bus:.2f}\t{pixel:.2f}")
PY
cat "$out/seeds.tsv"
best=$(awk -F'\t' 'NR > 1 && $2 == "yes" {
        if (!found || $3 > bus || ($3 == bus && $4 > pix)) {
            found = 1; seed = $1; bus = $3; pix = $4
        }
    } END { if (found) print seed }' "$out/seeds.tsv")
if [[ -z "$best" ]]; then
    echo "No seed of ${seeds[*]} met every check" >&2
    exit 1
fi
echo "Seed $best kept"
for f in ae350_soc.fs ae350_soc.bin ae350_soc-routed.json ae350_soc.json \
         timing.json nextpnr.log pack.log; do
    cp "$out/seeds/$best/$f" "$out/$f"
done
cp "$out/seeds/synth/synth.log" "$out/synth.log"
echo "$best" >"$out/seed"

make -C "$source_dir/firmware/apps/video_test" BUILD="$out/app" clean all
# CARDS reaches both the program and the host twin from one switch, so that a
# run with cards is always compared against a twin that drew them too.
make -C "$root/firmware/terrain" TINYNES="$source_dir" BUILD="$out/terrain" \
    CARDS="${TINYCREATURE_CARDS:-0}" TILES="${TINYCREATURE_TILES:-0}" \
    READOUT="${TINYCREATURE_READOUT:-1}" \
    CARD_TEX="${TINYCREATURE_CARD_TEX:-0}" \
    CARD_COLUMN_PX="${TINYCREATURE_CARD_COLUMN_PX:-3}" \
    CARD_YAW="${TINYCREATURE_CARD_YAW:-0}" CARD_DEPTH="${TINYCREATURE_CARD_DEPTH:-48}" \
    PIN_X="${TINYCREATURE_PIN_X:-0xffff}" PIN_Z="${TINYCREATURE_PIN_Z:-0xffff}" \
    PIN_DIST="${TINYCREATURE_PIN_DIST:-3200}" PIN_PITCH="${TINYCREATURE_PIN_PITCH:-2731}" \
    clean all host
make -C "$root/firmware/terrain" TINYNES="$source_dir" FABRIC=0 \
    CARDS="${TINYCREATURE_CARDS:-0}" TILES="${TINYCREATURE_TILES:-0}" \
    READOUT="${TINYCREATURE_READOUT:-1}" \
    CARD_TEX="${TINYCREATURE_CARD_TEX:-0}" \
    CARD_COLUMN_PX="${TINYCREATURE_CARD_COLUMN_PX:-3}" \
    CARD_YAW="${TINYCREATURE_CARD_YAW:-0}" CARD_DEPTH="${TINYCREATURE_CARD_DEPTH:-48}" \
    PIN_X="${TINYCREATURE_PIN_X:-0xffff}" PIN_Z="${TINYCREATURE_PIN_Z:-0xffff}" \
    PIN_DIST="${TINYCREATURE_PIN_DIST:-3200}" PIN_PITCH="${TINYCREATURE_PIN_PITCH:-2731}" \
    BUILD="$out/terrain-soft" clean all

sha256sum "$out/ae350_soc.fs" "$out/ae350_soc.bin" "$out/app/video_test.elf" \
    "$out/terrain/terrain.elf" "$out/terrain-soft/terrain.elf"
echo "Tang32 SRAM image: $out/ae350_soc.fs (seed $best)"
echo "Tang32 card image: $out/ae350_soc.bin"
echo "Tang32 test app:   $out/app/video_test.elf"
echo "Tang32 terrain:    $out/terrain/terrain.elf (fabric)"
echo "                   $out/terrain-soft/terrain.elf (software)"
