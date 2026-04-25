#!/usr/bin/env bash

# Ensure pactl can connect to PipeWire/PulseAudio regardless of launch context
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR/pulse"

# ---------------------------------------------------------
# DEPENDENCY CHECK
# ---------------------------------------------------------
# First check for notify-send so we can display errors
if ! command -v notify-send &> /dev/null; then
    echo "ERROR: notify-send is not installed. Cannot display missing dependencies."
    exit 1
fi

REQUIRED_CMDS=("gpu-screen-recorder" "grim" "satty" "wl-copy" "pactl" "quickshell" "zbarimg" "python3")
MISSING_CMDS=()

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_CMDS+=("$cmd")
    fi
done

if [ ${#MISSING_CMDS[@]} -ne 0 ]; then
    notify-send -u critical -a "Screenshot System" "Missing Dependencies" "Cannot start. Please install:\n${MISSING_CMDS[*]}"
    exit 1
fi
# ---------------------------------------------------------

# Directories
SAVE_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
RECORD_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
CACHE_DIR="$HOME/.cache/qs_recording_state"
mkdir -p "$SAVE_DIR" "$RECORD_DIR" "$CACHE_DIR"

# Parse arguments safely upfront
EDIT_MODE=false
FULL_MODE=false
RECORD_MODE=false
SCAN_QR_MODE=false
GEOMETRY=""
DESK_VOL="1.0"
DESK_MUTE="false"
MIC_VOL="1.0"
MIC_MUTE="false"
MIC_DEVICE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --edit) EDIT_MODE=true; shift ;;
        --full) FULL_MODE=true; shift ;;
        --record) RECORD_MODE=true; shift ;;
        --scan-qr) SCAN_QR_MODE=true; shift ;;
        --geometry) GEOMETRY="$2"; shift 2 ;;
        --desk-vol) DESK_VOL="$2"; shift 2 ;;
        --desk-mute) DESK_MUTE="$2"; shift 2 ;;
        --mic-vol) MIC_VOL="$2"; shift 2 ;;
        --mic-mute) MIC_MUTE="$2"; shift 2 ;;
        --mic-dev) MIC_DEVICE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# ---------------------------------------------------------
# MULTI-MONITOR GEOMETRY FIX (HYPRLAND)
# ---------------------------------------------------------
# Convert local coordinates from the Quickshell overlay to global Wayland coordinates
if [ -n "$GEOMETRY" ]; then
    # Fetch the X and Y global offset of the currently focused monitor
    OFFSET=$(hyprctl -j monitors | python3 -c "import sys,json; print(next((f\"{m['x']} {m['y']}\" for m in json.load(sys.stdin) if m.get('focused')), '0 0'))" 2>/dev/null)
    read -r MON_X MON_Y <<< "${OFFSET:-0 0}"
    
    # Parse the local geometry passed from QML (Format: "X,Y WxH")
    IFS=', x' read -r LOCAL_X LOCAL_Y W H <<< "$GEOMETRY"
    
    # Calculate true global coordinates
    GLOBAL_X=$((LOCAL_X + MON_X))
    GLOBAL_Y=$((LOCAL_Y + MON_Y))
    
    # Re-assemble for grim
    GEOMETRY="${GLOBAL_X},${GLOBAL_Y} ${W}x${H}"
fi

# ---------------------------------------------------------
# INSTANT QR SCANNING EXECUTION
# ---------------------------------------------------------
if [ "$SCAN_QR_MODE" = true ]; then
    RES_FILE="/tmp/qs_qr_result"
    export DEBUG_LOG="/tmp/qs_qr_debug.log"
    rm -f "$RES_FILE" "$DEBUG_LOG"
    
    echo "=== QR SCAN INITIATED $(date) ===" > "$DEBUG_LOG"
    
    if ! command -v zbarimg &> /dev/null; then
        echo -e "0,0,0,0|||ERROR: zbarimg is not installed. Please install it." > "$RES_FILE"
        exit 1
    fi

    TMP_IMG="/dev/shm/qs_qr_temp_$$.png"
    grim -g "$GEOMETRY" "$TMP_IMG"
    
    export XML_OUT=$(zbarimg --xml -q "$TMP_IMG" 2>>"$DEBUG_LOG")
    
    if [ -n "$XML_OUT" ]; then
        python3 << 'EOF' > "$RES_FILE"
