#!/usr/bin/env bash

# Zero-latency hardware presence check via sysfs (Instant, no nmcli latency)
# Checks for any network interface starting with 'e' (eth0, enp4s0, eno1, etc.)
if ! ls -1d /sys/class/net/e* &>/dev/null; then
    jq -nc --arg power "off" '{ "present": false, "power": $power, "device": "", "connected": null }'
    exit 0
fi

# Use LC_ALL=C to prevent nmcli from translating output
# Find the first ethernet device regardless of state
ETH_DEV=$(LC_ALL=C nmcli -t -f DEVICE,TYPE d 2>/dev/null | awk -F: '$2=="ethernet" {print $1; exit}')

# Fallback check if nmcli disagrees with the sysfs check
if [[ -z "$ETH_DEV" ]]; then
    jq -nc --arg power "off" '{ "present": false, "power": $power, "device": "", "connected": null }'
    exit 0
fi

# Fetch the specific state of that device
STATE=$(LC_ALL=C nmcli -t -f DEVICE,STATE d 2>/dev/null | awk -F: -v dev="$ETH_DEV" '$1==dev {print $2; exit}')

if [[ "$STATE" == "connected" || "$STATE" == "connecting" ]]; then
    POWER="on"
    
    # Fetch connection statistics
    IP=$(ip -4 addr show dev "$ETH_DEV" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    [ -z "$IP" ] && IP="No IP"

    SPEED=$(cat /sys/class/net/"$ETH_DEV"/speed 2>/dev/null)
    [ -n "$SPEED" ] && SPEED="${SPEED} Mbps" || SPEED="Unknown"

    MAC=$(cat /sys/class/net/"$ETH_DEV"/address 2>/dev/null)

    # Apply LC_ALL=C here as well to ensure consistent parsing
    PROFILE=$(LC_ALL=C nmcli -t -f NAME,DEVICE c show --active 2>/dev/null | grep ":$ETH_DEV$" | cut -d: -f1 | head -n1)
    [ -z "$PROFILE" ] && PROFILE="Wired Connection"

    CONNECTED_JSON=$(jq -nc \
        --arg id "$ETH_DEV" \
        --arg name "$PROFILE" \
        --arg icon "󰈀" \
        --arg ip "$IP" \
        --arg speed "$SPEED" \
        --arg mac "$MAC" \
        '{id: $id, name: $name, icon: $icon, ip: $ip, speed: $speed, mac: $mac}')
else
    POWER="off"
    CONNECTED_JSON="null"
fi

# Output JSON cleanly, including the device name even if offline
jq -nc \
    --arg power "$POWER" \
    --arg device "$ETH_DEV" \
    --argjson connected "$CONNECTED_JSON" \
    '{present: true, power: $power, device: $device, connected: $connected}'
