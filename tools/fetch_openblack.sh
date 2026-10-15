#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fetches openblack (GPL-3.0), the open-source reimplementation of Black &
# White's engine, at a pinned commit into third_party/openblack, which git
# ignores, with its vcpkg submodule at the commit openblack pins.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
url=https://github.com/openblack/openblack.git
commit=a243c6b2fbd251b5d54c1b5f09f59ded9b3b4c81
dir="${OPENBLACK_DIR:-$root/third_party/openblack}"

if [[ ! -d "$dir/.git" ]]; then
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" remote add origin "$url"
fi
full=$(git -C "$dir" rev-parse -q --verify "$commit^{commit}" || true)
if [[ -z "$full" ]]; then
    git -C "$dir" fetch -q origin master
    full=$(git -C "$dir" rev-parse "$commit^{commit}")
fi
if [[ "$(git -C "$dir" rev-parse -q --verify HEAD || true)" != "$full" ]]; then
    git -C "$dir" checkout -q --detach "$full"
fi
git -C "$dir" submodule update -q --init --recursive
[[ -z "$(git -C "$dir" status --porcelain)" ]] || {
    echo "openblack: $dir has local changes" >&2; exit 1; }
echo "openblack $full in $dir"
