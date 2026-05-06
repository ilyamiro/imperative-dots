#!/usr/bin/env bash

bootstrap_dependencies() {
    if ! command -v fzf &>/dev/null || ! command -v lspci &>/dev/null \
        || ! command -v jq &>/dev/null || ! command -v curl &>/dev/null; then
        echo -e "${C_CYAN}Bootstrapping TUI dependencies (fzf, pciutils, jq, curl)...${RESET}"
        sudo pacman -Sy --noconfirm --needed fzf pciutils jq curl >/dev/null 2>&1
    fi

    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo -e "${C_CYAN}Enabling multilib repository for 32-bit driver support...${RESET}"
        sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
        sudo pacman -Sy --noconfirm >/dev/null 2>&1
    fi

    if ! command -v yay &>/dev/null && ! command -v paru &>/dev/null; then
        echo -e "${C_CYAN}Installing 'yay' (AUR helper) to fetch custom packages...${RESET}"
        sudo pacman -S --noconfirm --needed base-devel git
        git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin >/dev/null 2>&1
        (cd /tmp/yay-bin && makepkg -si --noconfirm >/dev/null 2>&1)
        rm -rf /tmp/yay-bin
    fi

    if command -v yay &>/dev/null; then
        PKG_MANAGER="yay -S --noconfirm --needed"
    elif command -v paru &>/dev/null; then
        PKG_MANAGER="paru -S --noconfirm --needed"
    else
        PKG_MANAGER="sudo pacman -S --noconfirm --needed"
    fi
}

resolve_conflicts() {
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Resolving potential package conflicts..."

    for jack_pkg in jack jack2 jack2-dbus; do
        if pacman -Qq "$jack_pkg" &>/dev/null; then
            echo -e "  -> Removing conflicting package '$jack_pkg'..."
            sudo pacman -Rdd --noconfirm "$jack_pkg" 2>/dev/null || true
        fi
    done

    yes "Y" | $PKG_MANAGER pipewire-jack >/dev/null 2>&1 || true

    local CONFLICTING_PKGS=("swayosd" "quickshell" "matugen" "go-yq")
    for cpkg in "${CONFLICTING_PKGS[@]}"; do
        if pacman -Qq | grep -qx "$cpkg"; then
            echo -e "  -> ${C_YELLOW}Removing conflicting package '$cpkg'...${RESET}"
            systemctl --user stop "$cpkg" 2>/dev/null || true
            sudo systemctl stop "$cpkg" 2>/dev/null || true
            if ! sudo pacman -Rns --noconfirm "$cpkg" >/dev/null 2>&1; then
                echo -e "  -> ${DIM}Forcing removal of '$cpkg'...${RESET}"
                sudo pacman -Rdd --noconfirm "$cpkg" >/dev/null 2>&1
            fi
        fi
    done
}

install_packages() {
    local ALL_PKGS=("${PKGS[@]}" "${DRIVER_PKGS[@]}")
    local MISSING_PKGS=()

    echo -e "\n${C_CYAN}[ INFO ]${RESET} Checking for already installed packages..."
    for pkg in "${ALL_PKGS[@]}"; do
        [[ -z "$pkg" ]] && continue
        pacman -Q "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
    done

    if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
        echo -e "  -> ${C_GREEN}All packages are already installed! Skipping package download phase.${RESET}\n"
        return
    fi

    echo -e "  -> ${C_YELLOW}Found ${#MISSING_PKGS[@]} missing packages to install.${RESET}"
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing System Packages & Drivers...\n"

    local SAFE_JOBS=$(( $(nproc) / 2 ))
    [[ $SAFE_JOBS -lt 1 ]] && SAFE_JOBS=1
    [[ $SAFE_JOBS -gt 4 ]] && SAFE_JOBS=4

    for pkg in "${MISSING_PKGS[@]}"; do
        echo -e "\n${C_CYAN}=================================================================${RESET}"
        echo -e "${C_BLUE}::${RESET} ${BOLD}Installing ${pkg}...${RESET}"
        echo -e "${C_CYAN}=================================================================${RESET}"

        if yes "Y" | env CARGO_BUILD_JOBS="$SAFE_JOBS" MAKEFLAGS="-j$SAFE_JOBS" $PKG_MANAGER "$pkg"; then
            echo -e "\n${C_GREEN}[ OK ] Successfully installed ${pkg}${RESET}"
        else
            echo -e "\n${C_RED}[ FAILED ] Failed to install ${pkg}${RESET}"
            FAILED_PKGS+=("$pkg")
        fi
        sleep 0.5
    done
}

setup_nvidia() {
    [ "$HAS_NVIDIA_PROPRIETARY" = true ] || return

    echo -e "\n${C_CYAN}[ INFO ]${RESET} Performing Precise NVIDIA Initialization for Wayland..."
    echo -e "  -> Injecting kernel parameters via modprobe..."
    echo -e "options nvidia-drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia.conf >/dev/null

    if command -v mkinitcpio &>/dev/null; then
        echo -e "  -> Rebuilding initramfs (mkinitcpio)..."
        sudo mkinitcpio -P >/dev/null 2>&1
        printf "  -> Mkinitcpio rebuild successful %-9s ${C_GREEN}[ OK ]${RESET}\n" ""
    elif command -v dracut &>/dev/null; then
        echo -e "  -> Rebuilding initramfs (dracut)..."
        sudo dracut --force >/dev/null 2>&1
        printf "  -> Dracut rebuild successful %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
}