#!/usr/bin/env bash

TMP_DIR="/tmp/eww_covers"
mkdir -p "$TMP_DIR"
PLACEHOLDER="$TMP_DIR/placeholder_blank.png"
STATE_FILE="$TMP_DIR/last_state.json"

# --- 1. ENSURE PLACEHOLDER EXISTS ---
if [ ! -f "$PLACEHOLDER" ]; then
    convert -size 500x500 xc:"#313244" "$PLACEHOLDER"
fi

# --- 2. CHECK STATUS ---
STATUS=$(playerctl status 2>/dev/null)

if [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ]; then

    # --- 3. GET INFO ---
    rawUrl=$(playerctl metadata mpris:artUrl 2>/dev/null)
    title=$(playerctl metadata xesam:title 2>/dev/null)
    artist=$(playerctl metadata xesam:artist 2>/dev/null)
    
    # Generate Hash
    idStr="${title:-unknown}-${artist:-unknown}"
    trackHash=$(echo "$idStr" | md5sum | cut -d" " -f1)
    
    finalArt="$TMP_DIR/${trackHash}_art.jpg"
    blurPath="$TMP_DIR/${trackHash}_blur.png"
    colorPath="$TMP_DIR/${trackHash}_grad.txt"
    textPath="$TMP_DIR/${trackHash}_text.txt"
    lockFile="$TMP_DIR/${trackHash}.lock"

    # Default display values (Placeholder)
    displayArt="$PLACEHOLDER"
    displayBlur="$PLACEHOLDER"
    displayGrad="linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)"
    displayText="#cdd6f4"

    # --- 4. ASYNC BACKGROUND LOGIC ---
    if [ -f "$finalArt" ] && [ -s "$finalArt" ]; then
        displayArt="$finalArt"
        if [ -f "$blurPath" ]; then displayBlur="$blurPath"; fi
        if [ -f "$colorPath" ]; then displayGrad=$(cat "$colorPath"); fi
        if [ -f "$textPath" ]; then displayText=$(cat "$textPath"); fi
    else
        if [ ! -f "$lockFile" ] && [ -n "$rawUrl" ]; then
            touch "$lockFile"
            (
                if [[ "$rawUrl" == http* ]]; then
                    curl -s -L --max-time 10 -o "$finalArt" "$rawUrl"
                else
                    cleanPath=$(echo "$rawUrl" | sed 's/file:\/\///g')
                    if [ -f "$cleanPath" ]; then
                        cp "$cleanPath" "$finalArt"
                    else
                        cp "$PLACEHOLDER" "$finalArt"
                    fi
                fi

                if [ ! -s "$finalArt" ]; then
                    cp "$PLACEHOLDER" "$finalArt"
                fi

                isPlaceholder=$(convert "$finalArt" -format "%[hex:u.p{0,0}]" info: 2>/dev/null | cut -c1-6)
                
                if [[ "$isPlaceholder" == "313244" ]] || [[ -z "$isPlaceholder" ]]; then
                    cp "$finalArt" "$blurPath"
                else
                    convert "$finalArt" -blur 0x20 -brightness-contrast -30x-10 "$blurPath" 2>/dev/null
                    
                    colors=$(convert "$finalArt" -resize 50x50 -alpha off +dither -quantize RGB -colors 3 -depth 8 -format "%c" histogram:info: 2>/dev/null | grep -E -o '#[0-9A-Fa-f]{6}' | head -n 3 | tr '\n' ' ')
                    read -r -a color_array <<< "$colors"
                    
                    c1=${color_array[0]:-#cba6f7}
                    c2=${color_array[1]:-$c1}
                    c3=${color_array[2]:-$c1}
                    
                    echo "linear-gradient(45deg, $c1, $c2, $c3, $c1)" > "$colorPath"
                    
                    opp_raw=$(convert xc:"$c1" -alpha off -negate -depth 8 -format "%[hex:u]" info: 2>/dev/null | grep -E -o '[0-9A-Fa-f]{6}' | head -n 1)
                    if [ -n "$opp_raw" ]; then
                        echo "#$opp_raw" > "$textPath"
                    else
                        echo "#cdd6f4" > "$textPath"
                    fi
                fi

                rm "$lockFile"
                (cd "$TMP_DIR" && ls -1t | tail -n +21 | xargs -r rm 2>/dev/null)
            ) &
        fi
    fi

    # --- 5. TIMING ---
    len_micro=$(playerctl metadata mpris:length 2>/dev/null)
    if [ -z "$len_micro" ] || [ "$len_micro" -eq 0 ]; then len_micro=1000000; fi
    len_sec=$((len_micro / 1000000))
    len_str=$(printf "%02d:%02d" $((len_sec/60)) $((len_sec%60)))

    if [ "$STATUS" = "Playing" ]; then
        # When playing, playerctl reports position correctly — save it
        pos_micro=$(playerctl metadata --format '{{position}}' 2>/dev/null)
        if [ -z "$pos_micro" ]; then pos_micro=0; fi
        pos_sec=$((pos_micro / 1000000))

        # Persist for use when paused/stopped (Firefox MPRIS reports 0 when paused)
        jq -n -c \
            --argjson pos_sec "$pos_sec" \
            --argjson len_sec "$len_sec" \
            '{pos_sec: $pos_sec, len_sec: $len_sec}' \
            > "$STATE_FILE"
    else
        # Paused: Firefox (and some other players) report position=0 over D-Bus.
        # Use last saved position from when it was playing instead.
        pos_sec=0
        if [ -f "$STATE_FILE" ]; then
            saved_pos=$(jq -r '.pos_sec' "$STATE_FILE")
            saved_len=$(jq -r '.len_sec' "$STATE_FILE")
            # Only restore if it's the same track length (same song)
            if [ "$saved_len" = "$len_sec" ] && [ -n "$saved_pos" ] && [ "$saved_pos" != "null" ]; then
                pos_sec=$saved_pos
            fi
        fi
    fi

    percent=$((pos_sec * 100 / len_sec))
    pos_str=$(printf "%02d:%02d" $((pos_sec/60)) $((pos_sec%60)))
    time_str="${pos_str} / ${len_str}"

    # --- 6. DEVICE INFO ---
    player_raw=$(playerctl status -f "{{playerName}}" 2>/dev/null | head -n 1)
    player_nice="${player_raw^}"

    sink_name=$(pactl get-default-sink 2>/dev/null)
    dev_icon="󰓃"; dev_name="Speaker"
    if [[ "$sink_name" == *"bluez"* ]]; then
        dev_icon="󰂯"
        readable_name=$(pactl list sinks | grep -A 20 "$sink_name" | grep -m 1 "Description:" | cut -d: -f2 | xargs)
        if [ -n "$readable_name" ]; then dev_name="$readable_name"; else dev_name="Bluetooth"; fi
    elif [[ "$sink_name" == *"usb"* ]]; then
        dev_icon="󰓃"; dev_name="USB Audio"
    elif [[ "$sink_name" == *"pci"* ]]; then
        dev_icon="󰓃"; dev_name="System"
    fi

    # --- 7. JSON OUTPUT ---
    jq -n -c \
        --arg title "$title" \
        --arg artist "$artist" \
        --arg status "$STATUS" \
        --arg len "$len_sec" \
        --arg pos "$pos_sec" \
        --arg len_str "$len_str" \
        --arg pos_str "$pos_str" \
        --arg time_str "$time_str" \
        --arg percent "$percent" \
        --arg source "$player_nice" \
        --arg pname "$player_raw" \
        --arg blur "$displayBlur" \
        --arg grad "$displayGrad" \
        --arg txtColor "$displayText" \
        --arg devIcon "$dev_icon" \
        --arg devName "$dev_name" \
        --arg finalArt "$displayArt" \
        '{
            title: $title,
            artist: $artist,
            status: $status,
            length: $len,
            position: $pos,
            lengthStr: $len_str,
            positionStr: $pos_str,
            timeStr: $time_str,
            percent: $percent,
            source: $source,
            playerName: $pname,
            blur: $blur,
            grad: $grad,
            textColor: $txtColor,
            deviceIcon: $devIcon,
            deviceName: $devName,
            artUrl: $finalArt
        }'

