#!/usr/bin/env bash

## NETWORK
get_wifi_status() { timeout 1 nmcli -t -f WIFI g 2>/dev/null || echo "disabled"; }
get_wifi_ssid() { 
    # Ask the kernel directly (instant) to avoid NetworkManager scan delays
    local ssid=""
    if command -v iw &>/dev/null; then
        # Handle spaces in SSID by grabbing everything after 'ssid '
        ssid=$(timeout 1 iw dev 2>/dev/null | awk '/\s+ssid/ { $1=""; sub(/^ /, ""); print }' | head -n 1)
    fi
    
    # Fast fallback to active connections only (bypasses environmental scans)
    if [ -z "$ssid" ]; then
        ssid=$(timeout 1 nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '/802-11-wireless/ {print $1; exit}')
    fi
    
    echo "${ssid:-}" 
}
get_wifi_strength() { 
    # Fast read from kernel procfs (instant)
    local signal=$(awk 'NR==3 {gsub(/\./,"",$3); print int($3 * 100 / 70)}' /proc/net/wireless 2>/dev/null)
    
    # Fallback to nmcli with a longer timeout just in case
    if [ -z "$signal" ]; then
        signal=$(timeout 2 nmcli -f IN-USE,SIGNAL dev wifi 2>/dev/null | awk '/^\*/ {print $2; exit}')
    fi
    
    echo "${signal:-0}" 
}
get_wifi_icon() {
    local status=$(get_wifi_status)
    local ssid=$(get_wifi_ssid)
    if [ "$status" = "enabled" ]; then
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

## ETHERNET
get_eth_status() {
    local iface=$(ls /sys/class/net/ 2>/dev/null | grep -E "^e" | head -1)
    if [ -n "$iface" ] && [ "$(cat /sys/class/net/$iface/operstate 2>/dev/null)" = "up" ]; then
        echo "connected"
    else
        echo "disconnected"
    fi
}
get_eth_name() {
    local iface=$(ls /sys/class/net/ 2>/dev/null | grep -E "^e" | head -1)
    if [ -n "$iface" ] && [ "$(cat /sys/class/net/$iface/operstate 2>/dev/null)" = "up" ]; then
        local name=$(timeout 1 nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":${iface}$" | cut -d: -f1 | head -1)
        echo "${name:-Wired}"
    else
        echo ""
    fi
}

## BLUETOOTH
get_bt_available() {
    if timeout 1 bluetoothctl show 2>/dev/null | grep -q "Controller"; then
        echo "true"
    else
        echo "false"
    fi
}
get_bt_status() {
    if timeout 1 bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then echo "on"
    else echo "off"; fi
}
get_bt_icon() {
    if [ "$(get_bt_status)" = "on" ]; then
        if timeout 1 bluetoothctl devices Connected 2>/dev/null | grep -q "Device"; then echo "󰂱"
        else echo "󰂯"; fi
    else echo "󰂲"; fi
}
get_bt_connected_device() {
    if [ "$(get_bt_status)" = "on" ]; then
        local device=$(timeout 1 bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-)
        echo "${device:-Disconnected}"
    else echo "Off"; fi
}
toggle_bt() {
    if [ "$(get_bt_status)" = "on" ]; then
        bluetoothctl power off 2>/dev/null
        notify-send -u low -i bluetooth-disabled "Bluetooth" "Disabled"
    else
        bluetoothctl power on 2>/dev/null
        notify-send -u low -i bluetooth-active "Bluetooth" "Enabled"
    fi
}

## AUDIO
get_volume() {
    local vol=""
    if command -v wpctl &> /dev/null; then vol=$(timeout 1 wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '\d+\.\d+' | awk '{print int($1*100)}')
    elif command -v pamixer &> /dev/null; then vol=$(timeout 1 pamixer --get-volume 2>/dev/null)
    elif command -v pactl &> /dev/null; then vol=$(timeout 1 pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\d+%' | head -n1 | tr -d '%')
    fi
    echo "${vol:-0}"
}
is_muted() {
    if command -v wpctl &> /dev/null; then
        timeout 1 wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q "MUTED" && echo "true" || echo "false"
    elif command -v pamixer &> /dev/null; then
        timeout 1 pamixer --get-mute 2>/dev/null | grep -q "true" && echo "true" || echo "false"
    elif command -v pactl &> /dev/null; then
        timeout 1 pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -q "yes" && echo "true" || echo "false"
    else echo "false"; fi
}
toggle_mute() {
    if command -v wpctl &> /dev/null; then
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    elif command -v pamixer &> /dev/null; then
        pamixer --toggle-mute 2>/dev/null
    elif command -v pactl &> /dev/null; then
        pactl set-sink-mute @DEFAULT_SINK@ toggle 2>/dev/null
    fi
    if [ "$(is_muted)" = "true" ]; then notify-send -u low -i audio-volume-muted "Volume" "Muted"
    else notify-send -u low -i audio-volume-high "Volume" "Unmuted ($(get_volume)%)"; fi
}
get_volume_icon() {
    local vol=$(get_volume | tr -cd '0-9')
    local muted=$(is_muted)
    [ -z "$vol" ] && vol=0
    if [ "$muted" = "true" ]; then echo "󰝟"
    elif [ "$vol" -ge 70 ]; then echo "󰕾"
    elif [ "$vol" -ge 30 ]; then echo "󰖀"
    elif [ "$vol" -gt 0 ]; then echo "󰕿"
    else echo "󰝟"; fi
}

## BATTERY
get_battery_present() {
    if ls /sys/class/power_supply/BAT* 2>/dev/null | grep -q .; then
        echo "true"
    else
        echo "false"
    fi
}
get_battery_percent() {
    if [ -f /sys/class/power_supply/BAT*/capacity ]; then 
        local bat=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1)
        echo "${bat:-100}"
    else echo "100"; fi
}
get_battery_status() {
    if [ -f /sys/class/power_supply/BAT*/status ]; then cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1
    else echo "Full"; fi
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
    local layout=$(timeout 1 hyprctl devices -j 2>/dev/null | jq -r '.keyboards[]? | select(.main == true) | .active_keymap' | head -n1)
    [[ -z "$layout" || "$layout" == "null" ]] && layout="US"
    echo "$layout" | cut -c1-2 | tr '[:lower:]' '[:upper:]'
}

## EXECUTION
case $1 in
    --wifi-toggle) toggle_wifi ;;
    --bt-toggle) toggle_bt ;;
    --toggle-mute) toggle_mute ;;
    *)
        # If no arguments are passed, output the full state as JSON
        jq -n -c \
          --arg wifi_status "$(get_wifi_status)" \
          --arg wifi_ssid "$(get_wifi_ssid)" \
          --arg wifi_icon "$(get_wifi_icon)" \
          --arg eth_status "$(get_eth_status)" \
          --arg eth_name "$(get_eth_name)" \
          --arg bt_available "$(get_bt_available)" \
          --arg bt_status "$(get_bt_status)" \
          --arg bt_icon "$(get_bt_icon)" \
          --arg bt_connected "$(get_bt_connected_device)" \
          --arg volume "$(get_volume)" \
          --arg volume_icon "$(get_volume_icon)" \
          --arg is_muted "$(is_muted)" \
          --arg bat_present "$(get_battery_present)" \
          --arg bat_percent "$(get_battery_percent)" \
          --arg bat_status "$(get_battery_status)" \
          --arg bat_icon "$(get_battery_icon)" \
          --arg kb_layout "$(get_kb_layout)" \
          '{
             wifi: { status: $wifi_status, ssid: $wifi_ssid, icon: $wifi_icon },
             ethernet: { status: $eth_status,  name: $eth_name },
             bt: { available: $bt_available, status: $bt_status, icon: $bt_icon, connected: $bt_connected },
             audio: { volume: $volume, icon: $volume_icon, is_muted: $is_muted },
             battery: { present: $bat_present, percent: $bat_percent, status: $bat_status, icon: $bat_icon },
             keyboard: { layout: $kb_layout }
           }'
    ;;
esac
