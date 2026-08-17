#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"
PIPE="$QS_RUN_DIR/qs_kb_wait_$$.fifo"
rm -f "$PIPE"; mkfifo "$PIPE"
MONITOR_PID=""
cleanup() {
    trap - EXIT INT TERM HUP
    rm -f "$PIPE"
    [[ -z "${MONITOR_PID:-}" ]] || kill "$MONITOR_PID" 2>/dev/null || true
    exit 0
}
trap cleanup EXIT INT TERM HUP
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    LC_ALL=C setpriv --pdeathsig TERM socat -U - \
    "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" \
    > "$PIPE" 2>/dev/null &
    MONITOR_PID=$!
    while IFS= read -r line; do
        [[ "$line" == *"activelayout>>"* ]] && break
    done < "$PIPE"
else
    sleep 10
fi
sleep 0.05
