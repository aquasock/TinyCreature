#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the 32 MiB Tang core, its 320x180 landscape test application, and the
# terrain program with its PC twin.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="${TINYCREATURE_TANG_SOURCE:-$root/build/tang32-src}"
out="${TINYCREATURE_TANG_BUILD:-$root/build/tang32}"

bash "$root/tools/fetch_tang32.sh"
export APICULA_FORK="${APICULA_FORK:-$(dirname "$root")/apicula-mathieufro}"
TINY_NES_BUILD_DIR="$out" "$source_dir/tools/build_ae350_soc.sh"
make -C "$source_dir/firmware/apps/video_test" BUILD="$out/app" clean all
make -C "$root/firmware/terrain" TINYNES="$source_dir" BUILD="$out/terrain" \
    clean all host

sha256sum "$out/ae350_soc.fs" "$out/ae350_soc.bin" "$out/app/video_test.elf" \
    "$out/terrain/terrain.elf"
echo "Tang32 SRAM image: $out/ae350_soc.fs"
echo "Tang32 card image: $out/ae350_soc.bin"
echo "Tang32 test app:   $out/app/video_test.elf"
echo "Tang32 terrain:    $out/terrain/terrain.elf"
