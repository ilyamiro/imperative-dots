#!/usr/bin/env bash

# Ensure pactl can connect to PipeWire/PulseAudio regardless of launch context
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR/pulse"

# Directories
SAVE_DIR="$HOME/Pictures/Screenshots"
RECORD_DIR="$HOME/Videos/Recordings"
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
# INSTANT QR SCANNING EXECUTION (WITH EXTENSIVE LOGGING)
# ---------------------------------------------------------
if [ "$SCAN_QR_MODE" = true ]; then
    RES_FILE="/tmp/qs_qr_result"
    export DEBUG_LOG="/tmp/qs_qr_debug.log"
    rm -f "$RES_FILE" "$DEBUG_LOG"
    
    echo "=== QR SCAN INITIATED $(date) ===" > "$DEBUG_LOG"
    
    if ! command -v zbarimg &> /dev/null; then
        echo -e "0,0,0,0|||ERROR: zbarimg is not installed. Please install it." > "$RES_FILE"
        echo "ERROR: zbarimg not installed." >> "$DEBUG_LOG"
        exit 1
    fi

    TMP_IMG="/dev/shm/qs_qr_temp_$$.png"
    echo "Taking screenshot with grim..." >> "$DEBUG_LOG"
    grim -g "$GEOMETRY" "$TMP_IMG"
    
    echo "Running zbarimg..." >> "$DEBUG_LOG"
    # Capture stderr to log, stdout to exported variable for Python
    export XML_OUT=$(zbarimg --xml -q "$TMP_IMG" 2>>"$DEBUG_LOG")
    
    echo "zbarimg finished. Output length: ${#XML_OUT}" >> "$DEBUG_LOG"
    
    if [ -n "$XML_OUT" ]; then
        echo "Executing Python parser..." >> "$DEBUG_LOG"
        
        # Using a quoted Here-Doc ('EOF') prevents Bash from attempting to evaluate ANY syntax inside.
        python3 << 'EOF' > "$RES_FILE"
import os, sys, logging, re
import xml.etree.ElementTree as ET

debug_log = os.environ.get("DEBUG_LOG", "/tmp/qs_qr_debug.log")
logging.basicConfig(filename=debug_log, level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s")
logging.info("--- Starting Python XML Parser ---")

raw_xml = os.environ.get("XML_OUT", "")
logging.debug(f"Raw XML Received:\n{raw_xml}")

if not raw_xml.strip():
    logging.error("Received empty XML string")
    print("0,0,0,0|||ERROR: Empty output from zbarimg. See log.")
    sys.exit(0)

try:
    # Aggressively strip xmlns attributes
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
                # Handle <polygon points="+x,+y +x2,+y2 ..."/> format properly
                elif child.tag.endswith('polygon'):
                    pts_str = child.get('points', '')
                    if pts_str:
                        # Strip the '+' signs and split by space
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
            
            if min_x == float('inf'):
                min_x, min_y, max_x, max_y = 0, 0, 0, 0

            w = max_x - min_x
            h = max_y - min_y

            encoded = data_text.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '')
            logging.info(f"QR Extracted: {int(min_x)},{int(min_y)},{int(w)},{int(h)} -> {encoded[:50]}...")
            print(f"{int(min_x)},{int(min_y)},{int(w)},{int(h)}|||{encoded}")

    if not found_any:
        logging.warning("No <symbol> tags found in the XML.")
        print("0,0,0,0|||NOT_FOUND")

except Exception as e:
    logging.exception("Failed to parse XML")
    print(f"0,0,0,0|||ERROR: XML Parse failure: {e}. Check log.")
EOF
    else
        echo "zbarimg output was totally empty." >> "$DEBUG_LOG"
        echo -e "0,0,0,0|||NOT_FOUND" > "$RES_FILE"
    fi
    
    rm -f "$TMP_IMG"
    echo "=== QR SCAN FINISHED ===" >> "$DEBUG_LOG"
    exit 0
fi

