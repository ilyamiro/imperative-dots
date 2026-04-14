#!/usr/bin/env bash

# Buffer delay to prevent hyper-looping if a daemon sends immediate sync events
sleep 0.5

# Setup a unique named pipe for this specific script execution
PIPE="/tmp/qs_sys_waiter_$$"
mkfifo "$PIPE" 2>/dev/null

# Cleanup Trap: Recursively kill all child processes. 
kill_descendants() {
    local pid=$1
    local children
    children=$(pgrep -P "$pid" 2>/dev/null)
    for child in $children; do
        kill_descendants "$child"
    done
    [ "$pid" != "$$" ] && kill -9 "$pid" 2>/dev/null
}
trap 'kill_descendants $$; rm -f "$PIPE"; exit 0' EXIT INT TERM

# 1. Volume
pactl subscribe 2>/dev/null | grep --line-buffered -E "sink|server" > "$PIPE" &

# 2. Network
nmcli monitor 2>/dev/null | grep --line-buffered -E "connected|disconnected" > "$PIPE" &

# 3. Bluetooth Device: Changed to "member=PropertiesChanged" to dodge the "NameAcquired" startup string
dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Device1'" \
    2>/dev/null | grep --line-buffered "member=PropertiesChanged" > "$PIPE" &

# 4. Bluetooth Adapter: Changed to "member=PropertiesChanged" to dodge the "NameAcquired" startup string
dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Adapter1'" \
    2>/dev/null | grep --line-buffered "member=PropertiesChanged" > "$PIPE" &

# 5. Battery: Changed to "change" to dodge the "monitor will print..." startup header
udevadm monitor --subsystem-match=power_supply 2>/dev/null | grep --line-buffered "change" > "$PIPE" &

# 6. Keyboard Layout (Hyprland)
if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock 2>/dev/null \
        | grep --line-buffered "activelayout>>" > "$PIPE" &
fi

# 7. Failsafe: force a refresh every 30 seconds
(sleep 30 && echo "failsafe" > "$PIPE") &

# Block the script here until the VERY FIRST line comes through the pipe
read -r _ < "$PIPE"

# Output the trigger. The script naturally exits, firing the cleanup trap.
echo "trigger"