else
    # --- FALLBACK (Stopped) ---
    # Restore last known position so the widget does not snap to 00:00
    if [ -f "$STATE_FILE" ]; then
        last_pos_sec=$(jq -r '.pos_sec' "$STATE_FILE")
        last_len_sec=$(jq -r '.len_sec' "$STATE_FILE")
    else
        last_pos_sec=0; last_len_sec=0
    fi

    if [ -z "$last_pos_sec" ] || [ "$last_pos_sec" = "null" ]; then last_pos_sec=0; fi
    if [ -z "$last_len_sec" ] || [ "$last_len_sec" = "null" ] || [ "$last_len_sec" -eq 0 ]; then last_len_sec=1; fi

    last_percent=$((last_pos_sec * 100 / last_len_sec))
    last_pos_str=$(printf "%02d:%02d" $((last_pos_sec/60)) $((last_pos_sec%60)))
    last_len_str=$(printf "%02d:%02d" $((last_len_sec/60)) $((last_len_sec%60)))
    last_time_str="${last_pos_str} / ${last_len_str}"

    jq -n -c \
    --arg placeholder "$PLACEHOLDER" \
    --arg pos_str "$last_pos_str" \
    --arg len_str "$last_len_str" \
    --arg time_str "$last_time_str" \
    --arg percent "$last_percent" \
    '{
        title: "Not Playing",
        artist: "",
        status: "Stopped",
        percent: $percent,
        lengthStr: $len_str,
        positionStr: $pos_str,
        timeStr: $time_str,
        source: "Offline",
        playerName: "",
        blur: $placeholder,
        grad: "linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)",
        textColor: "#cdd6f4",
        deviceIcon: "󰓃",
        deviceName: "Speaker",
        artUrl: $placeholder
    }'
fi
