#!/usr/bin/env bash

setup_repo() {
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up Dotfiles Repository..."

    OLD_COMMIT=""
    NEW_COMMIT=""

    if [ "$LOCAL_DEV" = true ]; then
        local SCRIPT_OWN_DIR
        SCRIPT_OWN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        SCRIPT_OWN_DIR="$(dirname "$SCRIPT_OWN_DIR")"  # go up from lib/
        if [ -d "$SCRIPT_OWN_DIR/.git" ]; then
            REPO_DIR="$SCRIPT_OWN_DIR"
            NEW_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)
            OLD_COMMIT="$LAST_COMMIT"
            echo "  -> [--local] Using local version: $REPO_DIR, git pull skipped"
        else
            echo -e "${C_RED}[--local] .git was not found near the script ($SCRIPT_OWN_DIR).${RESET}"
            exit 1
        fi
    elif [ -f "$(pwd)/install.sh" ] && [ -d "$(pwd)/.config" ] && [ -d "$(pwd)/.git" ] \
        && [ "$(pwd)" != "$CLONE_DIR" ] && [ "$(pwd)" != "$HOME" ]; then
        REPO_DIR="$(pwd)"
        echo "  -> Running from local development repository at $REPO_DIR"
        NEW_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)
        OLD_COMMIT="$LAST_COMMIT"
    else
        if [ -d "$CLONE_DIR" ]; then
            OLD_COMMIT="$LAST_COMMIT"
            git -C "$CLONE_DIR" fetch --all >/dev/null 2>&1
            git -C "$CLONE_DIR" checkout "$TARGET_BRANCH" >/dev/null 2>&1
            git -C "$CLONE_DIR" reset --hard "origin/$TARGET_BRANCH" >/dev/null 2>&1
            NEW_COMMIT=$(git -C "$CLONE_DIR" rev-parse HEAD 2>/dev/null)
        else
            OLD_COMMIT="$LAST_COMMIT"
            git clone -b "$TARGET_BRANCH" --progress "$REPO_URL" "$CLONE_DIR" 2>&1 \
                | tr '\r' '\n' | while read -r line; do
                    if [[ "$line" =~ Receiving\ objects:\ *([0-9]+)% ]]; then
                        local pc="${BASH_REMATCH[1]}"
                        local fill empty
                        fill=$(printf "%*s" $((pc / 2)) "" | tr ' ' '#')
                        empty=$(printf "%*s" $((50 - (pc / 2))) "" | tr ' ' '-')
                        printf "\r\033[K  -> Downloading repo: [%s%s] %3d%%" "$fill" "$empty" "$pc"
                    fi
                done
            echo ""
            NEW_COMMIT=$(git -C "$CLONE_DIR" rev-parse HEAD 2>/dev/null)
        fi
        REPO_DIR="$CLONE_DIR"
    fi
}

fetch_wallpapers() {
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Fetching Wallpapers..."
    mkdir -p "$WALLPAPER_DIR"

    if [ "$(ls -A "$WALLPAPER_DIR" 2>/dev/null | grep -E '\.(jpg|png|jpeg|gif|webp)$')" ]; then
        echo -e "  -> ${C_GREEN}Wallpapers already present in $WALLPAPER_DIR. Skipping download.${RESET}"
        return
    fi

    local WALLPAPER_CLONE_DIR="/tmp/shell-wallpapers"
    [ -d "$WALLPAPER_CLONE_DIR" ] && rm -rf "$WALLPAPER_CLONE_DIR"

    if [[ "$OPT_WALLPAPERS" == true ]]; then
        git clone --progress "$WALLPAPER_REPO" "$WALLPAPER_CLONE_DIR" 2>&1 \
            | tr '\r' '\n' | while read -r line; do
                if [[ "$line" =~ Receiving\ objects:\ *([0-9]+)% ]]; then
                    local pc="${BASH_REMATCH[1]}"
                    local fill empty
                    fill=$(printf "%*s" $((pc / 2)) "" | tr ' ' '#')
                    empty=$(printf "%*s" $((50 - (pc / 2))) "" | tr ' ' '-')
                    printf "\r\033[K  -> Downloading: [%s%s] %3d%%" "$fill" "$empty" "$pc"
                fi
            done
        echo ""
        if [ -d "$WALLPAPER_CLONE_DIR/images" ]; then
            cp -r "$WALLPAPER_CLONE_DIR/images/"* "$WALLPAPER_DIR/" 2>/dev/null || true
        else
            cp -r "$WALLPAPER_CLONE_DIR/"* "$WALLPAPER_DIR/" 2>/dev/null || true
        fi
        rm -rf "$WALLPAPER_CLONE_DIR"
        printf "  -> Full wallpaper pack installed to %-12s ${C_GREEN}[ OK ]${RESET}\n" "$WALLPAPER_DIR"
    else
        echo -e "  -> ${C_CYAN}Fetching 3 random wallpapers to save time...${RESET}"
        mkdir -p "$WALLPAPER_CLONE_DIR"
        (
            cd "$WALLPAPER_CLONE_DIR" || exit
            git init -q
            git remote add origin "$WALLPAPER_REPO"
            git fetch --depth 1 --filter=blob:none origin HEAD -q
            local RANDOM_PICS
            RANDOM_PICS=$(git ls-tree -r FETCH_HEAD --name-only \
                | grep -iE '\.(jpg|jpeg|png|gif|webp)$' | shuf -n 3)
            if [ -n "$RANDOM_PICS" ]; then
                for pic in $RANDOM_PICS; do
                    local filename
                    filename=$(basename "$pic")
                    echo -n "    -> Downloading $filename... "
                    git show FETCH_HEAD:"$pic" > "$WALLPAPER_DIR/$filename" 2>/dev/null
                    echo -e "${C_GREEN}[ DONE ]${RESET}"
                done
            else
                echo -e "    -> ${C_RED}Could not find any images in the repository.${RESET}"
            fi
        )
        rm -rf "$WALLPAPER_CLONE_DIR"
        printf "  -> Random wallpapers installed to %-12s ${C_GREEN}[ OK ]${RESET}\n" "$WALLPAPER_DIR"
    fi
}

