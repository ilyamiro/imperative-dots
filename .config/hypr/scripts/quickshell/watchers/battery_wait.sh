#!/usr/bin/env bash
PIPE="/tmp/qs_battery_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null
trap 'rm -f "$PIPE"; kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM

# Catch instant AC plug/unplug events
udevadm monitor --subsystem-match=power_supply 2>/dev/null | grep --line-buffered "change" > "$PIPE" &

# Failsafe: Force a refresh every 30 seconds because the kernel doesn't 
# always broadcast a udev event when the battery drops by 1% naturally.
(sleep 30 && echo "timeout" > "$PIPE") &

read -r _ < "$PIPE"
sleep 0.05
