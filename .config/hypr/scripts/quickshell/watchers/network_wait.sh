#!/usr/bin/env bash
PIPE="/tmp/qs_network_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null
trap 'rm -f "$PIPE"; kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM
nmcli monitor 2>/dev/null | grep --line-buffered -E "connected|disconnected" > "$PIPE" &
read -r _ < "$PIPE"
