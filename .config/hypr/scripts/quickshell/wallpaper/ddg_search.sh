#!/usr/bin/env bash

QUERY="$1"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CACHE_DIR="$HOME/.cache/wallpaper_picker"
SEARCH_DIR="$CACHE_DIR/search_thumbs"
MAP_FILE="$CACHE_DIR/search_map.txt"
CONTROL_FILE="/tmp/ddg_search_control"
LOG_FILE="/tmp/qs_ddg_downloader.log"

echo "=== Starting search for: $QUERY ===" > "$LOG_FILE"

# 1. Guarantee directory exists
mkdir -p "$SEARCH_DIR"

# 2. The Pipe: Python provides links, OS provides backpressure
python3 -u "$SCRIPT_DIR/get_ddg_links.py" "$QUERY" | while IFS='|' read -r thumb_url full_url; do
    
    # 3. Safely read control file
    state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    
    if [[ "$state" == "stop" ]]; then 
        echo "Stop signal received. Exiting." >> "$LOG_FILE"
        exit 0 
    fi
    
    while [[ "$state" == "pause" ]]; do
        sleep 1
        state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    done

    if [ -z "$thumb_url" ] || [ -z "$full_url" ]; then continue; fi

    # =========================================================================
    # PRE-FLIGHT CHECK ON THE FULL URL
    # =========================================================================
    target_headers=$(curl -s -I -L -m 3 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$full_url")
    target_type=$(echo "$target_headers" | grep -i "content-type:" | tail -n 1 | tr -d '\r')

    if [[ ! "$target_type" =~ "image/" ]]; then
        echo "Skip: Full URL is dead or HTML ($target_type) -> $full_url" >> "$LOG_FILE"
        continue
    fi
    # =========================================================================

    uuid=$(date +%s%N)
    ext="${full_url##*.}"
    ext="${ext%%\?*}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    if [[ ! "$ext" =~ ^(jpg|jpeg|png|webp|gif)$ ]]; then ext="jpg"; fi

    is_webp=0
    if [[ "$ext" == "webp" ]]; then
        is_webp=1
        ext="jpg"
    fi

    filename="ddg_${uuid}.${ext}"
    filepath="$SEARCH_DIR/$filename"
    tmppath="${filepath}.tmp"

    echo "Downloading Thumb: $thumb_url -> $filename" >> "$LOG_FILE"

    # 4. TIMEOUT ADDED: -m 5 prevents permanent freezing on stalled connections
    curl -s -L -m 5 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$thumb_url" -o "$tmppath"

    # 5. Check state again AFTER the curl block
    state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    if [[ "$state" == "stop" ]]; then 
        echo "Stop signal received during download. Discarding." >> "$LOG_FILE"
        rm -f "$tmppath"
        exit 0 
    fi

    # 6. Verify the thumbnail itself is valid and not corrupted
    if [ -s "$tmppath" ]; then
        actual_mime=$(file -b --mime-type "$tmppath")
        
        if [[ ! "$actual_mime" =~ ^image/ ]]; then
            echo "ERROR: Thumb is not an image ($actual_mime). Discarding." >> "$LOG_FILE"
            rm -f "$tmppath"
        else
            if [[ "$actual_mime" == "image/webp" ]] || [ $is_webp -eq 1 ]; then
                magick "$tmppath" "$filepath" 2>/dev/null || mv "$tmppath" "$filepath"
                rm -f "$tmppath"
            else
                mv "$tmppath" "$filepath"
            fi
            echo "$filename|$full_url" >> "$MAP_FILE"
            echo "Success: $filename saved." >> "$LOG_FILE"
        fi
    else
        echo "ERROR: Failed or empty download for $thumb_url" >> "$LOG_FILE"
        rm -f "$tmppath"
    fi
done

echo "=== Pipeline finished ===" >> "$LOG_FILE"
