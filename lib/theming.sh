#!/usr/bin/env bash

deploy_cava_wrapper() {
    mkdir -p "$HOME/.local/bin"
    if [ -f "$REPO_DIR/utils/bin/cava" ]; then
        cp "$REPO_DIR/utils/bin/cava" "$HOME/.local/bin/cava"
        chmod +x "$HOME/.local/bin/cava"
        printf "  -> Deployed Cava wrapper %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
}

install_fonts() {
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing Fonts..."
    local TARGET_FONTS_DIR="$HOME/.local/share/fonts"
    local REPO_FONTS_DIR="$REPO_DIR/.local/share/fonts"
    mkdir -p "$TARGET_FONTS_DIR"

    [ -d "$REPO_FONTS_DIR" ] && cp -r "$REPO_FONTS_DIR/"* "$TARGET_FONTS_DIR/" 2>/dev/null || true

    if [ -d "$TARGET_FONTS_DIR/IosevkaNerdFont" ] \
        && [ "$(ls -A "$TARGET_FONTS_DIR/IosevkaNerdFont" 2>/dev/null | grep -i "\.ttf")" ]; then
        echo -e "  -> ${C_GREEN}Iosevka Nerd Fonts already installed. Skipping download.${RESET}"
    else
        mkdir -p /tmp/iosevka-pack
        printf "  -> Downloading latest full Iosevka Nerd Font pack... \n"
        curl -fLo /tmp/iosevka-pack/Iosevka.zip \
            https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.zip
        unzip -q /tmp/iosevka-pack/Iosevka.zip -d /tmp/iosevka-pack/
        mkdir -p "$TARGET_FONTS_DIR/IosevkaNerdFont"
        mv /tmp/iosevka-pack/*.ttf "$TARGET_FONTS_DIR/IosevkaNerdFont/"
        sudo cp -r "$TARGET_FONTS_DIR/IosevkaNerdFont" /usr/share/fonts/
        rm -rf /tmp/iosevka-pack
        rm -f "$TARGET_FONTS_DIR/IosevkaNerdFont/"*Mono*.ttf
    fi

    find "$TARGET_FONTS_DIR" -type f -exec chmod 644 {} \; 2>/dev/null
    find "$TARGET_FONTS_DIR" -type d -exec chmod 755 {} \; 2>/dev/null
    command -v fc-cache &>/dev/null && fc-cache -f "$TARGET_FONTS_DIR" >/dev/null 2>&1
    printf "  -> Font cache updated %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
}

apply_system_adaptations() {
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Adapting configurations to your specific system..."
    rm -f "$HOME/.cache/wallpaper_initialized"

    local HYPR_CONF="$TARGET_CONFIG_DIR/hypr/hyprland.conf"
    local WP_QML="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper/WallpaperPicker.qml"
    local ZSH_RC="$HOME/.zshrc"

    _adapt_battery
    _adapt_hyprland_conf "$HYPR_CONF"
    _patch_wallpaper_qml "$WP_QML"
    _replace_swww
    _adapt_zsh "$ZSH_RC"
}

_adapt_battery() {
    local QS_BAT_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/battery"
    local REPO_BAT_DIR="$REPO_DIR/.config/hypr/scripts/quickshell/battery"

    echo -e "  -> Checking chassis for battery presence..."
    if ls /sys/class/power_supply/BAT* 1>/dev/null 2>&1; then
        echo -e "  -> ${C_GREEN}Battery detected.${RESET} Keeping Laptop Battery widget."
        [ -f "$REPO_BAT_DIR/BatteryPopup.qml" ] && \
            cp -f "$REPO_BAT_DIR/BatteryPopup.qml" "$QS_BAT_DIR/BatteryPopup.qml" 2>/dev/null || true
    else
        echo -e "  -> ${C_YELLOW}No battery detected (Desktop system).${RESET} Swapping to System Monitor widget."
        [ -f "$REPO_BAT_DIR/BatteryPopupAlt.qml" ] && \
            cp -f "$REPO_BAT_DIR/BatteryPopupAlt.qml" "$QS_BAT_DIR/BatteryPopup.qml" 2>/dev/null || true
    fi
}

_adapt_hyprland_conf() {
    local HYPR_CONF="$1"

    if [ ! -f "$HYPR_CONF" ]; then
        echo -e "${C_RED}Warning: hyprland.conf not found at $HYPR_CONF${RESET}"
        return
    fi

    # Keyboard layout
    echo -e "  -> Applying Keyboard configuration to hyprland.conf..."
    sed -i -E "s/^[[:space:]]*kb_layout[[:space:]]*=.*/    kb_layout = $KB_LAYOUTS/" "$HYPR_CONF"
    if [ -n "$KB_OPTIONS" ]; then
        sed -i -E "s/^[[:space:]]*kb_options[[:space:]]*=.*/    kb_options = $KB_OPTIONS/" "$HYPR_CONF"
    else
        sed -i -E "s/^[[:space:]]*kb_options[[:space:]]*=.*/    kb_options = /" "$HYPR_CONF"
    fi

    # Env injection
    _inject_env_conf "$HYPR_CONF"

    # Ensure env.conf is sourced
    if ! grep -q "env.conf" "$HYPR_CONF"; then
        echo -e "  -> Adding source directive for env.conf to hyprland.conf..."
        sed -i '1s/^/source = ~\/.config\/hypr\/config\/env.conf\n/' "$HYPR_CONF"
    fi

    # Restore cursor block if missing
    if ! grep -q "cursor {" "$HYPR_CONF"; then
        echo -e "  -> Restoring deleted cursor block..."
        cat <<EOF >> "$HYPR_CONF"

cursor {
    no_warps = true
}
EOF
    fi
}

