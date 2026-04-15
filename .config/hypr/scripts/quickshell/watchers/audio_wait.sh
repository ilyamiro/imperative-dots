#!/usr/bin/env bash
PIPE="/tmp/qs_audio_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null
trap 'rm -f "$PIPE"; kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM
pactl subscribe 2>/dev/null | grep --line-buffered -E "sink|server" > "$PIPE" &
read -r _ < "$PIPE"
