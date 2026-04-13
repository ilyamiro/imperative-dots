install_drivers(){
    if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
        echo -e "  -> ${C_GREEN}All packages are already installed! Skipping package download phase.${RESET}\n"
    else
        echo -e "  -> ${C_YELLOW}Found ${#MISSING_PKGS[@]} missing packages to install.${RESET}"
        echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing System Packages & Drivers...\n"

        for pkg in "${MISSING_PKGS[@]}"; do
            echo -e "\n${C_CYAN}=================================================================${RESET}"
            echo -e "${C_BLUE}::${RESET} ${BOLD}Installing ${pkg}...${RESET}"
            echo -e "${C_CYAN}=================================================================${RESET}"
            
            # Arch: Pipe 'yes ""' (Enter keystrokes) to automatically choose the default provider (1)
            # Limit CARGO_BUILD_JOBS to prevent OOM errors during heavy Rust compilations (like swayosd)
            if yes "" | env CARGO_BUILD_JOBS=2 $PKG_MANAGER "$pkg"; then
                echo -e "\n${C_GREEN}[ OK ] Successfully installed ${pkg}${RESET}"
            else
                echo -e "\n${C_RED}[ FAILED ] Failed to install ${pkg}${RESET}"
                FAILED_PKGS+=("$pkg")
            fi
            sleep 0.5
        done
    fi

    # --- 1.5. Advanced Proprietary NVIDIA Setup (Only if explicitly selected) ---
    if [ "$HAS_NVIDIA_PROPRIETARY" = true ]; then
        echo -e "\n${C_CYAN}[ INFO ]${RESET} Performing Precise NVIDIA Initialization for Wayland..."
        
        # 1. Enable modeset and fbdev via modprobe (safer than hacking bootloaders)
        echo -e "  -> Injecting kernel parameters via modprobe (nvidia-drm.modeset=1 nvidia-drm.fbdev=1)..."
        echo -e "options nvidia-drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null
        
        # 2. Rebuild initramfs safely
        if command -v mkinitcpio &> /dev/null; then
            echo -e "  -> Rebuilding initramfs (mkinitcpio)..."
            # We avoid aggressive sed replacements on mkinitcpio.conf as it often breaks systems.
            # The modprobe conf is usually enough for early KMS if the modules are loaded.
            sudo mkinitcpio -P >/dev/null 2>&1
            printf "  -> Mkinitcpio rebuild successful %-9s ${C_GREEN}[ OK ]${RESET}\n" ""
        elif command -v dracut &> /dev/null; then
            echo -e "  -> Rebuilding initramfs (dracut)..."
            sudo dracut --force >/dev/null 2>&1
            printf "  -> Dracut rebuild successful %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
        fi
    fi
}

