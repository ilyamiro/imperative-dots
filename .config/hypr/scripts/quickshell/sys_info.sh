#!/usr/bin/env bash

## NETWORK
get_wifi_status() {
    if grep -q "up" /sys/class/net/wl*/operstate 2>/dev/null; then echo "enabled"; else echo "disabled"; fi
}

get_wifi_ssid() { 
    local ssid=""
    if command -v iw &>/dev/null; then
        ssid=$(iw dev 2>/dev/null | awk '/\s+ssid/ { $1=""; sub(/^ /, ""); print; exit }')
    fi
    if [ -z "$ssid" ]; then
        ssid=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '/802-11-wireless/ {print $1; exit}')
    fi
    echo "${ssid:-}" 
}

get_wifi_strength() { 
    local signal=$(awk 'NR==3 {gsub(/\./,"",$3); print int($3 * 100 / 70)}' /proc/net/wireless 2>/dev/null)
    echo "${signal:-0}" 
}

get_wifi_icon() {
    local status=$(get_wifi_status)
    if [ "$status" = "enabled" ]; then
        local ssid=$(get_wifi_ssid)
        if [ -n "$ssid" ]; then
            local signal=$(get_wifi_strength)
            if [ "$signal" -ge 75 ]; then echo "󰤨"
            elif [ "$signal" -ge 50 ]; then echo "󰤥"
            elif [ "$signal" -ge 25 ]; then echo "󰤢"
            else echo "󰤟"; fi
        else echo "󰤯"; fi
    else echo "󰤮"; fi
}

toggle_wifi() {
    if [ "$(get_wifi_status)" = "enabled" ]; then
        nmcli radio wifi off
        notify-send -u low -i network-wireless-disabled "WiFi" "Disabled"
    else
        nmcli radio wifi on
        notify-send -u low -i network-wireless-enabled "WiFi" "Enabled"
    fi
}

## BLUETOOTH
get_bt_status() {
    # Fast native check via rfkill to avoid bluetoothctl timeout hangs
    if command -v rfkill &>/dev/null; then
        if rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: no"; then
            echo "on"; return
        else
            echo "off"; return
        fi
    fi
    if timeout 0.2 bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then 
        echo "on"
    else 
        echo "off"
    fi
}

get_bt_connected_device() {
    if [ "$(get_bt_status)" = "on" ]; then
        local device=$(timeout 0.2 bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-)
        if [ -n "$device" ]; then
            echo "$device"
        else
            echo "Disconnected"
        fi
    else 
        echo "Off"
    fi
}

get_bt_icon() {
    if [ "$(get_bt_status)" = "on" ]; then
        if timeout 0.2 bluetoothctl devices Connected 2>/dev/null | grep -q "^Device"; then 
            echo "󰂱"
        else 
            echo "󰂯"
        fi
    else 
        echo "󰂲"
    fi
}

toggle_bt() {
    if [ "$(get_bt_status)" = "on" ]; then
        timeout 0.5 bluetoothctl power off 2>/dev/null
        notify-send -u low -i bluetooth-disabled "Bluetooth" "Disabled"
    else
        timeout 0.5 bluetoothctl power on 2>/dev/null
        notify-send -u low -i bluetooth-active "Bluetooth" "Enabled"
    fi
}

## AUDIO
get_volume() {
    local vol=""
    if command -v wpctl &> /dev/null; then 
        vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '\d+\.\d+' | awk '{print int($1*100)}')
    fi
    if [[ -z "$vol" ]] && command -v pamixer &> /dev/null; then 
        vol=$(pamixer --get-volume 2>/dev/null)
    fi
    echo "${vol:-0}"
}

is_muted() {
    if command -v wpctl &> /dev/null; then
        if wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q "MUTED"; then echo "true"; else echo "false"; fi
    elif command -v pamixer &> /dev/null; then
        if pamixer --get-mute 2>/dev/null | grep -q "true"; then echo "true"; else echo "false"; fi
    else 
        echo "false"
    fi
}

