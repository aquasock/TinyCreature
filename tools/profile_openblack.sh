#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Measures openblack startup and steady-state CPU and memory use with the bgfx
# Noop and Vulkan backends. A realtime Vulkan phase also measures normal game
# logic cadence. Results stay under build/ and are not committed.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
game_dir=${1:-}
binary=${OPENBLACK_BIN:-$root/build/openblack/bin/Release/openblack}
steady_frames=${OPENBLACK_FRAMES:-3600}
realtime_frames=${OPENBLACK_REALTIME_FRAMES:-600}
runs=${OPENBLACK_RUNS:-3}
sample_interval=${OPENBLACK_SAMPLE_INTERVAL:-0.05}
timestamp=$(date +%Y%m%dT%H%M%S%z)
output_dir=${OPENBLACK_PROFILE_DIR:-$root/build/profile-openblack/$timestamp}

usage() {
    echo "usage: $0 <Black & White install directory>" >&2
    echo "environment: OPENBLACK_BIN OPENBLACK_FRAMES OPENBLACK_REALTIME_FRAMES" >&2
    echo "             OPENBLACK_RUNS OPENBLACK_SAMPLE_INTERVAL OPENBLACK_PROFILE_DIR" >&2
}

if [[ -z "$game_dir" ]]; then
    usage
    exit 2
fi
if [[ ! -x "$binary" ]]; then
    echo "openblack binary is not executable: $binary" >&2
    exit 1
fi
if [[ ! -d "$game_dir/Data" || ! -d "$game_dir/Scripts" ]]; then
    echo "game directory must contain Data/ and Scripts/: $game_dir" >&2
    exit 1
fi
if [[ ! "$steady_frames" =~ ^[1-9][0-9]*$ || ! "$realtime_frames" =~ ^[1-9][0-9]*$ || ! "$runs" =~ ^[1-9][0-9]*$ ]]; then
    echo "frame counts and OPENBLACK_RUNS must be positive integers" >&2
    exit 1
fi

binary=$(realpath "$binary")
game_dir=$(cd "$game_dir" && pwd)
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
summary="$output_dir/summary.tsv"
printf 'backend\trun\tphase\tframes\telapsed_s\tuser_s\tsystem_s\tcpu_ms_per_frame\tmax_rss_kb\tmax_pss_kb\tmax_private_kb\tmax_threads\texit\n' > "$summary"

{
    printf 'timestamp=%s\n' "$(date --iso-8601=seconds)"
    printf 'repository=%s\n' "$(git -C "$root" rev-parse HEAD)"
    printf 'openblack=%s\n' "$(git -C "$root/third_party/openblack" rev-parse HEAD)"
    printf 'binary_sha256=%s\n' "$(sha256sum "$binary" | awk '{print $1}')"
    printf 'machine=%s\n' "$(uname -m)"
    printf 'kernel=%s\n' "$(uname -r)"
    printf 'processors=%s\n' "$(getconf _NPROCESSORS_ONLN)"
    printf 'steady_frames=%s\n' "$steady_frames"
    printf 'realtime_frames=%s\n' "$realtime_frames"
    printf 'runs=%s\n' "$runs"
    printf 'resolution=1280x720\n'
    printf 'steady_vsync=off\n'
    printf 'realtime_vsync=on\n'
    printf 'audio=OpenAL-Soft null driver\n'
} > "$output_dir/metadata.txt"

sample_process() {
    local pid=$1
    local samples=$2
    local now rss pss private_clean private_dirty threads

    printf 'timestamp_ns\trss_kb\tpss_kb\tprivate_kb\tthreads\n' > "$samples"
    while [[ -r "/proc/$pid/smaps_rollup" ]]; do
        now=$(date +%s%N)
        read -r rss pss private_clean private_dirty < <(
            awk '
                /^Rss:/ { rss = $2 }
                /^Pss:/ { pss = $2 }
                /^Private_Clean:/ { clean = $2 }
                /^Private_Dirty:/ { dirty = $2 }
                END { print rss + 0, pss + 0, clean + 0, dirty + 0 }
            ' "/proc/$pid/smaps_rollup" 2>/dev/null || echo '0 0 0 0'
        )
        threads=$(awk '/^Threads:/ { print $2 }' "/proc/$pid/status" 2>/dev/null || true)
        printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$rss" "$pss" \
            "$((private_clean + private_dirty))" "${threads:-0}" >> "$samples"
        sleep "$sample_interval"
    done
}

