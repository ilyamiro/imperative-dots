

copy_dotfiles(){
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Applying Configurations & Backing Up Old Ones..."
    TARGET_CONFIG_DIR="$HOME/.config"
    BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"

    CONFIG_FOLDERS=("cava" "hypr" "kitty" "rofi" "swaync" "matugen" "zsh" "swayosd")
    if [ "$INSTALL_NVIM" = true ]; then CONFIG_FOLDERS+=("nvim"); fi

    mkdir -p "$TARGET_CONFIG_DIR" "$BACKUP_DIR"

    for folder in "${CONFIG_FOLDERS[@]}"; do
        TARGET_PATH="$TARGET_CONFIG_DIR/$folder"
        SOURCE_PATH="$REPO_DIR/.config/$folder"

        if [ -d "$SOURCE_PATH" ]; then
            if [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ]; then
                mv "$TARGET_PATH" "$BACKUP_DIR/$folder"
            fi
            cp -r "$SOURCE_PATH" "$TARGET_PATH"
            printf "  -> Copied %-31s ${C_GREEN}[ OK ]${RESET}\n" "$folder"
        fi
    done

    if [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
        ENV_TARGET_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar"
        mkdir -p "$ENV_TARGET_DIR"
    
    # Write the .env file with all gathered parameters
    cat <<EOF > "$ENV_TARGET_DIR/.env"
# OpenWeather API Configuration
OPENWEATHER_KEY=${WEATHER_API_KEY}
OPENWEATHER_CITY_ID=${WEATHER_CITY_ID}
OPENWEATHER_UNIT=${WEATHER_UNIT}
EOF
        
        chmod 600 "$ENV_TARGET_DIR/.env"
        printf "  -> Saved Weather API config to .env %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi

    # Deploy Cava Wrapper
    mkdir -p "$HOME/.local/bin"
    if [ -f "$REPO_DIR/utils/bin/cava" ]; then
        cp "$REPO_DIR/utils/bin/cava" "$HOME/.local/bin/cava"
        chmod +x "$HOME/.local/bin/cava"
        printf "  -> Deployed Cava wrapper %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi

    # Enable Pipewire natively for the user environment
    # Using --global prevents silent failures when testers run this script from a TTY (without an active DBUS session)
    sudo systemctl --global enable pipewire wireplumber pipewire-pulse 2>/dev/null || true
    # Attempt to start it locally if DBUS is available (fails silently in TTY, which is fine since --global catches the next login)
    systemctl --user start pipewire wireplumber pipewire-pulse 2>/dev/null || true

    if [ "$INSTALL_ZSH" = true ] && command -v zsh &> /dev/null; then
        if [ -f "$HOME/.zshrc" ]; then
            echo -e "  -> Extracting existing aliases from ~/.zshrc..."
            mkdir -p "$TARGET_CONFIG_DIR/zsh"
            grep "^alias " "$HOME/.zshrc" > "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" || true
            if [ -s "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ]; then
                printf "  -> Custom aliases backed up %-16s ${C_GREEN}[ OK ]${RESET}\n" ""
            else
                rm -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh"
            fi
        fi

        cp "$TARGET_CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"
        chsh -s $(which zsh) "$USER"

        if [ -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ]; then
            echo -e "\n# Load User Aliases" >> "$HOME/.zshrc"
            echo "source $TARGET_CONFIG_DIR/zsh/user_aliases.zsh" >> "$HOME/.zshrc"
        fi

        printf "  -> Zsh set as default shell %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
}

