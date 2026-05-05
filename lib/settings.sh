#!/usr/bin/env bash

sync_settings() {
    echo -e "  -> Syncing installer-owned fields to settings.json..."

    local MERGED_BINDS_JSON MERGED_STARTUPS_JSON
    MERGED_BINDS_JSON=$(_merge_keybinds)
    MERGED_STARTUPS_JSON=$(_merge_startups)
    MERGED_STARTUPS_JSON=$(_apply_once "$MERGED_STARTUPS_JSON")

    _write_settings "$MERGED_BINDS_JSON" "$MERGED_STARTUPS_JSON"
}

_merge_keybinds() {
    local UPSTREAM_BINDS_JSON="[]"
    local LOCAL_BINDS_JSON="[]"
    local UPSTREAM_KEYBINDS_CONF="$REPO_DIR/.config/hypr/config/keybindings.conf"

    if [ "$OPT_OVERRIDE_KEYBINDS" = true ] && [ -f "$UPSTREAM_KEYBINDS_CONF" ]; then
        echo -e "  -> Parsing upstream keybindings.conf (Override ON)..."
        local TMP_BINDS
        TMP_BINDS=$(mktemp)

        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            [[ ! "$line" =~ ^[[:space:]]*bind ]] && continue

            local bind_type rest mods key disp cmd
            bind_type="${line%%=*}"; bind_type="${bind_type// /}"
            rest="${line#*=}"
            IFS=',' read -r mods key disp cmd <<< "$rest"
            mods=$(_trim "$mods"); key=$(_trim "$key")
            disp=$(_trim "$disp"); cmd=$(_trim "$cmd")

            jq -c -n \
                --arg t "$bind_type" --arg m "$mods" \
                --arg k "$key" --arg d "$disp" --arg c "$cmd" \
                '{type: $t, mods: $m, key: $k, dispatcher: $d, command: $c}' >> "$TMP_BINDS"
        done < "$UPSTREAM_KEYBINDS_CONF"

        [ -s "$TMP_BINDS" ] && UPSTREAM_BINDS_JSON=$(jq -s '.' "$TMP_BINDS")
        rm -f "$TMP_BINDS"
    fi

    [ -f "$SETTINGS_FILE" ] && \
        LOCAL_BINDS_JSON=$(jq '.keybinds // []' "$SETTINGS_FILE" 2>/dev/null || echo "[]")

    if [ "$OPT_OVERRIDE_KEYBINDS" = true ]; then
        jq -n --argjson local "$LOCAL_BINDS_JSON" --argjson up "$UPSTREAM_BINDS_JSON" '
            ($local | map({key: (.mods + "|" + .key), value: .}) | from_entries) as $ld |
            ($up   | map({key: (.mods + "|" + .key), value: .}) | from_entries) as $ud |
            ($ld * $ud) | map(.)'
    else
        jq -n --argjson local "$LOCAL_BINDS_JSON" --argjson up "$UPSTREAM_BINDS_JSON" '
            ($local | map({key: (.mods + "|" + .key), value: .}) | from_entries) as $ld |
            ($up   | map({key: (.mods + "|" + .key), value: .}) | from_entries) as $ud |
            ($ud * $ld) | map(.)'
    fi
}

_merge_startups() {
    local UPSTREAM_STARTUPS_JSON="[]"
    local LOCAL_STARTUPS_JSON="[]"
    local UPSTREAM_STARTUPS_CONF="$REPO_DIR/.config/hypr/config/autostart.conf"

    if [ "$OPT_OVERRIDE_STARTUPS" = true ] && [ -f "$UPSTREAM_STARTUPS_CONF" ]; then
        echo -e "  -> Parsing upstream autostart.conf (Override ON)..."
        local TMP_STARTUPS
        TMP_STARTUPS=$(mktemp)

        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            [[ ! "$line" =~ ^[[:space:]]*exec-once[[:space:]]*= ]] && continue
            local cmd="${line#*=}"
            cmd=$(_trim "$cmd")
            [[ "$cmd" == *"qs_manager.sh toggle guide"* ]] && continue
            jq -c -n --arg c "$cmd" '{command: $c}' >> "$TMP_STARTUPS"
        done < "$UPSTREAM_STARTUPS_CONF"

        [ -s "$TMP_STARTUPS" ] && UPSTREAM_STARTUPS_JSON=$(jq -s '.' "$TMP_STARTUPS")
        rm -f "$TMP_STARTUPS"
    fi

    [ -f "$SETTINGS_FILE" ] && \
        LOCAL_STARTUPS_JSON=$(jq '.startup // []' "$SETTINGS_FILE" 2>/dev/null || echo "[]")

    if [ "$OPT_OVERRIDE_STARTUPS" = true ]; then
        echo "$UPSTREAM_STARTUPS_JSON"
    else
        jq -n --argjson local "$LOCAL_STARTUPS_JSON" --argjson up "$UPSTREAM_STARTUPS_JSON" '
            $local + ($up | map(
                select(.command as $cmd | ($local | map(.command) | index($cmd)) == null)
            ))'
    fi
}

