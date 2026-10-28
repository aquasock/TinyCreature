#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out="$root/build/tests/launcher"
mkdir -p "$out"

cc -std=c11 -Wall -Wextra -Werror -Ifirmware/terrain \
    tests/launcher_tb.c -o "$out/launcher_tb"
"$out/launcher_tb"
echo "launcher keyboard: PASS"
