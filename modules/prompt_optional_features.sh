
prompt_optional_features() {
    draw_header
    echo -e "${BOLD}${C_CYAN}=== Optional Component Setup ===${RESET}\n"

    echo -e "${BOLD}1. Display Manager Integration${RESET}"
    
    # Detect current display manager
    DM_SERVICES=("gdm" "gdm3" "lightdm" "sddm" "lxdm" "lxdm-gtk3" "ly")
    CURRENT_DM=""
    for dm in "${DM_SERVICES[@]}"; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
            CURRENT_DM="$dm"
            break
        fi
    done

    if [[ -z "$CURRENT_DM" ]]; then
        read -p "No display manager detected. Do you want to install and enable SDDM? (y/N): " choice_sddm
        if [[ "$choice_sddm" =~ ^[Yy]$ ]]; then
            INSTALL_SDDM=true
            SETUP_SDDM_THEME=true
            PKGS+=("sddm")
            echo -e "${C_GREEN}>> SDDM added to queue.${RESET}\n"
        else
            echo ""
        fi
    elif [[ "$CURRENT_DM" == "sddm" ]]; then
        echo -e "Current session manager: ${C_YELLOW}sddm${RESET}"
        read -p "Do you want to ADD a theme (don't remove the old ones)? (y/N): " choice_theme
        if [[ "$choice_theme" =~ ^[Yy]$ ]]; then
            SETUP_SDDM_THEME=true
            echo -e "${C_GREEN}>> SDDM theme queued.${RESET}\n"
        else
            echo ""
        fi
    else
        echo -e "Current session manager: ${C_YELLOW}${CURRENT_DM}${RESET}"
        read -p "Do you want to replace it with SDDM? (y/N): " choice_replace
        if [[ "$choice_replace" =~ ^[Yy]$ ]]; then
            INSTALL_SDDM=true
            REPLACE_DM=true
            SETUP_SDDM_THEME=true
            PKGS+=("sddm")
            echo -e "${C_GREEN}>> SDDM added to queue (will replace $CURRENT_DM).${RESET}\n"
        else
            echo ""
        fi
    fi

    echo -e "${BOLD}2. Neovim Matugen Configuration${RESET}"
    echo -e "${C_YELLOW}WARNING: If you use your own Neovim configuration, it will be overwritten/backed up.${RESET}"
    read -p "Do you want to install this Neovim configuration? (y/N): " choice_nvim
    if [[ "$choice_nvim" =~ ^[Yy]$ ]]; then
        INSTALL_NVIM=true
        PKGS+=("neovim" "lua-language-server" "unzip" "nodejs" "npm" "python3")
        echo -e "${C_GREEN}>> Neovim added to queue.${RESET}\n"
    fi

    echo -e "${BOLD}3. Zsh Shell${RESET}"
    read -p "Do you want to install Zsh? (y/N): " choice_zsh
    if [[ "$choice_zsh" =~ ^[Yy]$ ]]; then
        INSTALL_ZSH=true
        PKGS+=("zsh")
        echo -e "${C_GREEN}>> Zsh added to queue.${RESET}\n"
    fi
    sleep 1.5
}