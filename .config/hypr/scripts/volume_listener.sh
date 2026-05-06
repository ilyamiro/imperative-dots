#!/usr/bin/env bash

# Helper functions to get current state
get_sink() { pactl get-default-sink; }
get_vol() { pamixer --get-volume; }
get_mute() { pamixer --get-mute; }

# 1. Initialize state
last_sink=$(get_sink)
last_vol=$(get_vol)
last_mute=$(get_mute)

# 2. Loop through events
pactl subscribe | grep --line-buffered "Event 'change' on sink" | while read -r line; do

    current_sink=$(get_sink)
    current_vol=$(get_vol)
    current_mute=$(get_mute)

    # CHECK 1: Did the Output Device change? (e.g. Headphones connected)
    if [[ "$current_sink" != "$last_sink" ]]; then
        # The device changed. We do NOT want a popup for this.
        # Just update our tracking variables to the new device's levels.
        last_sink="$current_sink"
        last_vol="$current_vol"
        last_mute="$current_mute"
        continue
    fi

    # CHECK 2: Did the Volume/Mute actually change on the SAME device?
    if [[ "$current_vol" != "$last_vol" ]] || [[ "$current_mute" != "$last_mute" ]]; then

        # Trigger OSD (without changing volume)
        swayosd-client --output-volume 0

        # Update tracking
        last_vol="$current_vol"
        last_mute="$current_mute"
    fi
done