_apply_once() {
    local MERGED_STARTUPS_JSON="$1"
    local APPLY_ONCE_SOURCE="$REPO_DIR/.config/hypr/config/apply_once.conf"
    local APPLY_ONCE_TARGET="$TARGET_CONFIG_DIR/hypr/config/apply_once.conf"

    [ -f "$APPLY_ONCE_SOURCE" ] || { echo "$MERGED_STARTUPS_JSON"; return; }

    [ ! -f "$APPLY_ONCE_TARGET" ] && cp "$APPLY_ONCE_SOURCE" "$APPLY_ONCE_TARGET"

    local CURRENT_CMDS
    CURRENT_CMDS=$(jq -r '.startup[]?.command // empty' "$SETTINGS_FILE" 2>/dev/null)

    local APPLY_ONCE_ENTRIES=()
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        [[ ! "$line" =~ ^[[:space:]]*exec-once[[:space:]]*= ]] && continue
        local cmd="${line#*=}"
        cmd=$(_trim "$cmd")
        [ -z "$cmd" ] && continue
        echo "$CURRENT_CMDS" | grep -qxF "$cmd" || APPLY_ONCE_ENTRIES+=("$cmd")
    done < "$APPLY_ONCE_SOURCE"

    for cmd in "${APPLY_ONCE_ENTRIES[@]}"; do
        MERGED_STARTUPS_JSON=$(jq --arg c "$cmd" \
            'if map(.command) | index($c) == null then . += [{command: $c}] else . end' \
            <<< "$MERGED_STARTUPS_JSON")
        echo "exec-once = $cmd" >> "$APPLY_ONCE_TARGET"
    done

    echo "$MERGED_STARTUPS_JSON"
}

_write_settings() {
    local MERGED_BINDS_JSON="$1"
    local MERGED_STARTUPS_JSON="$2"

    if [ -f "$SETTINGS_FILE" ]; then
        local tmp_json
        tmp_json=$(mktemp)
        if jq \
            --arg langs "$KB_LAYOUTS" \
            --arg wpdir "$WALLPAPER_DIR" \
            --arg kbopt "$KB_OPTIONS" \
            --argjson binds "$MERGED_BINDS_JSON" \
            --argjson startup "$MERGED_STARTUPS_JSON" \
            '.language = $langs | .wallpaperDir = $wpdir | .kbOptions = $kbopt
             | .keybinds = $binds | .startup = $startup' \
            "$SETTINGS_FILE" > "$tmp_json"; then
            mv "$tmp_json" "$SETTINGS_FILE"
            printf "  -> settings.json updated (merged keybinds + startup, user fields preserved) %-3s \e[32m[ OK ]\e[0m\n" ""
        else
            echo -e "  -> \e[31mFailed to update settings.json. Continuing...\e[0m"
            rm -f "$tmp_json"
        fi
    else
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        if jq -n \
            --arg langs "$KB_LAYOUTS" \
            --arg wpdir "$WALLPAPER_DIR" \
            --arg kbopt "$KB_OPTIONS" \
            --argjson binds "$MERGED_BINDS_JSON" \
            --argjson startup "$MERGED_STARTUPS_JSON" \
            '{uiScale: 1.0, openGuideAtStartup: true, topbarHelpIcon: true,
              wallpaperDir: $wpdir, language: $langs, kbOptions: $kbopt,
              keybinds: $binds, startup: $startup, monitors: []}' > "$SETTINGS_FILE"; then
            printf "  -> settings.json rebuilt from scratch %-4s \e[32m[ OK ]\e[0m\n" ""
        else
            echo -e "  -> \e[31mFailed to create settings.json. Check syntax.\e[0m"
        fi
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