_inject_env_conf() {
    local HYPR_CONF="$1"
    local ENV_CONF="$TARGET_CONFIG_DIR/hypr/config/env.conf"
    mkdir -p "$(dirname "$ENV_CONF")"

    echo -e "  -> Applying Environment Variables safely to env.conf..."

    # Clean up legacy injections from hyprland.conf
    sed -i '/^# === DOTFILES AUTO-INJECTED ENV ===/,/^# === END DOTFILES ENV ===/d' "$HYPR_CONF"
    sed -i '/env = WALLPAPER_DIR/d;/env = SCRIPT_DIR/d;/env = QT_QPA_PLATFORMTHEME/d' "$HYPR_CONF"
    sed -i '/env = XDG_PICTURES_DIR/d;/env = XDG_VIDEOS_DIR/d' "$HYPR_CONF"

    cat <<EOF > "$ENV_CONF"
# === DOTFILES AUTO-INJECTED ENV ===
env = XDG_PICTURES_DIR,$USER_PICTURES_DIR
env = XDG_VIDEOS_DIR,$USER_VIDEOS_DIR
env = WALLPAPER_DIR,$WALLPAPER_DIR
env = SCRIPT_DIR,$HOME/.config/hypr/scripts
env = QT_QPA_PLATFORMTHEME,qt6ct
EOF

    if [ "$GPU_VENDOR" == "NVIDIA" ]; then
        echo -e "  -> Applying safe NVIDIA variables..."
        cat <<EOF >> "$ENV_CONF"
env = ELECTRON_OZONE_PLATFORM_HINT,auto
env = __NV_PRIME_RENDER_OFFLOAD,1
env = __NV_PRIME_RENDER_OFFLOAD_PROVIDER,NVIDIA-G0
env = __GL_GSYNC_ALLOWED,0
env = __GL_VRR_ALLOWED,0
env = __GL_SHADER_DISK_CACHE,1
env = __GL_SHADER_DISK_CACHE_PATH,$HOME/.cache/nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = LIBVA_DRIVER_NAME,nvidia
EOF
        echo -e "\n${BOLD}${C_YELLOW}[?] NVIDIA GPU Detected.${RESET}"
        read -p "Enable aggressive/experimental NVIDIA env vars? (y/N): " < /dev/tty inject_agg
        if [[ "$inject_agg" =~ ^[Yy]$ ]]; then
            echo -e "  -> Applying aggressive NVIDIA variables..."
            cat <<EOF >> "$ENV_CONF"
env = WLR_DRM_DEVICES,/dev/dri/card0:/dev/dri/card1
env = QSG_RHI_BACKEND,vulkan
EOF
        else
            echo -e "  -> ${DIM}Skipping aggressive NVIDIA variables.${RESET}"
        fi
    fi

    echo "# === END DOTFILES ENV ===" >> "$ENV_CONF"
}

_patch_wallpaper_qml() {
    local WP_QML="$1"
    [ -f "$WP_QML" ] || return
    sed -i 's/ \+--source-color-index 0//g' "$WP_QML"
    sed -i 's/matugen image "[^"]*"/& --source-color-index 0/g' "$WP_QML"
}