# ---------------------------------------------------------
# SMART TOGGLE: STOP RECORDING & MUX AUDIO/VIDEO
# ---------------------------------------------------------
if [ -f "$CACHE_DIR/wl_pid" ]; then
    # PREVENT OVERLAPPING EXECUTIONS IF BUTTON IS SPAMMED
    if [ -f "$CACHE_DIR/processing.lock" ]; then
        exit 0
    fi
    touch "$CACHE_DIR/processing.lock"

    WL_PID=$(cat "$CACHE_DIR/wl_pid")
    FF_PID=$(cat "$CACHE_DIR/ff_pid")
    VID_TMP=$(cat "$CACHE_DIR/vid_tmp")
    AUD_TMP=$(cat "$CACHE_DIR/aud_tmp")
    FINAL_FILE=$(cat "$CACHE_DIR/final_file")

    notify-send -a "Screen Recorder" "⏳ Saving..." "Processing recording in the background."

    # 1. SEND STOP SIGNAL SIMULTANEOUSLY (Fixes audio trailing)
    [ "$WL_PID" != "0" ] && kill -SIGINT $WL_PID 2>/dev/null
    [ "$FF_PID" != "0" ] && kill -SIGINT $FF_PID 2>/dev/null

    # 2. WAIT FOR BOTH TO CLOSE GRACEFULLY
    timeout=30
    while { kill -0 $WL_PID 2>/dev/null || kill -0 $FF_PID 2>/dev/null; } && [ $timeout -gt 0 ]; do
        sleep 0.1
        timeout=$((timeout - 1))
    done

    # 3. FORCE KILL IF STUCK
    [ "$WL_PID" != "0" ] && kill -9 $WL_PID 2>/dev/null
    [ "$FF_PID" != "0" ] && kill -9 $FF_PID 2>/dev/null

    # 4. BACKGROUND THE HEAVY LIFTING (Fixes 4-second UI freeze)
    (
        if [ -s "$VID_TMP" ]; then
            if [ -s "$AUD_TMP" ]; then
                HAS_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$VID_TMP" 2>/dev/null)

                MIX_SUCCESS=false
                if [ -n "$HAS_AUDIO" ]; then
                    # Both exist -> Mix them
                    if ffmpeg -nostdin -y -threads 0 \
                        -i "$VID_TMP" -i "$AUD_TMP" \
                        -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=2[aout]" \
                        -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k -shortest \
                        "$FINAL_FILE" -loglevel error; then
                        MIX_SUCCESS=true
                    fi
                else
                    # Only mic exists -> Map directly
                    if ffmpeg -nostdin -y -threads 0 \
                        -i "$VID_TMP" -i "$AUD_TMP" \
                        -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k -shortest \
                        "$FINAL_FILE" -loglevel error; then
                        MIX_SUCCESS=true
                    fi
                fi

                if [ "$MIX_SUCCESS" = true ]; then
                    rm -f "$VID_TMP" "$AUD_TMP"
                else
                    mv "$VID_TMP" "$FINAL_FILE"
                    notify-send -a "Screen Recorder" "⚠️ Audio Mix Failed" "Saved video with default audio only."
                fi
            else
                mv "$VID_TMP" "$FINAL_FILE"
            fi

            if [ -f "$FINAL_FILE" ]; then
                notify-send -a "Screen Recorder" -i "$FINAL_FILE" "⏺ Recording Saved" "File: $(basename "$FINAL_FILE")\nFolder: $RECORD_DIR"
            fi
        else
            notify-send -a "Screen Recorder" "❌ Error" "Failed to save the video file."
        fi

        # Final cleanup of temp assets inside the subshell
        rm -f "$AUD_TMP" "$VID_TMP"
    ) & disown

    # 5. INSTANT UI CLEANUP (Lets the topbar button update immediately)
    rm -f "$CACHE_DIR/processing.lock"
    rm -f "$CACHE_DIR"/wl_pid "$CACHE_DIR"/ff_pid "$CACHE_DIR"/vid_tmp "$CACHE_DIR"/aud_tmp "$CACHE_DIR"/final_file
    exit 0
fi

# Define timestamp for filenames
time=$(date +'%Y-%m-%d-%H%M%S')
FILENAME="$SAVE_DIR/Screenshot_$time.png"
VID_FILENAME="$RECORD_DIR/Recording_$time.mp4"
CACHE_FILE="$HOME/.cache/qs_screenshot_geom"
MODE_CACHE_FILE="$HOME/.cache/qs_screenshot_mode"

# Ensure there are no stale lock files when starting a new recording
rm -f "$CACHE_DIR/processing.lock"