import os, sys, logging, re
import xml.etree.ElementTree as ET

debug_log = os.environ.get("DEBUG_LOG", "/tmp/qs_qr_debug.log")
logging.basicConfig(filename=debug_log, level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s")

raw_xml = os.environ.get("XML_OUT", "")
if not raw_xml.strip():
    print("0,0,0,0|||ERROR: Empty output from zbarimg. See log.")
    sys.exit(0)

try:
    xml_clean = re.sub(r'\sxmlns="[^"]+"', '', raw_xml)
    xml_clean = re.sub(r"\sxmlns='[^']+'", '', xml_clean)
    tree = ET.fromstring(xml_clean)
    
    found_any = False
    for elem in tree.iter():
        if elem.tag.endswith('symbol'):
            found_any = True
            data_text = ''
            min_x, min_y, max_x, max_y = float('inf'), float('inf'), -float('inf'), -float('inf')
            
            for child in elem:
                if child.tag.endswith('data'):
                    data_text = child.text if child.text else ''
                elif child.tag.endswith('polygon'):
                    pts_str = child.get('points', '')
                    if pts_str:
                        pt_pairs = pts_str.replace('+', '').split(' ')
                        for pair in pt_pairs:
                            if ',' in pair:
                                try:
                                    x_str, y_str = pair.split(',')
                                    x, y = int(x_str), int(y_str)
                                    min_x = min(min_x, x)
                                    max_x = max(max_x, x)
                                    min_y = min(min_y, y)
                                    max_y = max(max_y, y)
                                except ValueError:
                                    pass
            
            if min_x == float('inf'): min_x, min_y, max_x, max_y = 0, 0, 0, 0
            w, h = max_x - min_x, max_y - min_y
            encoded = data_text.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '')
            print(f"{int(min_x)},{int(min_y)},{int(w)},{int(h)}|||{encoded}")

    if not found_any: print("0,0,0,0|||NOT_FOUND")
except Exception as e:
    print(f"0,0,0,0|||ERROR: XML Parse failure: {e}. Check log.")
EOF
    else
        echo -e "0,0,0,0|||NOT_FOUND" > "$RES_FILE"
    fi
    
    rm -f "$TMP_IMG"
    exit 0
fi

# ---------------------------------------------------------
# SMART TOGGLE: STOP RECORDING & CLEANUP VIRTUAL AUDIO
# ---------------------------------------------------------
if [ -f "$CACHE_DIR/rec_pid" ]; then
    # PREVENT OVERLAPPING EXECUTIONS
    if [ -f "$CACHE_DIR/processing.lock" ]; then exit 0; fi
    touch "$CACHE_DIR/processing.lock"

    REC_PID=$(cat "$CACHE_DIR/rec_pid")
    FINAL_FILE=$(cat "$CACHE_DIR/final_file")

    # 1. SEND STOP SIGNAL TO GPU-SCREEN-RECORDER
    [ "$REC_PID" != "0" ] && kill -SIGINT $REC_PID 2>/dev/null

    # 2. WAIT FOR GSR TO CLOSE GRACEFULLY AND FINALIZE MP4
    timeout=30
    while kill -0 $REC_PID 2>/dev/null && [ $timeout -gt 0 ]; do
        sleep 0.1
        timeout=$((timeout - 1))
    done

    # FORCE KILL IF STUCK
    [ "$REC_PID" != "0" ] && kill -9 $REC_PID 2>/dev/null

    # 3. DESTROY PIPEWIRE VIRTUAL AUDIO CABLES
    if [ -f "$CACHE_DIR/pw_modules" ]; then
        while read -r mod_id; do
            [ -n "$mod_id" ] && pactl unload-module "$mod_id" 2>/dev/null
        done < "$CACHE_DIR/pw_modules"
        rm -f "$CACHE_DIR/pw_modules"
    fi

    # 4. SEND FINAL NOTIFICATION
    if [ -f "$FINAL_FILE" ]; then
        notify-send -a "Screen Recorder" -i "$FINAL_FILE" "⏺ Recording Saved" "File: $(basename "$FINAL_FILE")\nFolder: $RECORD_DIR"
    else
        notify-send -a "Screen Recorder" "❌ Error" "Failed to save the video file."
    fi

    # 5. INSTANT UI CLEANUP
    rm -f "$CACHE_DIR/processing.lock"
    rm -f "$CACHE_DIR/rec_pid" "$CACHE_DIR/final_file"
    exit 0
