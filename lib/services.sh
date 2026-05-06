#!/usr/bin/env bash

setup_display_manager_service() {
    [[ "$INSTALL_SDDM" == true || "$REPLACE_DM" == true ]] || return
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Configuring Display Manager..."
    if [[ "$REPLACE_DM" == true ]]; then
        local DMS=("lightdm" "gdm" "gdm3" "lxdm" "lxdm-gtk3" "ly")
        for dm in "${DMS[@]}"; do
            if systemctl is-enabled "$dm.service" &>/dev/null \
                || systemctl is-active "$dm.service" &>/dev/null; then
                echo "  -> Disabling conflicting Display Manager: $dm"
                sudo systemctl disable "$dm.service" 2>/dev/null || true
                sudo pacman -Rns --noconfirm "$dm" >/dev/null 2>&1 || true
            fi
        done
    fi
    if [[ "$INSTALL_SDDM" == true ]]; then
        sudo systemctl enable sddm.service -f
        printf "  -> SDDM enabled successfully %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
}

setup_sddm_theme() {
    [[ "$SETUP_SDDM_THEME" == true ]] || return
    _setup_sddm_theme
}

_setup_sddm_theme() {
    [ -d "$REPO_DIR/.config/sddm/themes/matugen-minimal" ] || return

    sudo mkdir -p /usr/share/sddm/themes/matugen-minimal
    sudo cp -r "$REPO_DIR/.config/sddm/themes/matugen-minimal/"* /usr/share/sddm/themes/matugen-minimal/

    cat <<EOF | sudo tee /usr/share/sddm/themes/matugen-minimal/Colors.qml >/dev/null
pragma Singleton
import QtQuick
QtObject {
    readonly property color base: "#1e1e2e"
    readonly property color crust: "#11111b"
    readonly property color mantle: "#181825"
    readonly property color text: "#cdd6f4"
    readonly property color subtext0: "#a6adc8"
    readonly property color surface0: "#313244"
    readonly property color surface1: "#45475a"
    readonly property color surface2: "#585b70"
    readonly property color mauve: "#cba6f7"
    readonly property color red: "#f38ba8"
    readonly property color peach: "#fab387"
    readonly property color blue: "#89b4fa"
    readonly property color green: "#a6e3a1"
}
EOF
    sudo chown "$USER:$USER" /usr/share/sddm/themes/matugen-minimal/Colors.qml

    sudo mkdir -p /etc/sddm.conf.d
    if [[ "$SDDM_WAYLAND" == true ]]; then
        cat <<EOF | sudo tee /etc/sddm.conf.d/10-wayland-matugen.conf >/dev/null
[Theme]
Current=matugen-minimal

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1
EOF
    else
        cat <<EOF | sudo tee /etc/sddm.conf.d/10-wayland-matugen.conf >/dev/null
[Theme]
Current=matugen-minimal
EOF
    fi

    printf "  -> SDDM Theme configured %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
}

setup_audio() {
    sudo systemctl --global enable pipewire wireplumber pipewire-pulse 2>/dev/null || true
    systemctl --user start pipewire wireplumber pipewire-pulse 2>/dev/null || true

    sudo systemctl enable --now swayosd-libinput-backend.service 2>/dev/null || true
    printf "  -> SwayOSD libinput backend enabled %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
}

setup_easyeffects() {
    if [ -f "$HOME/.config/systemd/user/easyeffects.service" ]; then
        systemctl --user stop easyeffects.service 2>/dev/null || true
        rm -f "$HOME/.config/systemd/user/easyeffects.service"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    systemctl --user enable easyeffects.service 2>/dev/null || true
    printf "  -> EasyEffects daemon service enabled %-12s ${C_GREEN}[ OK ]${RESET}\n" ""
}

setup_network() {
    sudo systemctl enable NetworkManager.service
    printf "  -> NetworkManager enabled %-20s ${C_GREEN}[ OK ]${RESET}\n" ""
    sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
    printf "  -> Power Profiles Daemon enabled %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
}

setup_zsh() {
    [ "$INSTALL_ZSH" = true ] && command -v zsh &>/dev/null || return

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
    chsh -s "$(which zsh)" "$USER"

    if [ -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ]; then
        sed -i '/# Load User Aliases/d' "$HOME/.zshrc"
        sed -i "\|source $TARGET_CONFIG_DIR/zsh/user_aliases.zsh|d" "$HOME/.zshrc"
        echo -e "\n# Load User Aliases" >> "$HOME/.zshrc"
        echo "source $TARGET_CONFIG_DIR/zsh/user_aliases.zsh" >> "$HOME/.zshrc"
    fi

    printf "  -> Zsh set as default shell %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
}

compile_templates() {
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Compiling .conf files from Templates..."
    local watcher="$TARGET_CONFIG_DIR/hypr/scripts/settings_watcher.sh"
    if [ -f "$watcher" ]; then
        chmod +x "$watcher"
        bash "$watcher" --compile
    fi
}

save_version_state() {
    cat <<EOF > "$VERSION_FILE"
LOCAL_VERSION="$DOTS_VERSION"
LAST_COMMIT="$NEW_COMMIT"
WEATHER_API_KEY="$WEATHER_API_KEY"
WEATHER_CITY_ID="$WEATHER_CITY_ID"
WEATHER_UNIT="$WEATHER_UNIT"
DRIVER_CHOICE="$DRIVER_CHOICE"
KB_LAYOUTS="$KB_LAYOUTS"
KB_LAYOUTS_DISPLAY="$KB_LAYOUTS_DISPLAY"
KB_OPTIONS="$KB_OPTIONS"
WALLPAPER_DIR="$WALLPAPER_DIR"
TELEMETRY_ID="$TELEMETRY_ID"
EOF
    rm -f ~/.cache/qs_update_pending
    rm -f ~/.cache/wallpaper_initialized
    printf "  -> Configuration and version state saved %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
}