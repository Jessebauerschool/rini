#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <niri-pid>" >&2
    exit 2
fi

pid=$1
status="/proc/$pid/status"
smaps_rollup="/proc/$pid/smaps_rollup"
smaps="/proc/$pid/smaps"

if [[ ! -r "$status" ]]; then
    echo "niri process $pid is not readable" >&2
    exit 1
fi

echo "rini_pid=$pid"
grep -E '^Vm(RSS|Size|Peak|HWM):' "$status" || true

if [[ -r "$smaps_rollup" ]]; then
    grep -E '^(Rss|Pss|Private_(Clean|Dirty)|Shared_(Clean|Dirty)|Swap):' "$smaps_rollup" |
        sed 's/^/smaps_/'
fi

if [[ -r "$smaps" ]]; then
    echo "largest_mappings_by_pss:"
    awk '
        function print_mapping() {
            printf "%10d %10d %s\n", pss, private, name
        }

        /^[[:xdigit:]]+-[[:xdigit:]]+[[:space:]]/ {
            if (have_mapping) {
                print_mapping()
            }
            name = $0
            for (i = 0; i < 5; i++) {
                sub(/^[^[:space:]]+[[:space:]]*/, "", name)
            }
            if (name == "") {
                name = "[anonymous]"
            }
            pss = 0
            private = 0
            have_mapping = 1
            next
        }

        $1 == "Pss:" { pss += $2 }
        $1 == "Private_Clean:" || $1 == "Private_Dirty:" { private += $2 }

        END {
            if (have_mapping) {
                print_mapping()
            }
        }
    ' "$smaps" |
        sort -nr |
        awk 'NR <= 15 { printf "  PSS: %8s kB  private: %8s kB  %s\n", $1, $2, substr($0, index($0, $3)) }'
fi

cgroup_v2_path="$(awk -F: '$1 == "0" && $2 == "" { print $3; exit }' "/proc/$pid/cgroup")"
if [[ -n "$cgroup_v2_path" ]]; then
    echo "cgroup_path=$cgroup_v2_path"
    cgroup_dir="/sys/fs/cgroup${cgroup_v2_path%/}"
    if [[ -r "$cgroup_dir/memory.current" ]]; then
        echo "cgroup_memory_current_bytes=$(<"$cgroup_dir/memory.current")"
        if [[ -r "$cgroup_dir/memory.max" ]]; then
            echo "cgroup_memory_max_bytes=$(<"$cgroup_dir/memory.max")"
        fi
    fi
else
    cgroup_v1_path="$(awk -F: '$2 ~ /(^|,)memory(,|$)/ { print $3; exit }' "/proc/$pid/cgroup")"
    if [[ -n "$cgroup_v1_path" ]]; then
        echo "cgroup_path=$cgroup_v1_path"
        cgroup_dir="/sys/fs/cgroup/memory${cgroup_v1_path%/}"
        if [[ -r "$cgroup_dir/memory.usage_in_bytes" ]]; then
            echo "cgroup_memory_usage_bytes=$(<"$cgroup_dir/memory.usage_in_bytes")"
            if [[ -r "$cgroup_dir/memory.limit_in_bytes" ]]; then
                echo "cgroup_memory_limit_bytes=$(<"$cgroup_dir/memory.limit_in_bytes")"
            fi
        fi
    fi
fi
