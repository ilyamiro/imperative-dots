#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"
PIPE="$QS_RUN_DIR/qs_bt_wait_$$.fifo"
rm -f "$PIPE"; mkfifo "$PIPE"
MONITOR_PIDS=()
cleanup() {
    trap - EXIT INT TERM HUP
    rm -f "$PIPE"
    for pid in "${MONITOR_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
    exit 0
}
trap cleanup EXIT INT TERM HUP
LC_ALL=C setpriv --pdeathsig TERM dbus-monitor --system \
"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Device1'" \
> "$PIPE" 2>/dev/null &
MONITOR_PIDS+=("$!")
LC_ALL=C setpriv --pdeathsig TERM dbus-monitor --system \
"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Adapter1'" \
> "$PIPE" 2>/dev/null &
MONITOR_PIDS+=("$!")
while IFS= read -r line; do
    [[ "$line" == *'string "Connected"'* || "$line" == *'string "Powered"'* ]] && break
done < "$PIPE"
