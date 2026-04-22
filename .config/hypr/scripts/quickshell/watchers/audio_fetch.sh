#!/usr/bin/env bash
get_volume() {
    local vol=""
    if command -v wpctl &> /dev/null; then 
        vol=$(LC_ALL=C wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100)}')
    fi
    if [[ -z "$vol" ]] && command -v pamixer &> /dev/null; then 
        vol=$(LC_ALL=C pamixer --get-volume 2>/dev/null)
    fi
    echo "${vol:-0}"
}

is_muted() {
    if command -v wpctl &> /dev/null; then
        if LC_ALL=C wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q "MUTED"; then echo "true"; else echo "false"; fi
    elif command -v pamixer &> /dev/null; then
        if LC_ALL=C pamixer --get-mute 2>/dev/null | grep -q "true"; then echo "true"; else echo "false"; fi
    else 
        echo "false"
    fi
}

get_volume_icon() {
    local vol=$(get_volume)
    local muted=$(is_muted)
    if [ "$muted" = "true" ]; then echo "󰝟"
    elif [ "$vol" -ge 70 ]; then echo "󰕾"
    elif [ "$vol" -ge 30 ]; then echo "󰖀"
    elif [ "$vol" -gt 0 ]; then echo "󰕿"
    else echo "󰝟"; fi
}

toggle_mute() {
    if command -v wpctl &> /dev/null; then
        LC_ALL=C wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    elif command -v pamixer &> /dev/null; then
        LC_ALL=C pamixer --toggle-mute 2>/dev/null
    fi
    if [ "$(is_muted)" = "true" ]; then notify-send -u low -i audio-volume-muted "Volume" "Muted"
    else notify-send -u low -i audio-volume-high "Volume" "Unmuted ($(get_volume)%)"; fi
}

case $1 in
    --toggle) toggle_mute ;;
    *) jq -n -c --arg volume "$(get_volume)" --arg icon "$(get_volume_icon)" --arg is_muted "$(is_muted)" '{volume: $volume, icon: $icon, is_muted: $is_muted}' ;;
esac
