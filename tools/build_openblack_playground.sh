#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds the TinyCreature landscape playground from the pinned openblack source.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
commit=a243c6b2fbd251b5d54c1b5f09f59ded9b3b4c81
upstream="$root/third_party/openblack"
source_dir="$root/build/openblack-playground-src"
build_dir="$root/build/openblack-playground"
patch_files=(
    "$root/patches/openblack-playground.patch"
    "$root/patches/openblack-playground-retro.patch"
    "$root/patches/openblack-playground-memory.patch"
)

"$root/tools/fetch_openblack.sh"

if [[ ! -d "$source_dir/.git" ]]; then
    git clone -q --shared "$upstream" "$source_dir"
    git -C "$source_dir" checkout -q --detach "$commit"
    git -C "$source_dir" -c protocol.file.allow=always \
        -c submodule.vcpkg.url="$upstream/vcpkg" submodule update -q --init --recursive
fi

if [[ "$(git -C "$source_dir" rev-parse HEAD)" != "$commit" ]]; then
    echo "playground source is not at pinned openblack commit $commit: $source_dir" >&2
    exit 1
fi

applied_patch_count() {
	local patch_count patch_index temporary_index valid
	for ((patch_count = ${#patch_files[@]}; patch_count >= 0; --patch_count)); do
		temporary_index="${TMPDIR:-/tmp}/tinycreature-openblack-index-$$-$patch_count"
		rm -f "$temporary_index"
		GIT_INDEX_FILE="$temporary_index" git -C "$source_dir" read-tree HEAD
		GIT_INDEX_FILE="$temporary_index" git -C "$source_dir" add -A
		valid=1
		for ((patch_index = patch_count - 1; patch_index >= 0; --patch_index)); do
			if ! GIT_INDEX_FILE="$temporary_index" git -C "$source_dir" apply --cached --reverse \
				"${patch_files[$patch_index]}" 2>/dev/null; then
				valid=0
				break
			fi
		done
		if ((valid)) && GIT_INDEX_FILE="$temporary_index" git -C "$source_dir" diff --cached --quiet; then
			rm -f "$temporary_index"
			printf '%s\n' "$patch_count"
			return 0
		fi
		rm -f "$temporary_index"
	done
	return 1
}

if ! applied_count=$(applied_patch_count); then
	echo "playground source has unexpected changes: $source_dir" >&2
	exit 1
fi
for ((patch_index = applied_count; patch_index < ${#patch_files[@]}; ++patch_index)); do
	git -C "$source_dir" apply --check "${patch_files[$patch_index]}"
	git -C "$source_dir" apply "${patch_files[$patch_index]}"
done

vcpkg_installed=${OPENBLACK_VCPKG_INSTALLED_DIR:-$root/build/openblack/vcpkg_installed}
cmake -S "$source_dir" -B "$build_dir" -G "Ninja Multi-Config" \
    -DOPENBLACK_USE_VCPKG=ON \
    -DCMAKE_TOOLCHAIN_FILE="$source_dir/vcpkg/scripts/buildsystems/vcpkg.cmake" \
    -DVCPKG_INSTALLED_DIR="$vcpkg_installed"
cmake --build "$build_dir" --config Release --target openblack -j "${OPENBLACK_JOBS:-$(getconf _NPROCESSORS_ONLN)}"

echo "playground binary: $build_dir/bin/Release/openblack"
