#!/usr/bin/env bash

# Ensure pactl can connect to PipeWire/PulseAudio regardless of launch context
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR/pulse"

# Directories
SAVE_DIR="$HOME/Pictures/Screenshots"
RECORD_DIR="$HOME/Videos/Recordings"
CACHE_DIR="$HOME/.cache/qs_recording_state"
mkdir -p "$SAVE_DIR" "$RECORD_DIR" "$CACHE_DIR"

# ---------------------------------------------------------
# SMART TOGGLE: STOP RECORDING & MUX AUDIO/VIDEO
# ---------------------------------------------------------
if [ -f "$CACHE_DIR/wl_pid" ]; then
    WL_PID=$(cat "$CACHE_DIR/wl_pid")
    FF_PID=$(cat "$CACHE_DIR/ff_pid")
    VID_TMP=$(cat "$CACHE_DIR/vid_tmp")
    AUD_TMP=$(cat "$CACHE_DIR/aud_tmp")
    FINAL_FILE=$(cat "$CACHE_DIR/final_file")

    notify-send -a "Screen Recorder" "⏳ Processing..." "Finishing streams. Please wait a moment."

    kill -SIGINT $WL_PID 2>/dev/null
    [ "$FF_PID" != "0" ] && kill -SIGINT $FF_PID 2>/dev/null

    while kill -0 $WL_PID 2>/dev/null; do sleep 0.2; done
    [ "$FF_PID" != "0" ] && while kill -0 $FF_PID 2>/dev/null; do sleep 0.2; done

    if [ -s "$VID_TMP" ]; then
        if [ -s "$AUD_TMP" ]; then
            ffmpeg -nostdin -y \
                -i "$VID_TMP" -i "$AUD_TMP" \
                -filter_complex "[0:a][1:a]amix=inputs=2:duration=first[aout]" \
                -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k \
                "$FINAL_FILE" -loglevel error
        else
            mv "$VID_TMP" "$FINAL_FILE"
        fi

        if [ -f "$FINAL_FILE" ]; then
            notify-send -a "Screen Recorder" -i "$FINAL_FILE" "⏺ Recording Saved" "File: $(basename "$FINAL_FILE")\nFolder: $RECORD_DIR"
        fi
    else
        notify-send -a "Screen Recorder" "❌ Error" "Failed to save the video file."
    fi

    rm -f "$VID_TMP" "$AUD_TMP"
    rm -f "$CACHE_DIR"/wl_pid "$CACHE_DIR"/ff_pid "$CACHE_DIR"/vid_tmp "$CACHE_DIR"/aud_tmp "$CACHE_DIR"/final_file
    exit 0
fi

# Define timestamp for filenames
time=$(date +'%Y-%m-%d-%H%M%S')
FILENAME="$SAVE_DIR/Screenshot_$time.png"
VID_FILENAME="$RECORD_DIR/Recording_$time.mp4"
CACHE_FILE="$HOME/.cache/qs_screenshot_geom"
MODE_CACHE_FILE="$HOME/.cache/qs_screenshot_mode"

# Parse arguments
EDIT_MODE=false
FULL_MODE=false
RECORD_MODE=false
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
# PHASE 1: Execution
# ---------------------------------------------------------
if [ "$FULL_MODE" = true ] || [ -n "$GEOMETRY" ]; then

    if [ "$RECORD_MODE" = true ]; then
        VID_TMP="$RECORD_DIR/.temp_vid_${time}.mp4"
        AUD_TMP="$RECORD_DIR/.temp_aud_${time}.m4a"
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
        WL_ARGS+=(-f "$VID_TMP")

        wl-screenrec "${WL_ARGS[@]}" &
        WL_PID=$!

        FF_PID="0"
        if [ "$MIC_MUTE" != "true" ] && [ -n "$MIC_DEV" ]; then
            ffmpeg -nostdin -y \
                -thread_queue_size 1024 -f pulse -i "$MIC_DEV" \
                -filter_complex "[0:a]volume=${M_VOL},aresample=async=1[aout]" \
                -map "[aout]" -c:a aac -b:a 192k "$AUD_TMP" > "$FFMPEG_LOG" 2>&1 &
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
        # Text restored to show paths. QML still intercepts using the -i path.
        notify-send -a "Screenshot" -i "$FILENAME" "Screenshot Saved" "File: Screenshot_$time.png\nFolder: $SAVE_DIR"
    fi
    exit 0
fi

# ---------------------------------------------------------
# PHASE 2: UI Trigger (Launch Standalone Quickshell Overlay)
# ---------------------------------------------------------

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

quickshell -p ~/.config/hypr/scripts/quickshell/ScreenshotOverlay.qml
