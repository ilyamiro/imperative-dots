#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"
PIPE="$QS_RUN_DIR/qs_network_wait_$$.fifo"
rm -f "$PIPE"; mkfifo "$PIPE"
MONITOR_PID=""
cleanup() {
    trap - EXIT INT TERM HUP
    rm -f "$PIPE"
    [[ -z "${MONITOR_PID:-}" ]] || kill "$MONITOR_PID" 2>/dev/null || true
    exit 0
}
trap cleanup EXIT INT TERM HUP
LC_ALL=C setpriv --pdeathsig TERM nmcli monitor > "$PIPE" 2>/dev/null &
MONITOR_PID=$!
while IFS= read -r line; do
    lower="${line,,}"
    if [[ "$lower" == *connected* || "$lower" == *disconnected* ||
          "$lower" == *enabled* || "$lower" == *disabled* ||
          "$lower" == *activated* || "$lower" == *deactivated* ||
          "$lower" == *available* || "$lower" == *unavailable* ]]; then
        break
    fi
done < "$PIPE"