fi

time=$(date +'%Y-%m-%d-%H%M%S')
FILENAME="$SAVE_DIR/Screenshot_$time.png"
VID_FILENAME="$RECORD_DIR/Recording_$time.mp4"
CACHE_FILE="$HOME/.cache/qs_screenshot_geom"
MODE_CACHE_FILE="$HOME/.cache/qs_screenshot_mode"

rm -f "$CACHE_DIR/processing.lock"

# ---------------------------------------------------------
# PHASE 1: Capture Execution (GPU-Screen-Recorder + Virtual Audio)
# ---------------------------------------------------------
if [ "$FULL_MODE" = true ] || [ -n "$GEOMETRY" ]; then

    if [ "$RECORD_MODE" = true ]; then
        
        # Clear out any old module IDs
        echo -n "" > "$CACHE_DIR/pw_modules"

        DESK_SINK=$(pactl get-default-sink 2>/dev/null)
        [ -n "$DESK_SINK" ] && DESK_DEV="${DESK_SINK}.monitor" || DESK_DEV=""
        
        [ -n "$MIC_DEVICE" ] && [ "$MIC_DEVICE" != "null" ] && MIC_DEV="$MIC_DEVICE" || MIC_DEV=$(pactl get-default-source 2>/dev/null)
        MIC_DEV="${MIC_DEV:-default}"

        # Reverted back to the portal method for reliable security clearance
        GSR_ARGS=(-w "portal" -c "mp4" -f "60" -ac "aac")

        AUDIO_MIX=""

        # --- DESKTOP AUDIO VIRTUAL ROUTING ---
        if [ "$DESK_MUTE" != "true" ] && [ -n "$DESK_DEV" ]; then
            # Create a virtual sink
            D_SINK_ID=$(pactl load-module module-null-sink sink_name=qs_virt_desk sink_properties=device.description="QS_Virtual_Desk")
            # Loop the real desktop audio into the virtual sink
            D_LOOP_ID=$(pactl load-module module-loopback source="$DESK_DEV" sink=qs_virt_desk)
            
            # Linearize volume calculation (0 - 65536) to prevent PulseAudio's steep cubic drop-off at 25%
            D_VOL_INT=$(awk "BEGIN {print int(${DESK_VOL//,/.} * 65536)}")
            pactl set-sink-volume qs_virt_desk "$D_VOL_INT"
            
            # Save IDs for teardown
            echo "$D_SINK_ID" >> "$CACHE_DIR/pw_modules"
            echo "$D_LOOP_ID" >> "$CACHE_DIR/pw_modules"
            
            # Append to mixing string
            AUDIO_MIX="${AUDIO_MIX}qs_virt_desk.monitor|"
        fi

        # --- MICROPHONE VIRTUAL ROUTING ---
        if [ "$MIC_MUTE" != "true" ] && [ -n "$MIC_DEV" ]; then
            # Create a virtual sink for the mic
            M_SINK_ID=$(pactl load-module module-null-sink sink_name=qs_virt_mic sink_properties=device.description="QS_Virtual_Mic")
            # Loop the real mic into the virtual sink
            M_LOOP_ID=$(pactl load-module module-loopback source="$MIC_DEV" sink=qs_virt_mic)
            
            # Linearize volume calculation (0 - 65536) to prevent PulseAudio's steep cubic drop-off
            M_VOL_INT=$(awk "BEGIN {print int(${MIC_VOL//,/.} * 65536)}")
            pactl set-sink-volume qs_virt_mic "$M_VOL_INT"
            
            # Save IDs for teardown
            echo "$M_SINK_ID" >> "$CACHE_DIR/pw_modules"
            echo "$M_LOOP_ID" >> "$CACHE_DIR/pw_modules"
            
            # Append to mixing string
            AUDIO_MIX="${AUDIO_MIX}qs_virt_mic.monitor|"
        fi

        # Remove trailing pipe and add the single mix string to the recorder so everything stays on one track
        AUDIO_MIX=${AUDIO_MIX%|}
        if [ -n "$AUDIO_MIX" ]; then
            GSR_ARGS+=(-a "$AUDIO_MIX")
        fi

        # Execute gpu-screen-recorder
        gpu-screen-recorder "${GSR_ARGS[@]}" -o "$VID_FILENAME" > /dev/null 2>&1 &
        REC_PID=$!

        echo "$REC_PID" > "$CACHE_DIR/rec_pid"
        echo "$VID_FILENAME" > "$CACHE_DIR/final_file"

        notify-send -a "Screen Recorder" "⏺ Recording Started" "Press your screenshot shortcut again to stop."
        exit 0
    fi

    # Mode: Screenshot
    GRIM_CMD="grim -"
    [ -n "$GEOMETRY" ] && GRIM_CMD="grim -g \"$GEOMETRY\" -"

    if [ "$EDIT_MODE" = true ]; then
        eval $GRIM_CMD | GSK_RENDERER=gl satty --filename - --output-filename "$FILENAME" --init-tool brush --copy-command wl-copy
    else
        eval $GRIM_CMD | tee "$FILENAME" | wl-copy
    fi

    [ -s "$FILENAME" ] && notify-send -a "Screenshot" -i "$FILENAME" "Screenshot Saved" "File: Screenshot_$time.png\nFolder: $SAVE_DIR"
    exit 0