# ---------------------------------------------------------
# PHASE 1: Capture Execution
# ---------------------------------------------------------
if [ "$FULL_MODE" = true ] || [ -n "$GEOMETRY" ]; then

    if [ "$RECORD_MODE" = true ]; then
        VID_TMP="$RECORD_DIR/.temp_vid_${time}.mp4"
        AUD_TMP="$RECORD_DIR/.temp_aud_${time}.wav"
        FFMPEG_LOG="$CACHE_DIR/ffmpeg_debug.log"

        D_VOL="${DESK_VOL//,/.}"
        M_VOL="${MIC_VOL//,/.}"
        if [ "$DESK_MUTE" = "true" ]; then D_VOL="0.0"; fi
        if [ "$MIC_MUTE" = "true" ]; then M_VOL="0.0"; fi

        DESK_SINK=$(pactl get-default-sink 2>/dev/null)
        if [ -n "$DESK_SINK" ]; then
            DESK_DEV="${DESK_SINK}.monitor"
        else
            DESK_DEV=""
        fi

        if [ -n "$MIC_DEVICE" ] && [ "$MIC_DEVICE" != "null" ]; then
            MIC_DEV="$MIC_DEVICE"
        else
            MIC_DEV=$(pactl get-default-source 2>/dev/null)
            MIC_DEV="${MIC_DEV:-default}"
        fi

        WL_ARGS=()
        if [ "$FULL_MODE" = false ]; then
            WL_ARGS+=(-g "$GEOMETRY")
        fi
        if [ "$DESK_MUTE" != "true" ] && [ -n "$DESK_DEV" ]; then
            WL_ARGS+=(--audio --audio-device "$DESK_DEV")
        fi
        
        WL_ARGS+=(--bitrate "1.2 MB") 
        WL_ARGS+=(-f "$VID_TMP")

        wl-screenrec "${WL_ARGS[@]}" &
        WL_PID=$!

        FF_PID="0"
        if [ "$MIC_MUTE" != "true" ] && [ -n "$MIC_DEV" ]; then
            ffmpeg -nostdin -y \
                -thread_queue_size 1024 -f pulse -i "$MIC_DEV" \
                -filter_complex "[0:a]volume=${M_VOL}[aout]" \
                -map "[aout]" -c:a pcm_s16le "$AUD_TMP" > "$FFMPEG_LOG" 2>&1 &
            FF_PID=$!
        fi

        echo "$WL_PID" > "$CACHE_DIR/wl_pid"
        echo "$FF_PID"  > "$CACHE_DIR/ff_pid"
        echo "$VID_TMP" > "$CACHE_DIR/vid_tmp"
        echo "$AUD_TMP" > "$CACHE_DIR/aud_tmp"
        echo "$VID_FILENAME" > "$CACHE_DIR/final_file"

        notify-send -a "Screen Recorder" "⏺ Recording Started" "Press your screenshot shortcut again to stop."
        exit 0
    fi

    # Mode: Screenshot
    GRIM_CMD="grim -"
    if [ -n "$GEOMETRY" ]; then
        GRIM_CMD="grim -g \"$GEOMETRY\" -"
    fi

    if [ "$EDIT_MODE" = true ]; then
        eval $GRIM_CMD | GSK_RENDERER=gl satty --filename - --output-filename "$FILENAME" --init-tool brush --copy-command wl-copy
    else
        eval $GRIM_CMD | tee "$FILENAME" | wl-copy
    fi

    if [ -s "$FILENAME" ]; then
        notify-send -a "Screenshot" -i "$FILENAME" "Screenshot Saved" "File: Screenshot_$time.png\nFolder: $SAVE_DIR"
    fi
    exit 0
fi

# ---------------------------------------------------------
# PHASE 2: UI Trigger (Launch Standalone Quickshell Overlay)
# ---------------------------------------------------------

QML_PATH="$HOME/.config/hypr/scripts/quickshell/ScreenshotOverlay.qml"

# Toggle logic: if it's already running, kill it and exit
if pgrep -f "quickshell -p $QML_PATH" > /dev/null; then
    pkill -f "quickshell -p $QML_PATH"
    exit 0
fi

if command -v pactl &> /dev/null; then
    export QS_MIC_LIST=$(pactl list sources short 2>/dev/null \
        | awk '{print $2}' \
        | grep -v '\.monitor$' \
        | while IFS= read -r name; do
            desc=$(pactl list sources 2>/dev/null \
                | awk -v n="$name" '
                    /Name:/ { found = ($2 == n) }
                    found && /Description:/ {
                        sub(/^[[:space:]]*Description:[[:space:]]*/, "")
                        print
                        exit
                    }')
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

if [ "$EDIT_MODE" = true ]; then export QS_SCREENSHOT_EDIT="true"; else export QS_SCREENSHOT_EDIT="false"; fi
if [ -f "$CACHE_FILE" ]; then export QS_CACHED_GEOM=$(cat "$CACHE_FILE"); else export QS_CACHED_GEOM=""; fi
if [ -f "$MODE_CACHE_FILE" ]; then export QS_CACHED_MODE=$(cat "$MODE_CACHE_FILE"); else export QS_CACHED_MODE="false"; fi

quickshell -p "$QML_PATH"
