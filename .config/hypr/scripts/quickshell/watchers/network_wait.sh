#!/usr/bin/env bash
PIPE="/tmp/qs_network_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null
trap 'rm -f "$PIPE"; kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM

LC_ALL=C nmcli monitor 2>/dev/null | grep --line-buffered -iwE "connected|disconnected|enabled|disabled|activated|deactivated|available|unavailable" > "$PIPE" &
read -r _ < "$PIPE"
