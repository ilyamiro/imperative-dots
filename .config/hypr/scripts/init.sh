#!/usr/bin/env bash

SAVED="$HOME/.cache/current_wallpaper"
RELOAD_SCRIPT_PATH="$HOME/.config/hypr/scripts/quickshell/wallpaper/matugen_reload.sh"

file=""

# Restore saved wallpaper if the path is still valid and is an image (videos need mpvpaper, skip)
if [ -f "$SAVED" ]; then
    candidate=$(cat "$SAVED")
    case "${candidate,,}" in
        *.jpg|*.jpeg|*.png|*.gif|*.webp)
            [ -f "$candidate" ] && file="$candidate"
            ;;
    esac
fi

# No valid saved wallpaper — pick randomly and persist the choice
if [ -z "$file" ]; then
    WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
    sleep 0.5
    file=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null | shuf -n 1)
    [ -n "$file" ] && { mkdir -p "$(dirname "$SAVED")"; echo "$file" > "$SAVED"; }
fi

if [ -n "$file" ]; then
    awww img "$file" --transition-type any --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 &
    matugen image "$file" --source-color-index 0

    if [ -f "$RELOAD_SCRIPT_PATH" ]; then
        chmod +x "$RELOAD_SCRIPT_PATH"
        bash "$RELOAD_SCRIPT_PATH"
    fi
fi
