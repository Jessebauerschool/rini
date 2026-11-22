#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <niri-pid>" >&2
    exit 2
fi

pid=$1
status="/proc/$pid/status"
smaps="/proc/$pid/smaps_rollup"

if [[ ! -r "$status" ]]; then
    echo "niri process $pid is not readable" >&2
    exit 1
fi

echo "niri_pid=$pid"
grep -E '^Vm(RSS|Size|Peak|HWM):' "$status" || true

if [[ -r "$smaps" ]]; then
    grep -E '^(Rss|Pss|Private_(Clean|Dirty)|Shared_(Clean|Dirty)|Swap):' "$smaps" |
        sed 's/^/smaps_/'
fi
