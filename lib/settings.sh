#!/usr/bin/env bash

sync_settings() {
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Establishing settings.json SSoT..."
    local UPSTREAM_JSON="$REPO_DIR/.config/hypr/default_settings.json"
    local SETTINGS_FILE="$TARGET_CONFIG_DIR/hypr/settings.json"

    mkdir -p "$(dirname "$SETTINGS_FILE")"

    # Strictly validate that the old JSON is perfectly formatted
    if [ -f "$BACKUP_DIR/hypr/settings.json" ] && jq -e . "$BACKUP_DIR/hypr/settings.json" >/dev/null 2>&1; then
        OLD_JSON="$BACKUP_DIR/hypr/settings.json"
        echo "  -> Processing JSON Merges safely..."
    else
        OLD_JSON="$UPSTREAM_JSON"
        echo "  -> Generating fresh configuration from upstream defaults..."
    fi

    # Pure jq merge logic: The "Best of Both Worlds" Smart Merge
    jq -n --slurpfile local "$OLD_JSON" --slurpfile up "$UPSTREAM_JSON" \
       --arg langs "$KB_LAYOUTS" \
       --arg wpdir "$WALLPAPER_DIR" \
       --arg kbopt "$KB_OPTIONS" \
       --arg ovr_kb "$OPT_OVERRIDE_KEYBINDS" \
       --arg ovr_su "$OPT_OVERRIDE_STARTUPS" '

       $up[0] as $u |
       (if ($local | length > 0) then $local[0] else $u end) as $l |

       ($u + $l) |
       .language = $langs |
       .wallpaperDir = $wpdir |
       .kbOptions = $kbopt |

       .keybinds = (
           if $ovr_kb == "true" then
               $u.keybinds
           else
               ($l.keybinds | map(((.mods // "") + "|" + (.key // "")))) as $local_keys |
               ($l.keybinds | map(.command)) as $local_cmds |

               ($u.keybinds | map(select(
                   # Key combo must not be claimed by user
                   (((.mods // "") + "|" + (.key // "")) as $k | ($local_keys | index($k)) == null) and
                   # Command must not already exist under a different user-defined key
                   (.command as $cmd | ($local_cmds | index($cmd)) == null)
                ))) as $new_upstream |

                ($l.keybinds + $new_upstream)
           end
       ) |

       .startup = (
           if $ovr_su == "true" then
               $u.startup
           else
               ($l.startup | map(.command)) as $local_startups |
               ($u.startup | map(select(.command as $cmd | ($local_startups | index($cmd)) == null))) as $new_startups |
               ($l.startup + $new_startups)
           end
       )
    ' > "$SETTINGS_FILE"

    if ! jq -e . "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo -e "  -> ${C_RED}settings.json is invalid after merge. Check default_settings.json.${RESET}"
    else
        printf "  -> settings.json built successfully %-15s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
}

sync_state_from_settings() {
    local EXISTING_SETTINGS="$HOME/.config/hypr/settings.json"
    [ -f "$EXISTING_SETTINGS" ] && command -v jq &>/dev/null || return

    local _sj_lang _sj_kbopt _sj_wpdir
    _sj_lang=$(jq -r 'if has("language") then (.language // "") else "IGNORE_ME" end' "$EXISTING_SETTINGS" 2>/dev/null)
    _sj_kbopt=$(jq -r 'if has("kbOptions") then (.kbOptions // "") else "IGNORE_ME" end' "$EXISTING_SETTINGS" 2>/dev/null)
    _sj_wpdir=$(jq -r 'if has("wallpaperDir") then (.wallpaperDir // "") else "IGNORE_ME" end' "$EXISTING_SETTINGS" 2>/dev/null)

    if [[ "$_sj_lang" != "IGNORE_ME" ]]; then
        KB_LAYOUTS="$_sj_lang"
        if [ "$KB_LAYOUTS" != "$( (source "$VERSION_FILE" 2>/dev/null; echo "$KB_LAYOUTS") )" ] \
            || [ -z "$KB_LAYOUTS_DISPLAY" ]; then
            KB_LAYOUTS_DISPLAY="$_sj_lang"
        fi
        VISITED_KEYBOARD=true
    fi

    [[ "$_sj_kbopt" != "IGNORE_ME" ]] && KB_OPTIONS="$_sj_kbopt"

    if [[ "$_sj_wpdir" != "IGNORE_ME" ]] && [[ -n "$_sj_wpdir" ]]; then
        _sj_wpdir="${_sj_wpdir%/}"
        WALLPAPER_DIR="$_sj_wpdir"
        USER_PICTURES_DIR="$(dirname "$_sj_wpdir")"
    fi
}

_trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}