toggle_mute() {
    if command -v wpctl &> /dev/null; then
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    elif command -v pamixer &> /dev/null; then
        pamixer --toggle-mute 2>/dev/null
    fi
    if [ "$(is_muted)" = "true" ]; then notify-send -u low -i audio-volume-muted "Volume" "Muted"
    else notify-send -u low -i audio-volume-high "Volume" "Unmuted ($(get_volume)%)"; fi
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

## BATTERY
get_battery_percent() {
    cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo "100"
}

get_battery_status() {
    cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo "Full"
}

get_battery_icon() {
    local percent=$(get_battery_percent)
    local status=$(get_battery_status)
    if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
        if [ "$percent" -ge 90 ]; then echo "󰂅"
        elif [ "$percent" -ge 80 ]; then echo "󰂋"
        elif [ "$percent" -ge 60 ]; then echo "󰂊"
        elif [ "$percent" -ge 40 ]; then echo "󰢞"
        elif [ "$percent" -ge 20 ]; then echo "󰂆"
        else echo "󰢜"; fi
    else
        if [ "$percent" -ge 90 ]; then echo "󰁹"
        elif [ "$percent" -ge 80 ]; then echo "󰂂"
        elif [ "$percent" -ge 70 ]; then echo "󰂁"
        elif [ "$percent" -ge 60 ]; then echo "󰂀"
        elif [ "$percent" -ge 50 ]; then echo "󰁿"
        elif [ "$percent" -ge 40 ]; then echo "󰁾"
        elif [ "$percent" -ge 30 ]; then echo "󰁽"
        elif [ "$percent" -ge 20 ]; then echo "󰁼"
        elif [ "$percent" -ge 10 ]; then echo "󰁻"
        else echo "󰁺"; fi
    fi
}

## SYSTEM
get_kb_layout() {
    local layout=$(hyprctl devices -j 2>/dev/null | jq -r '(.keyboards[] | select(.main == true) | .active_keymap) // .keyboards[0].active_keymap // empty' | head -n1)
    [[ -z "$layout" || "$layout" == "null" ]] && layout="US"
    echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]'
}

## EXECUTION
case $1 in
    --wifi-toggle) toggle_wifi ;;
    --bt-toggle) toggle_bt ;;
    --toggle-mute) toggle_mute ;;
    *)
        # Setup a temporary directory for parallel JSON dumps
        tmp_dir=$(mktemp -d /tmp/qs_sys_info.XXXXXX)
        trap 'rm -rf "$tmp_dir"' EXIT

        # Execute data gathering for each module in strict parallel
        ( jq -n -c \
            --arg status "$(get_wifi_status)" \
            --arg ssid "$(get_wifi_ssid)" \
            --arg icon "$(get_wifi_icon)" \
            '{wifi: {status: $status, ssid: $ssid, icon: $icon}}' > "$tmp_dir/wifi.json" ) &

        ( jq -n -c \
            --arg status "$(get_bt_status)" \
            --arg icon "$(get_bt_icon)" \
            --arg connected "$(get_bt_connected_device)" \
            '{bt: {status: $status, icon: $icon, connected: $connected}}' > "$tmp_dir/bt.json" ) &

        ( jq -n -c \
            --arg volume "$(get_volume)" \
            --arg icon "$(get_volume_icon)" \
            --arg is_muted "$(is_muted)" \
            '{audio: {volume: $volume, icon: $icon, is_muted: $is_muted}}' > "$tmp_dir/audio.json" ) &

        ( jq -n -c \
            --arg percent "$(get_battery_percent)" \
            --arg status "$(get_battery_status)" \
            --arg icon "$(get_battery_icon)" \
            '{battery: {percent: $percent, status: $status, icon: $icon}}' > "$tmp_dir/battery.json" ) &

        ( jq -n -c \
            --arg layout "$(get_kb_layout)" \
            '{keyboard: {layout: $layout}}' > "$tmp_dir/kb.json" ) &

        # Wait for all background tasks to finish.
        # Max latency is now bounded by the single slowest task, not the sum of all tasks.
        wait

        # Merge all partial JSON files into the master payload
        jq -s 'add' "$tmp_dir"/*.json
    ;;
esac