fi

# ---------------------------------------------------------
# PHASE 2: UI Trigger (Launch Standalone Quickshell Overlay)
# ---------------------------------------------------------
QML_PATH="$HOME/.config/hypr/scripts/quickshell/ScreenshotOverlay.qml"

if pgrep -f "quickshell -p $QML_PATH" > /dev/null; then
    pkill -f "quickshell -p $QML_PATH"
    exit 0
fi

if command -v pactl &> /dev/null; then
    export QS_MIC_LIST=$(pactl list sources short 2>/dev/null | awk '{print $2}' | grep -v '\.monitor$' | while IFS= read -r name; do
        desc=$(pactl list sources 2>/dev/null | awk -v n="$name" '/Name:/ { found = ($2 == n) } found && /Description:/ { sub(/^[[:space:]]*Description:[[:space:]]*/, ""); print; exit }')
        echo "$name|${desc:-$name}"
    done)
else
    export QS_MIC_LIST=""
fi

PREFS="$HOME/.cache/qs_audio_prefs"
if [ -f "$PREFS" ]; then
    IFS=',' read -r QS_DESK_VOL QS_DESK_MUTE QS_MIC_VOL QS_MIC_MUTE QS_MIC_DEV < "$PREFS"
    export QS_DESK_VOL QS_DESK_MUTE QS_MIC_VOL QS_MIC_MUTE QS_MIC_DEV
fi

[ "$EDIT_MODE" = true ] && export QS_SCREENSHOT_EDIT="true" || export QS_SCREENSHOT_EDIT="false"
[ -f "$CACHE_FILE" ] && export QS_CACHED_GEOM=$(cat "$CACHE_FILE") || export QS_CACHED_GEOM=""
[ -f "$MODE_CACHE_FILE" ] && export QS_CACHED_MODE=$(cat "$MODE_CACHE_FILE") || export QS_CACHED_MODE="false"

quickshell -p "$QML_PATH"