copy_dotfiles() {
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Applying Configurations & Backing Up Old Ones..."

    BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"
    CONFIG_FOLDERS=("cava" "hypr" "kitty" "rofi" "matugen" "zsh" "swayosd")
    [ "$INSTALL_NVIM" = true ] && CONFIG_FOLDERS+=("nvim")

    mkdir -p "$TARGET_CONFIG_DIR" "$BACKUP_DIR"

    local DO_FULL_INSTALL=true
    if [ -z "$OLD_COMMIT" ]; then
        echo -e "  -> No previous commit tracked. Forcing a full overwrite."
    elif [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
        DO_FULL_INSTALL=false
        if git -C "$REPO_DIR" cat-file -t "$OLD_COMMIT" >/dev/null 2>&1; then
            echo -e "  -> Found existing installation. Analyzing updates between ${C_YELLOW}${OLD_COMMIT::7}${RESET} and ${C_YELLOW}${NEW_COMMIT::7}${RESET}..."
        else
            echo -e "  -> Previous commit missing from local tree. Forcing a full overwrite."
            DO_FULL_INSTALL=true
        fi
    else
        DO_FULL_INSTALL=false
        echo -e "  -> Repository is up to date (${C_YELLOW}${NEW_COMMIT::7}${RESET}). Only applying upstream changes (None found)."
    fi

    [ "$DO_FULL_INSTALL" = true ] && _full_install || _partial_update
}

_full_install() {
    echo "  -> Performing Full Install / Overwrite..."

    [ -f "$SETTINGS_FILE" ] && cp "$SETTINGS_FILE" "$BACKUP_DIR/settings.json.bak"

    for folder in "${CONFIG_FOLDERS[@]}"; do
        local TARGET_PATH="$TARGET_CONFIG_DIR/$folder"
        local SOURCE_PATH="$REPO_DIR/.config/$folder"
        [ -d "$SOURCE_PATH" ] || continue
        { [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ]; } && mv "$TARGET_PATH" "$BACKUP_DIR/$folder"
        cp -r "$SOURCE_PATH" "$TARGET_PATH"
        if [ -s "$BACKUP_DIR/$folder/config/apply_once.conf" ]; then
            cp "$BACKUP_DIR/$folder/config/apply_once.conf" "$TARGET_PATH/config/apply_once.conf"
        else
            rm -f "$TARGET_PATH/config/apply_once.conf"
        fi
        printf "  -> Copied %-31s ${C_GREEN}[ OK ]${RESET}\n" "$folder"
    done

    if [ -f "$BACKUP_DIR/settings.json.bak" ]; then
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        cp "$BACKUP_DIR/settings.json.bak" "$SETTINGS_FILE"
        printf "  -> Restored existing settings.json  %-12s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
}

_partial_update() {
    local CHANGED_FILES="" DELETED_FILES=""

    if [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
        CHANGED_FILES=$(git -C "$REPO_DIR" diff --name-only --no-renames --diff-filter=AM \
            "$OLD_COMMIT" "$NEW_COMMIT" | grep "^\.config/")
        DELETED_FILES=$(git -C "$REPO_DIR" diff --name-only --no-renames --diff-filter=D \
            "$OLD_COMMIT" "$NEW_COMMIT" | grep "^\.config/")
    fi

    if [ -z "$CHANGED_FILES" ] && [ -z "$DELETED_FILES" ]; then
        echo "  -> No target config files were changed upstream. Local files kept intact."
        return
    fi

    echo -e "  -> Performing ${C_GREEN}Partial Update${RESET} based on upstream changes..."

    if [ -n "$DELETED_FILES" ]; then
        echo "$DELETED_FILES" | while IFS= read -r file; do
            local FOLDER_NAME REL_PATH TARGET_FILE
            FOLDER_NAME=$(echo "$file" | cut -d'/' -f2)
            _is_managed_folder "$FOLDER_NAME" || continue
            REL_PATH="${file#\.config/}"
            TARGET_FILE="$HOME/$file"
            if [ -f "$TARGET_FILE" ]; then
                mkdir -p "$(dirname "$BACKUP_DIR/$REL_PATH")"
                cp "$TARGET_FILE" "$BACKUP_DIR/$REL_PATH"
                rm -f "$TARGET_FILE"
                echo "    -> Removed obsolete file: $file"
            fi
        done
    fi

    if [ -n "$CHANGED_FILES" ]; then
        echo "$CHANGED_FILES" | while IFS= read -r file; do
            local FOLDER_NAME REL_PATH SOURCE_FILE TARGET_FILE
            FOLDER_NAME=$(echo "$file" | cut -d'/' -f2)
            _is_managed_folder "$FOLDER_NAME" || continue
            [[ "$file" == *"settings.json" ]] && { echo "    -> Skipped (user-owned): $file"; continue; }
            REL_PATH="${file#\.config/}"
            SOURCE_FILE="$REPO_DIR/$file"
            TARGET_FILE="$HOME/$file"
            if [ -f "$TARGET_FILE" ]; then
                mkdir -p "$(dirname "$BACKUP_DIR/$REL_PATH")"
                cp "$TARGET_FILE" "$BACKUP_DIR/$REL_PATH"
            fi
            mkdir -p "$(dirname "$TARGET_FILE")"
            cp "$SOURCE_FILE" "$TARGET_FILE"
            echo "    -> Updated: $file"
        done
    fi

    printf "  -> Partial update complete %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
}

_is_managed_folder() {
    local folder="$1"
    for f in "${CONFIG_FOLDERS[@]}"; do
        [ "$f" == "$folder" ] && return 0
    done
    return 1
}

persist_weather_config() {
    local ENV_TARGET_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar"
    local OLD_ENV_IN_BACKUP="$BACKUP_DIR/hypr/scripts/quickshell/calendar/.env"

    if [[ "$KEEP_OLD_ENV" == true ]]; then
        if [ -f "$OLD_ENV_IN_BACKUP" ]; then
            mkdir -p "$ENV_TARGET_DIR"
            cp "$OLD_ENV_IN_BACKUP" "$ENV_TARGET_DIR/.env"
            printf "  -> Restored existing Weather API config from backup %-3s ${C_GREEN}[ OK ]${RESET}\n" ""
        fi
    elif [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
        _write_env_file "$ENV_TARGET_DIR"
        printf "  -> Saved Weather API config to .env %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
}

restore_qs_colors() {
    local QS_COLORS_BACKUP="$BACKUP_DIR/hypr/scripts/quickshell/qs_colors.json"
    local QS_COLORS_TARGET="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/qs_colors.json"
    if [ -f "$QS_COLORS_BACKUP" ]; then
        mkdir -p "$(dirname "$QS_COLORS_TARGET")"
        cp "$QS_COLORS_BACKUP" "$QS_COLORS_TARGET"
        printf "  -> Restored existing Quickshell colors %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
}

_write_env_file() {
    local dir="$1"
    mkdir -p "$dir"
    cat <<EOF > "$dir/.env"
# OpenWeather API Configuration
OPENWEATHER_KEY=${WEATHER_API_KEY}
OPENWEATHER_CITY_ID=${WEATHER_CITY_ID}
OPENWEATHER_UNIT=${WEATHER_UNIT}
EOF
    chmod 600 "$dir/.env"
}

bake_hardware_env() {
    echo "  -> Baking hardware environment variables into template..."
    if [ "$GPU_VENDOR" == "NVIDIA" ]; then
        NVIDIA_VARS="env = ELECTRON_OZONE_PLATFORM_HINT,auto\n\
env = __NV_PRIME_RENDER_OFFLOAD,1\n\
env = __NV_PRIME_RENDER_OFFLOAD_PROVIDER,NVIDIA-G0\n\
env = __GL_GSYNC_ALLOWED,0\n\
env = __GL_VRR_ALLOWED,0\n\
env = __GL_SHADER_DISK_CACHE,1\n\
env = __GL_SHADER_DISK_CACHE_PATH,$HOME/.cache/nvidia\n\
env = __GLX_VENDOR_LIBRARY_NAME,nvidia\n\
env = LIBVA_DRIVER_NAME,nvidia"
        sed -i "s|{{HARDWARE_ENV}}|$NVIDIA_VARS|g" "$TARGET_CONFIG_DIR/hypr/templates/env.conf.template"
    else
        sed -i "s|{{HARDWARE_ENV}}||g" "$TARGET_CONFIG_DIR/hypr/templates/env.conf.template"
    fi
}