_replace_swww() {
    [ -d "$TARGET_CONFIG_DIR/hypr/scripts" ] || return
    find "$TARGET_CONFIG_DIR/hypr/scripts" -type f \
        -exec sed -i -e 's/swww-daemon/awww-daemon/g' -e 's/swww/awww/g' {} +
}

_adapt_zsh() {
    local ZSH_RC="$1"
    [ -f "$ZSH_RC" ] || return
    sed -i '/# Dynamic System Paths/d;/export WALLPAPER_DIR=/d;/export SCRIPT_DIR=/d' "$ZSH_RC"
    echo -e "\n# Dynamic System Paths" >> "$ZSH_RC"
    echo "export WALLPAPER_DIR=\"$WALLPAPER_DIR\"" >> "$ZSH_RC"
    echo "export SCRIPT_DIR=\"$HOME/.config/hypr/scripts\"" >> "$ZSH_RC"
    sed -i "s/OS_LOGO_PLACEHOLDER/${OS}_small/g" "$ZSH_RC"
}

setup_gtk_qt() {
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Configuring GTK and Qt Theming Engines..."

    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true

    mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
    echo '@import url("file://'"$HOME"'/.cache/matugen/colors-gtk.css");' > "$HOME/.config/gtk-3.0/gtk.css"
    echo '@import url("file://'"$HOME"'/.cache/matugen/colors-gtk.css");' > "$HOME/.config/gtk-4.0/gtk.css"

    cat <<EOF > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=adw-gtk3-dark
EOF

    cat <<EOF > "$HOME/.config/gtk-4.0/settings.ini"
[Settings]
gtk-application-prefer-dark-theme=1
EOF

    mkdir -p "$HOME/.config/qt5ct/colors" "$HOME/.config/qt5ct/qss"
    mkdir -p "$HOME/.config/qt6ct/colors" "$HOME/.config/qt6ct/qss"

    cat <<EOF > "$HOME/.config/qt5ct/qt5ct.conf"
[Appearance]
color_scheme_path=$HOME/.config/qt5ct/colors/matugen.conf
custom_palette=true
standard_dialogs=default
style=Fusion
stylesheets=$HOME/.config/qt5ct/qss/matugen-style.qss

[Interface]
stylesheets=$HOME/.config/qt5ct/qss/matugen-style.qss
EOF

    cat <<EOF > "$HOME/.config/qt6ct/qt6ct.conf"
[Appearance]
color_scheme_path=$HOME/.config/qt6ct/colors/matugen.conf
custom_palette=true
standard_dialogs=default
style=Fusion
stylesheets=$HOME/.config/qt6ct/qss/matugen-style.qss

[Interface]
stylesheets=$HOME/.config/qt6ct/qss/matugen-style.qss
EOF

    printf "  -> Matugen GTK & Qt environment initialized %-4s ${C_GREEN}[ OK ]${RESET}\n" ""
}

print_completion() {
    echo -e "\n${BOLD}${C_GREEN}"
    cat << "EOF"
 ___ _  _ ___ _____ _   _    _      _ _____ ___ ___  _  _    ___ ___  __  __ ___ _    ___ _____ ___ 
|_ _| \| / __|_   _/_\ | |  | |    /_\_   _|_ _/ _ \| \| |  / __/ _ \ | \/  | _ \ |  | __|_   _| __|
 | || .` \__ \ | |/ _ \| |__| |__ / _ \| |  | | (_) | .` | | (_| (_) | |\/| |  _/ |__| _|  | | | _| 
|___|_|\_|___/ |_/_/ \_\____|____/_/ \_\_| |___\___/|_|\_|  \___\___/|_|  |_|_| |____|___| |_| |___|
EOF
    echo -e "${RESET}\n"
    echo -e "${BOLD}${C_MAGENTA}=================================================================${RESET}"
    echo -e "${BOLD}${C_YELLOW} Support the Creator:${RESET}"
    echo -e " ${BOLD}${C_CYAN}Ko-fi:${RESET} https://ko-fi.com/ilyamiro"
    echo -e "${BOLD}${C_MAGENTA}=================================================================${RESET}\n"

    if [ ${#FAILED_PKGS[@]} -ne 0 ]; then
        echo -e "${BOLD}${C_RED}The following packages were NOT installed:${RESET}"
        for fp in "${FAILED_PKGS[@]}"; do
            echo -e "  - ${C_YELLOW}$fp${RESET}"
        done
        echo ""
    fi

    echo -e "Old configurations backed up to: ${C_CYAN}$BACKUP_DIR${RESET}"
    echo -e "Please log out and log back in, or restart Hyprland to apply all changes."
}