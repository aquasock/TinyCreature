#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Measure what the engine can draw, on the board, in one table: the terrain's
# own cost against how far the camera is, and a ladder of textured
# villager-sized cards. Every configuration is built here and then run through
# tools/run_tang32.sh, so the board and the twin it is checked against are the
# same build -- the rule core-log entry 50 had to learn.
#
#   bash tools/measure_tang32.sh [out.tsv]
#
# The two sweeps are what vary: TINYCREATURE_MEASURE_DIST (Q4 camera distance
# for one pinned card, default "3200 1600 800 320") and
# TINYCREATURE_MEASURE_CARDS (cards on the island, default "64 256 1000 2000").
# TINYCREATURE_MEASURE_SWEEPS picks which run (default "distance cards").
# The card is a villager by default: CARD_UNITS 80 is half a cell. Geometry
# and art are TINYCREATURE_MEASURE_UNITS (80), TINYCREATURE_MEASURE_DEPTH (8)
# and TINYCREATURE_MEASURE_SHEET (empty, the Makefile's Meph sheet).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out="${1:-$root/build/measure.tsv}"
sweeps="${TINYCREATURE_MEASURE_SWEEPS-distance cards}"
dist="${TINYCREATURE_MEASURE_DIST-3200 1600 800 320}"
cards="${TINYCREATURE_MEASURE_CARDS-64 256 1000 2000}"
units="${TINYCREATURE_MEASURE_UNITS:-80}"
depth="${TINYCREATURE_MEASURE_DEPTH:-8}"
sheet="${TINYCREATURE_MEASURE_SHEET:-}"
src="${TINYCREATURE_TANG_SOURCE:-$root/build/tang32-src}"
build="$root/build/tang32/terrain"

printf 'sweep\tvalue\ttris\tpixels\tcells\tdraw_us\tmax_us\tperiod_us\tstalls\tlate\tcrc\twhy\n' >"$out"

run_one() { # sweep value <make args...>
    local sweep="$1" value="$2"; shift 2
    local sheet_arg=()
    [[ -n "$sheet" ]] && sheet_arg=(TILES_SHEET="$sheet")
    echo "== $sweep $value ==" >&2
    make -s -C "$root/firmware/terrain" TINYNES="$src" BUILD="$build" \
        CARDS=0 TILES=1 READOUT=0 CARD_TEX=1 CARD_UNITS="$units" CARD_DEPTH="$depth" \
        CARD_EDGE="${TINYCREATURE_CARD_EDGE:-0}" \
        PIN_X=0xffff PIN_Z=0xffff "${sheet_arg[@]}" "$@" clean all host >/dev/null
    local log line why
    # The board's own output is kept whole, so a run that fails its cadence
    # check says so in the table rather than leaving an unexplained dash.
    log="${TMPDIR:-/tmp}/measure-$sweep-$value.log"
    TINYCREATURE_CARDS=0 TINYCREATURE_TILES=1 bash "$root/tools/run_tang32.sh" two-wire terrain >"$log" 2>&1 || true
    line=$(grep -o 'TinyCreature TERRAIN OK .*' "$log" | head -1 || true)
    why=-
    if [ -z "$line" ]; then
        why=$(grep -o 'BAD TINYCREATURE [A-Z]*' "$log" | head -1 || true)
        why=${why:-$(grep -o 'FAIL:.*' "$log" | head -1 || true)}
        why=${why:--}
    else
        why=ok
    fi
    if [ -z "$line" ]; then
        printf '%s\t%s\t-\t-\t-\t-\t-\t-\t-\t-\t-\t%s\n' "$sweep" "$value" "$why" >>"$out"
        return
    fi
    field() { echo "$line" | grep -o "$1=[0-9a-f]*" | head -1 | cut -d= -f2; }
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sweep" "$value" "$(field TRIS)" "$(field PIXELS)" "$(field CELLS)" \
        "$(field DRAW)" "$(field MAX)" "$(field PERIOD)" "$(field STALLS)" \
        "$(field LATE)" "$(field CRC)" "$why" >>"$out"
}

for sweep in $sweeps; do
    case "$sweep" in
    distance)
        for d in $dist; do
            run_one distance "$d" CARDS=0 PIN_X=80 PIN_Z=90 PIN_DIST="$d"
        done
        ;;
    cards)
        for n in $cards; do
            run_one cards "$n" CARDS=1 CARDS_N="$n" PIN_DIST=3200
        done
        ;;
    *)
        echo "unknown sweep: $sweep" >&2
        exit 2
        ;;
    esac
done
cat "$out"
