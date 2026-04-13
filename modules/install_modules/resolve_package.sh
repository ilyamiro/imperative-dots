

# --- 0. Resolve Package Conflicts ---
resolve_package(){
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Resolving potential package conflicts..."
    # Added 'jack', 'jack2', and 'go-yq' here to prevent installation hangs
    CONFLICTING_PKGS=("swayosd" "quickshell" "matugen" "jack" "jack2" "go-yq")
    for cpkg in "${CONFLICTING_PKGS[@]}"; do
        if pacman -Qq | grep -qx "$cpkg"; then
            echo -e "  -> ${C_YELLOW}Removing conflicting package '$cpkg'...${RESET}"
            # Stop potential running services to prevent file locks
            systemctl --user stop "$cpkg" 2>/dev/null || true
            sudo systemctl stop "$cpkg" 2>/dev/null || true
            
            # Attempt safe removal first, fallback to forcing if dependency locked
            if ! sudo pacman -Rns --noconfirm "$cpkg" > /dev/null 2>&1; then
                echo -e "  -> ${DIM}Dependencies blocking clean removal, forcing removal of '$cpkg'...${RESET}"
                sudo pacman -Rdd --noconfirm "$cpkg" > /dev/null 2>&1
            fi
        fi
    done
}
