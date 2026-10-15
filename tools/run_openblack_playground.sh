#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the stripped landscape playground at a low default resolution.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
binary="$root/build/openblack-playground/bin/Release/openblack"
bundled_game="$root/build/wineprefix/drive_c/Program Files (x86)/Lionhead Studios Ltd/Black & White"
game_dir=${BLACK_WHITE_DIR:-$bundled_game}

if [[ $# -gt 0 && "$1" != -* ]]; then
    game_dir=$1
    shift
fi
if [[ ! -x "$binary" ]]; then
    echo "playground binary is missing; run tools/build_openblack_playground.sh first" >&2
    exit 1
fi
if [[ ! -d "$game_dir/Data" || ! -d "$game_dir/Scripts" ]]; then
    echo "usage: $0 [Black & White install directory] [openblack options]" >&2
    echo "the game directory must contain Data/ and Scripts/: $game_dir" >&2
    exit 2
fi

exec "$binary" --playground -g "$game_dir" \
    -W "${OPENBLACK_WIDTH:-640}" -H "${OPENBLACK_HEIGHT:-360}" \
    -u "${OPENBLACK_UI_SCALE:-0.75}" -V -l stdout -L all=info "$@"
