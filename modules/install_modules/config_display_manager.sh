
config_display_manager(){
    if [[ "$INSTALL_SDDM" == true || "$SETUP_SDDM_THEME" == true || "$REPLACE_DM" == true ]]; then
        echo -e "\n${C_CYAN}[ INFO ]${RESET} Configuring Display Manager..."
    fi

    if [[ "$REPLACE_DM" == true ]]; then
        # Disable and uninstall any conflicting managers
        DMS=("lightdm" "gdm" "gdm3" "lxdm" "lxdm-gtk3" "ly")
        for dm in "${DMS[@]}"; do
            if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
                echo "  -> Disabling conflicting Display Manager: $dm"
                sudo systemctl disable "$dm.service" --now 2>/dev/null || true
                sudo pacman -Rns --noconfirm "$dm" > /dev/null 2>&1 || true
            fi
        done
    fi

    if [[ "$INSTALL_SDDM" == true ]]; then
        sudo systemctl enable sddm.service -f
        printf "  -> SDDM enabled successfully %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
        
        # Fix for SDDM black screen on logout (forces dangling wayland session processes to close)
        echo "  -> Applying systemd logind workaround for Wayland logout black screens..."
        sudo sed -i 's/^#*KillUserProcesses=.*/KillUserProcesses=yes/' /etc/systemd/logind.conf
        sudo systemctl restart systemd-logind 2>/dev/null || true
    fi
}


