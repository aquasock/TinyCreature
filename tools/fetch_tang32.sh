#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepare the pinned TinyNES foundation and apply TinyCreature's Tang patch.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
url=https://github.com/aquasock/TinyNES.git
commit=f5011dd374cfc65f4f17616fec97c903a66b6cc8
source_dir="${TINYCREATURE_TANG_SOURCE:-$root/build/tang32-src}"
patch_file="$root/patches/tinynes-tang32.patch"

if [[ ! -d "$source_dir/.git" ]]; then
    mkdir -p "$source_dir"
    git -C "$source_dir" init -q
    git -C "$source_dir" remote add origin "$url"
fi
if ! git -C "$source_dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$source_dir" fetch -q origin "$commit"
fi
if [[ "$(git -C "$source_dir" rev-parse -q --verify HEAD || true)" != "$commit" ]]; then
    if [[ -n "$(git -C "$source_dir" status --porcelain)" ]]; then
        echo "Tang source has local changes: $source_dir" >&2
        exit 1
    fi
    git -C "$source_dir" checkout -q --detach "$commit"
fi

if git -C "$source_dir" diff --quiet && git -C "$source_dir" diff --cached --quiet; then
    git -C "$source_dir" apply --check "$patch_file"
    git -C "$source_dir" apply "$patch_file"
else
    temporary_index="${TMPDIR:-/tmp}/tinycreature-tang32-index-$$"
    trap 'rm -f "$temporary_index"' EXIT
    GIT_INDEX_FILE="$temporary_index" git -C "$source_dir" read-tree HEAD
    GIT_INDEX_FILE="$temporary_index" git -C "$source_dir" add -A
    GIT_INDEX_FILE="$temporary_index" git -C "$source_dir" apply --cached --reverse "$patch_file"
    GIT_INDEX_FILE="$temporary_index" git -C "$source_dir" diff --cached --quiet || {
        echo "Tang source has changes beyond the project patch: $source_dir" >&2
        exit 1
    }
fi
echo "TinyNES $commit with TinyCreature Tang patch in $source_dir"
