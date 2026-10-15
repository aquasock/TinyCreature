#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="${TINYCREATURE_TANG_SOURCE:-$root/build/tang32-src}"
out="$root/build/tang32-video-tb"
bash "$root/tools/fetch_tang32.sh"
mkdir -p "$out"
iverilog -g2012 -s tang32_video_tb -o "$out/video_tb" \
    "$root/tests/tang32_video_tb.sv" "$source_dir/fpga/ae350_soc/video.sv"
vvp "$out/video_tb"
iverilog -g2012 -s tang32_sdram_video_tb -o "$out/sdram_video_tb" \
    "$root/tests/tang32_sdram_video_tb.sv" \
    "$source_dir/tests/sdram_model.sv" \
    "$source_dir/fpga/ae350_soc/ahb_sdram.sv"
vvp "$out/sdram_video_tb"
