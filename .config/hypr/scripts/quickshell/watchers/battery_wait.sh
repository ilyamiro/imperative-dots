#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"
PIPE="$QS_RUN_DIR/qs_battery_wait_$$.fifo"
rm -f "$PIPE"; mkfifo "$PIPE"
MONITOR_PID=""
cleanup() {
    trap - EXIT INT TERM HUP
    rm -f "$PIPE"
    [[ -z "${MONITOR_PID:-}" ]] || kill "$MONITOR_PID" 2>/dev/null || true
    exit 0
}
trap cleanup EXIT INT TERM HUP
LC_ALL=C setpriv --pdeathsig TERM udevadm monitor --subsystem-match=power_supply > "$PIPE" 2>/dev/null &
MONITOR_PID=$!
deadline=$((SECONDS + 10))
while (( SECONDS < deadline )); do
    remaining=$((deadline - SECONDS))
    IFS= read -r -t "$remaining" line || break
    [[ "${line,,}" == *change* ]] && break
done < "$PIPE"
