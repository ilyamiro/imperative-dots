#!/usr/bin/env bash
get_bt_status() {
    if LC_ALL=C timeout 0.5 bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then echo "on"; else echo "off"; fi
}
get_bt_connected_device() {
    if [ "$(get_bt_status)" = "on" ]; then
        local device=$(LC_ALL=C timeout 0.5 bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-)
        if [ -n "$device" ]; then echo "$device"; else echo "Disconnected"; fi
    else echo "Off"; fi
}
get_bt_icon() {
    if [ "$(get_bt_status)" = "on" ]; then
        if LC_ALL=C timeout 0.5 bluetoothctl devices Connected 2>/dev/null | grep -q "^Device"; then echo "󰂱"; else echo "󰂯"; fi
    else echo "󰂲"; fi
}
toggle_bt() {
    if [ "$(get_bt_status)" = "on" ]; then
        LC_ALL=C timeout 0.5 bluetoothctl power off 2>/dev/null
        notify-send -u low -i bluetooth-disabled "Bluetooth" "Disabled"
    else
        LC_ALL=C timeout 0.5 bluetoothctl power on 2>/dev/null
        notify-send -u low -i bluetooth-active "Bluetooth" "Enabled"
    fi
}
case $1 in
    --toggle) toggle_bt ;;
    *) jq -n -c --arg status "$(get_bt_status)" --arg icon "$(get_bt_icon)" --arg connected "$(get_bt_connected_device)" '{status: $status, icon: $icon, connected: $connected}' ;;
esac
