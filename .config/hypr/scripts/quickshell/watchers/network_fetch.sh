#!/usr/bin/env bash
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
get_eth_status() {
    if nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -i 'ethernet' | grep -qi 'connected'; then
        echo "Connected"
    else
        echo "Disconnected"
    fi
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
case $1 in
    --toggle) toggle_wifi ;;
    *) jq -n -c \
        --arg status "$(get_wifi_status)" \
        --arg ssid "$(get_wifi_ssid)" \
        --arg icon "$(get_wifi_icon)" \
        --arg eth "$(get_eth_status)" \
        '{status: $status, ssid: $ssid, icon: $icon, eth_status: $eth}' ;;
esac
