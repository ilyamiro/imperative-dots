#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# 1. Flatten Matugen v4.0 Nested JSON for Quickshell
# ------------------------------------------------------------------------------
# Updated to match your config.toml output path
QS_JSON="~/.config/hypr/scripts/quickshell/qs_colors.json"

python3 -c '
import json
import sys

def flatten_colors(obj):
    if isinstance(obj, dict):
        if "color" in obj and isinstance(obj["color"], str):
            return obj["color"]
        return {k: flatten_colors(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [flatten_colors(x) for x in obj]
    return obj

target_file = sys.argv[1]
try:
    with open(target_file, "r") as f:
        data = json.load(f)
    
    flat_data = flatten_colors(data)
    
    with open(target_file, "w") as f:
        json.dump(flat_data, f, indent=4)
        
except FileNotFoundError:
    pass
except Exception as e:
    print(f"Error flattening JSON: {e}")
' "$QS_JSON"

# ------------------------------------------------------------------------------
# 2. Flatten Matugen v4.0 Output in Standard Text Configs
# ------------------------------------------------------------------------------
# If Tera dumped {"color": "#hex"} into your text files, this strips it to #hex.
TEXT_FILES=(
    "$HOME/.config/kitty/kitty-matugen-colors.conf"
    "$HOME/.config/nvim/matugen_colors.lua"
    "$HOME/.config/cava/colors"
    "$HOME/.config/swayosd/style.css"
    "$HOME/.config/swaync/style.css"
    "$HOME/.config/rofi/theme.rasi"
)

for file in "${TEXT_FILES[@]}"; do
    # Check if file exists and we have write permissions (avoids sudo password hangs on SDDM)
    if [ -f "$file" ] && [ -w "$file" ]; then
        # Looks for {"color": "#abcdef"} and replaces it with #abcdef
        sed -i -E 's/\{[[:space:]]*"color":[[:space:]]*"([^"]+)"[[:space:]]*\}/\1/g' "$file"
    elif [ -f "$file" ]; then
        echo "Warning: No write permission for $file (Skipping text clean-up)"
    fi
done

# ------------------------------------------------------------------------------
# 3. Reload System Components
# ------------------------------------------------------------------------------

# Reload Kitty instances
killall -USR1 kitty

# Reload CAVA
# ALWAYS rebuild the final config file from the base and newly generated colors
cat ~/.config/cava/config_base ~/.config/cava/colors > ~/.config/cava/config 2>/dev/null

# Tell CAVA to reload the config ONLY if it is currently running
if pgrep -x "cava" > /dev/null; then
    killall -USR1 cava
fi

# Reload SwayNC CSS styling dynamically without killing the daemon
if command -v swaync-client &> /dev/null; then
    swaync-client -rs
fi

# Restart swayosd-server in the background and disown it so the script doesn't hang
killall swayosd-server 2>/dev/null
swayosd-server --top-margin 0.9 --style "$HOME/.config/swayosd/style.css" > /dev/null 2>&1 &
disown