run_case() {
    local backend=$1
    local run=$2
    local phase=$3
    local frames=$4
    local vsync=${5:-off}
    local case_dir="$output_dir/${backend,,}-${run}-${phase}"
    local timing="$case_dir/time.tsv"
    local samples="$case_dir/smaps.tsv"
    local timer_pid app_pid='' sampler_pid='' children rc fields
    local elapsed user system max_rss exit_status
    local max_pss max_private max_threads cpu_ms
    local -a sync_args=()

    if [[ "$vsync" == on ]]; then
        sync_args=(-V)
    fi

    mkdir -p "$case_dir"
    printf 'elapsed_s\tuser_s\tsystem_s\tmax_rss_kb\texit\n' > "$timing"

    (
        cd "$case_dir"
        exec env LC_ALL=C ALSOFT_DRIVERS=null /usr/bin/time \
            -f '%e\t%U\t%S\t%M\t%x' -a -o "$timing" \
            "$binary" -g "$game_dir" -W 1280 -H 720 -b "$backend" \
            -n "$frames" "${sync_args[@]}" -l "$case_dir/openblack.log" -L all=off \
            > "$case_dir/stdout.log" 2> "$case_dir/stderr.log"
    ) &
    timer_pid=$!

    while kill -0 "$timer_pid" 2>/dev/null; do
        if [[ -r "/proc/$timer_pid/task/$timer_pid/children" ]]; then
            read -r children < "/proc/$timer_pid/task/$timer_pid/children" || true
            app_pid=${children%% *}
            [[ -n "$app_pid" ]] && break
        fi
        sleep 0.01
    done

    if [[ -n "$app_pid" ]]; then
        sample_process "$app_pid" "$samples" &
        sampler_pid=$!
    else
        printf 'timestamp_ns\trss_kb\tpss_kb\tprivate_kb\tthreads\n' > "$samples"
    fi

    set +e
    wait "$timer_pid"
    rc=$?
    if [[ -n "$sampler_pid" ]]; then
        wait "$sampler_pid"
    fi
    set -e

    fields=$(tail -n 1 "$timing")
    IFS=$'\t' read -r elapsed user system max_rss exit_status <<< "$fields"
    read -r max_pss max_private max_threads < <(
        awk -F '\t' '
            NR > 1 {
                if ($3 > pss) pss = $3
                if ($4 > private) private = $4
                if ($5 > threads) threads = $5
            }
            END { print pss + 0, private + 0, threads + 0 }
        ' "$samples"
    )
    cpu_ms=$(awk -v user_time="$user" -v system_time="$system" -v frames="$frames" \
        'BEGIN { printf "%.6f", 1000 * (user_time + system_time) / frames }')

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$backend" "$run" "$phase" "$frames" "$elapsed" "$user" "$system" \
        "$cpu_ms" "$max_rss" "$max_pss" "$max_private" "$max_threads" "$exit_status" \
        >> "$summary"
    printf '%-6s run %s %-7s: %s frames, %s s elapsed, %s kB max RSS\n' \
        "$backend" "$run" "$phase" "$frames" "$elapsed" "$max_rss"

    if [[ "$rc" -ne 0 || "$exit_status" -ne 0 ]]; then
        echo "openblack failed for $backend run $run phase $phase" >&2
        exit 1
    fi
}

for ((run = 1; run <= runs; ++run)); do
    for backend in Noop Vulkan; do
        run_case "$backend" "$run" startup 1
        run_case "$backend" "$run" steady "$((steady_frames + 1))"
    done
    run_case Vulkan "$run" realtime "$((realtime_frames + 1))" on
done

{
    printf 'backend\trun\tsteady_cpu_ms_per_frame\n'
    awk -F '\t' -v steady_frames="$steady_frames" '
    NR == 1 { next }
    {
        key = $1 SUBSEP $2
        if ($3 == "startup") {
            startup_cpu[key] = $6 + $7
        } else if ($3 == "steady") {
            steady_cpu[key] = $6 + $7
        }
    }
    END {
        for (key in steady_cpu) {
            split(key, parts, SUBSEP)
            printf "%s\t%s\t%.6f\n", parts[1], parts[2], \
                1000 * (steady_cpu[key] - startup_cpu[key]) / steady_frames
        }
    }
    ' "$summary" | sort -k1,1 -k2,2n
} > "$output_dir/steady-cpu.tsv"

{
    printf 'backend\trun\trealtime_cpu_ms_per_frame\n'
    awk -F '\t' -v realtime_frames="$realtime_frames" '
    NR == 1 { next }
    {
        key = $1 SUBSEP $2
        if ($3 == "startup") {
            startup_cpu[key] = $6 + $7
        } else if ($3 == "realtime") {
            realtime_cpu[key] = $6 + $7
        }
    }
    END {
        for (key in realtime_cpu) {
            split(key, parts, SUBSEP)
            printf "%s\t%s\t%.6f\n", parts[1], parts[2], \
                1000 * (realtime_cpu[key] - startup_cpu[key]) / realtime_frames
        }
    }
    ' "$summary" | sort -k1,1 -k2,2n
} > "$output_dir/realtime-cpu.tsv"

echo "profile results: $output_dir"
