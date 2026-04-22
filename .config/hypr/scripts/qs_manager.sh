#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# CONSTANTS & ARGUMENTS
# -----------------------------------------------------------------------------
QS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BT_PID_FILE="$HOME/.cache/bt_scan_pid"
BT_SCAN_LOG="$HOME/.cache/bt_scan.log"
SRC_DIR="${WALLPAPER_DIR:-${srcdir:-$HOME/Pictures/Wallpapers}}"
THUMB_DIR="$HOME/.cache/wallpaper_picker/thumbs"

# User-specific cache directory matching the QML logic
QS_NETWORK_CACHE="${XDG_RUNTIME_DIR:-$HOME/.cache}/qs_network"
mkdir -p "$QS_NETWORK_CACHE"

IPC_FILE="/tmp/qs_widget_state"
NETWORK_MODE_FILE="$QS_NETWORK_CACHE/mode"

ACTION="$1"
TARGET="$2"
SUBTARGET="$3"

# -----------------------------------------------------------------------------
# FAST PATH: WORKSPACE SWITCHING
# -----------------------------------------------------------------------------
if [[ "$ACTION" =~ ^[0-9]+$ ]]; then
    WORKSPACE_NUM="$ACTION"
    echo "close" > "$IPC_FILE"
    
    CMD="workspace $WORKSPACE_NUM"
    [[ "$2" == "move" ]] && CMD="movetoworkspace $WORKSPACE_NUM"
    hyprctl --batch "dispatch $CMD" >/dev/null 2>&1
    exit 0
fi

