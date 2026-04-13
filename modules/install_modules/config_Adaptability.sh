

config_Adaptability(){

    rm -f "$HOME/.cache/wallpaper_initialized" # if reinstalling
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Adapting configurations to your specific system..."

    HYPR_CONF="$TARGET_CONFIG_DIR/hypr/hyprland.conf"
    ZSH_RC="$HOME/.zshrc"
    WP_QML="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper/WallpaperPicker.qml"
    WP_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper"

    # -> Desktop/Laptop Battery Adaptability <-
    QS_BAT_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/battery"
    echo -e "  -> Checking chassis for battery presence..."
    if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then
        echo -e "  -> ${C_GREEN}Battery detected.${RESET} Keeping Laptop Battery widget."
    else
        echo -e "  -> ${C_YELLOW}No battery detected (Desktop system).${RESET} Swapping to System Monitor widget."
        if [ -f "$QS_BAT_DIR/BatteryPopupAlt.qml" ]; then
            mv "$QS_BAT_DIR/BatteryPopup.qml" "$QS_BAT_DIR/BatteryPopup_laptop_backup.qml" 2>/dev/null || true
            mv "$QS_BAT_DIR/BatteryPopupAlt.qml" "$QS_BAT_DIR/BatteryPopup.qml" 2>/dev/null || true
        fi
    fi

    # -> Desktop/Ethernet Network Adaptability <-
    QS_NET_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/network"
    echo -e "  -> Checking for Wi-Fi interface..."
    if ls /sys/class/net/w* 1> /dev/null 2>&1 || iw dev 2>/dev/null | grep -q Interface; then
        echo -e "  -> ${C_GREEN}Wi-Fi module detected.${RESET} Keeping standard Network widget."
    else
        echo -e "  -> ${C_YELLOW}No Wi-Fi module detected (Desktop/Ethernet).${RESET} Swapping to Alternate Network widget."
        if [ -f "$QS_NET_DIR/NetworkPopupAlt.qml" ]; then
            mv "$QS_NET_DIR/NetworkPopup.qml" "$QS_NET_DIR/NetworkPopup_wifi_backup.qml" 2>/dev/null || true
            mv "$QS_NET_DIR/NetworkPopupAlt.qml" "$QS_NET_DIR/NetworkPopup.qml" 2>/dev/null || true
        fi
    fi


    if [ -f "$HYPR_CONF" ]; then
        
        # 0. Inject Keyboard Layout Configurations dynamically
        echo -e "  -> Applying Keyboard configuration..."
        sed -i "s/^ *kb_layout =.*/    kb_layout = $KB_LAYOUTS/" "$HYPR_CONF"
        if [ -n "$KB_OPTIONS" ]; then
            sed -i "s/^ *kb_options =.*/    kb_options = $KB_OPTIONS/" "$HYPR_CONF"
        else
            sed -i "s/^ *kb_options =.*/    kb_options = /" "$HYPR_CONF"
        fi

        # 1. Inject SwayOSD Autostart (Looking for the new 'awww-daemon' entry)
        sed -i '/^exec-once = awww-daemon/a exec-once = swayosd-server --top-margin 0.9 --style ~/.config/swayosd/style.css' "$HYPR_CONF"

        # 2. Inject Environment Variables for Quickshell
        sed -i "/^env = NIXOS_OZONE_WL,1/a env = WALLPAPER_DIR,$WALLPAPER_DIR\nenv = SCRIPT_DIR,$HOME/.config/hypr/scripts" "$HYPR_CONF"
        
        # 3. Inject Advanced Nvidia specific configurations (ONLY IF PROPRIETARY IS CHOSEN)
        if [ "$HAS_NVIDIA_PROPRIETARY" = true ]; then
            sed -i '/^env = NIXOS_OZONE_WL,1/a env = LIBVA_DRIVER_NAME,nvidia\nenv = XDG_SESSION_TYPE,wayland\nenv = GBM_BACKEND,nvidia-drm\nenv = __GLX_VENDOR_LIBRARY_NAME,nvidia\nenv = WLR_NO_HARDWARE_CURSORS,1\ncursor {\n    no_hardware_cursors = true\n}' "$HYPR_CONF"
        fi
    else
        echo -e "${C_RED}Warning: hyprland.conf not found at $HYPR_CONF${RESET}"
    fi

    # 4. Patch WallpaperPicker.qml dynamically
    if [ -f "$WP_QML" ]; then
        # Injecting the properly evaluated bash variable straight into the QML instead of the hardcoded Quickshell.env string
        sed -i "s|Quickshell.env(\"HOME\") + \"/Pictures/Wallpapers\"|\"$WALLPAPER_DIR\"|g" "$WP_QML"
    fi

    # 5. Rename all instances of swww to awww in quickshell/wallpaper files
    if [ -d "$WP_DIR" ]; then
        find "$WP_DIR" -type f -exec sed -i 's/swww/awww/g' {} +
    fi

    # 6. Zsh Dynamism
    if [ -f "$ZSH_RC" ]; then
        echo -e "\n# Dynamic System Paths" >> "$ZSH_RC"
        echo "export WALLPAPER_DIR=\"$WALLPAPER_DIR\"" >> "$ZSH_RC"
        echo "export SCRIPT_DIR=\"$HOME/.config/hypr/scripts\"" >> "$ZSH_RC"
        sed -i "s/OS_LOGO_PLACEHOLDER/${OS}_small/g" "$ZSH_RC"
    fi

    echo -e "\n${C_CYAN}[ INFO ]${RESET} Enabling Core System Services..."
    sudo systemctl enable NetworkManager.service
    printf "  -> NetworkManager enabled %-20s ${C_GREEN}[ OK ]${RESET}\n" ""
}

