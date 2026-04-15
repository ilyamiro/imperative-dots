#!/usr/bin/env bash

# Check interval in seconds (600s = 10 minutes)
INTERVAL=600

# Cache file to prevent notification spam if the script is restarted
CACHE_FILE="$HOME/.cache/qs_update_notified_version"

while true; do
    # Fetch local version
    LOCAL_VERSION=$(source ~/.local/state/imperative-dots-version 2>/dev/null && echo "$LOCAL_VERSION")
    LOCAL_VERSION=${LOCAL_VERSION:-"Unknown"}
    
    # Fetch remote version
    REMOTE_VERSION=$(curl -m 5 -s https://raw.githubusercontent.com/ilyamiro/imperative-dots/master/install.sh | grep '^DOTS_VERSION=' | cut -d'"' -f2)

    # Check if we got valid responses and they don't match
    if [[ -n "$REMOTE_VERSION" && "$LOCAL_VERSION" != "Unknown" && "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
        
        # Determine the newest version using bash semantic sorting
        NEWEST=$(printf '%s\n' "$LOCAL_VERSION" "$REMOTE_VERSION" | sort -V | tail -n1)
        
        if [[ "$NEWEST" == "$REMOTE_VERSION" ]]; then
            
            # Only send the notification if we haven't notified about this specific version yet
            if [[ ! -f "$CACHE_FILE" ]] || [[ "$(cat "$CACHE_FILE")" != "$REMOTE_VERSION" ]]; then
                notify-send -t 60000 -a 'Imperative Dots' -u normal 'Update Available' "A new version ($REMOTE_VERSION) is ready! Open the config guide to apply."
                
                # Cache the version so we don't spam the user every 10 minutes
                echo "$REMOTE_VERSION" > "$CACHE_FILE"
            fi
        fi
    fi

    # Wait 10 minutes before checking again
    sleep "$INTERVAL"
done