handle_wallpaper_prep() {
    mkdir -p "$THUMB_DIR"

    THUMB_SOURCE_FILE="$THUMB_DIR/.source_dir"
    if [ -f "$THUMB_SOURCE_FILE" ]; then
        CACHED_SRC=$(cat "$THUMB_SOURCE_FILE")
        if [ "$CACHED_SRC" != "$SRC_DIR" ]; then
            find "$THUMB_DIR" -maxdepth 1 -type f ! -name '.source_dir' -delete
            echo "$SRC_DIR" > "$THUMB_SOURCE_FILE"
        fi
    else
        echo "$SRC_DIR" > "$THUMB_SOURCE_FILE"
    fi
    
    # Completely detached subshell to prevent random input/output stream blocking
    (
        LOCKFILE="/tmp/qs_manager_wallpaper.lock"
        exec 9> "$LOCKFILE"
        if ! flock -n 9; then
            exit 0
        fi

        # --- FAST ORPHAN REMOVAL (Fix for the 5-second QML UI freeze) ---
        # Instead of looping one-by-one and triggering QML's FolderListModel 
        # onCountChanged repeatedly, we map orphans in memory and delete 
        # them all at once to only trigger the Qt file-watcher once.
        
        find "$SRC_DIR" -maxdepth 1 -type f -printf "%f\n" > /tmp/qs_src_files.txt
        find "$THUMB_DIR" -maxdepth 1 -type f ! -name '.source_dir' -printf "%f\n" | awk '{
            orig=$0; 
            sub(/^000_/, "", orig); 
            print orig "\t" $0
        }' > /tmp/qs_thumbs_map.txt

        awk 'NR==FNR {src[$0]=1; next} { if (!($1 in src)) print "'"$THUMB_DIR"'/"$2 }' /tmp/qs_src_files.txt /tmp/qs_thumbs_map.txt | xargs -r rm -f
        
        rm -f /tmp/qs_src_files.txt /tmp/qs_thumbs_map.txt

        # --- GENERATE MISSING THUMBNAILS ---
        for img in "$SRC_DIR"/*.{jpg,jpeg,png,webp,gif,mp4,mkv,mov,webm}; do
            [ -e "$img" ] || continue
            filename=$(basename "$img")
            extension="${filename##*.}"

            if [[ "${extension,,}" == "webp" ]]; then
                new_img="${img%.*}.jpg"
                if command -v magick >/dev/null 2>&1; then
                    magick "$img" "$new_img"
                    rm -f "$img"
                    img="$new_img"
                    filename=$(basename "$img")
                    extension="jpg"
                fi
            fi

            if [[ "${extension,,}" =~ ^(mp4|mkv|mov|webm)$ ]]; then
                thumb="$THUMB_DIR/000_$filename"
                [ -f "$THUMB_DIR/$filename" ] && rm -f "$THUMB_DIR/$filename"
                if [ ! -f "$thumb" ]; then
                     ffmpeg -y -ss 00:00:05 -i "$img" -vframes 1 -f image2 -q:v 2 "$thumb" > /dev/null 2>&1
                fi
            else
                thumb="$THUMB_DIR/$filename"
                if [ ! -f "$thumb" ]; then
                    if command -v magick >/dev/null 2>&1; then
                        magick "$img" -resize x420 -quality 70 "$thumb"
                    fi
                fi
            fi
        done
    ) </dev/null >/dev/null 2>&1 &

    TARGET_THUMB=""
    CURRENT_SRC=""

    # Optimized search patterns using -m 1 for faster pipe termination
    if pgrep -a "mpvpaper" > /dev/null 2>&1; then
        CURRENT_SRC=$(pgrep -a mpvpaper 2>/dev/null | grep -m 1 -o "$SRC_DIR/[^' ]*")
        [ -n "$CURRENT_SRC" ] && CURRENT_SRC=$(basename "$CURRENT_SRC")
    fi

    if [ -z "$CURRENT_SRC" ] && command -v swww >/dev/null 2>&1; then
        CURRENT_SRC=$(swww query 2>/dev/null | awk -F'image: ' '{print $2}' | head -n 1)
        [ -n "$CURRENT_SRC" ] && CURRENT_SRC=$(basename "$CURRENT_SRC")
    fi
    
    if [ -n "$CURRENT_SRC" ]; then
        EXT="${CURRENT_SRC##*.}"
        if [[ "${EXT,,}" =~ ^(mp4|mkv|mov|webm)$ ]]; then
            TARGET_THUMB="000_$CURRENT_SRC"
        else
            TARGET_THUMB="$CURRENT_SRC"
        fi
    fi
    
    export WALLPAPER_THUMB="$TARGET_THUMB"
}


handle_network_prep() {
    echo "" > "$BT_SCAN_LOG"
    { echo "scan on"; sleep infinity; } | stdbuf -oL bluetoothctl > "$BT_SCAN_LOG" 2>&1 &
    echo $! > "$BT_PID_FILE"
    (nmcli device wifi rescan) >/dev/null 2>&1 &
}

# -----------------------------------------------------------------------------
# ZOMBIE WATCHDOG
# -----------------------------------------------------------------------------
MAIN_QML_PATH="$HOME/.config/hypr/scripts/quickshell/Main.qml"
BAR_QML_PATH="$HOME/.config/hypr/scripts/quickshell/TopBar.qml"

if ! pgrep -f "quickshell.*Main\.qml" >/dev/null; then
    quickshell -p "$MAIN_QML_PATH" >/dev/null 2>&1 &
    disown
fi

if ! pgrep -f "quickshell.*TopBar\.qml" >/dev/null; then
    quickshell -p "$BAR_QML_PATH" >/dev/null 2>&1 &
    disown
fi

# -----------------------------------------------------------------------------
# IPC ROUTING
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "close" ]]; then
    echo "close" > "$IPC_FILE"
    if [[ "$TARGET" == "network" || "$TARGET" == "all" || -z "$TARGET" ]]; then
        if [ -f "$BT_PID_FILE" ]; then
            kill $(cat "$BT_PID_FILE") 2>/dev/null
            rm -f "$BT_PID_FILE"
        fi
        (bluetoothctl scan off > /dev/null 2>&1) &
    fi
    exit 0
fi

if [[ "$ACTION" == "open" || "$ACTION" == "toggle" ]]; then
    CURRENT_MODE=$(cat "$NETWORK_MODE_FILE" 2>/dev/null)

    if [[ "$TARGET" == "network" ]]; then
        handle_network_prep
        [[ -n "$SUBTARGET" ]] && echo "$SUBTARGET" > "$NETWORK_MODE_FILE"
        echo "$ACTION:$TARGET:$SUBTARGET" > "$IPC_FILE"
        exit 0
    fi

    if [[ "$TARGET" == "wallpaper" ]]; then
        handle_wallpaper_prep
        echo "$ACTION:$TARGET:$WALLPAPER_THUMB" > "$IPC_FILE"
    else
        echo "$ACTION:$TARGET:$SUBTARGET" > "$IPC_FILE"
    fi
    exit 0
fi
