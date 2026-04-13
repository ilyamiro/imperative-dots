#!/usr/bin/env bash

# ==============================================================================
# Script Versioning & Initialization
# ==============================================================================
DOTS_VERSION="1.0.8"
VERSION_FILE="$HOME/.local/state/imperative-dots-version"

# Global Variables & Initial States (Defaults)
WALLPAPER_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Wallpapers"
WEATHER_API_KEY=""
WEATHER_CITY_ID=""
WEATHER_UNIT=""
FAILED_PKGS=()

INSTALL_NVIM=false
INSTALL_ZSH=false
INSTALL_SDDM=false
REPLACE_DM=false
SETUP_SDDM_THEME=false

DRIVER_CHOICE="None (Skipped)"
DRIVER_PKGS=()
HAS_NVIDIA_PROPRIETARY=false

# Submenu Completion Tracking
VISITED_PKGS=false
VISITED_OVERVIEW=false
VISITED_WEATHER=false
VISITED_DRIVERS=false
VISITED_KEYBOARD=false

# Keyboard State Defaults
KB_LAYOUTS="us"
KB_LAYOUTS_DISPLAY="English (US)"
KB_OPTIONS="grp:alt_shift_toggle"

mkdir -p "$(dirname "$VERSION_FILE")"

# Load previous choices if the file exists
if [ -f "$VERSION_FILE" ]; then
    source "$VERSION_FILE"
    if [ -n "$LOCAL_VERSION" ]; then
        if [ -n "$KB_LAYOUTS" ]; then VISITED_KEYBOARD=true; fi
        if [ -n "$WEATHER_API_KEY" ]; then VISITED_WEATHER=true; fi
        if [ "$DRIVER_CHOICE" != "None (Skipped)" ] && [ -n "$DRIVER_CHOICE" ]; then VISITED_DRIVERS=true; fi
    fi
else
    LOCAL_VERSION="Not Installed"
fi

# ==============================================================================
# Terminal UI Colors & Formatting
# ==============================================================================
RESET="\e[0m"
BOLD="\e[1m"
DIM="\e[2m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_MAGENTA="\e[35m"

# ==============================================================================
# Package Arrays
# ==============================================================================
ARCH_PKGS=(
    "hyprland" "weston" "kitty" "cava" "rofi-wayland" "swaync" 
    "pavucontrol" "alsa-utils" "awww" "networkmanager-dmenu-git"
    "wl-clipboard" "fd" "qt6-multimedia" "qt6-5compat" "ripgrep"
    "cliphist" "jq" "socat" "inotify-tools" "pamixer" "brightnessctl" "acpi" "iw"
    "bluez" "bluez-utils" "libnotify" "networkmanager" "lm_sensors" "bc" 
    "pipewire" "wireplumber" "pipewire-pulse" "pipewire-alsa" "pipewire-jack" "libpulse" "python"
    "imagemagick" "wget" "file" "git" "psmisc"
    "matugen-bin" "ffmpeg" "fastfetch" "quickshell-git" "unzip" "python-websockets" "qt6-websockets"
    "grim" "playerctl" "satty" "yq" "xdg-desktop-portal-gtk" "slurp" "mpvpaper"
    "wmctrl" "power-profiles-daemon" "easyeffects" "swayosd-git" "nautilus" "lsp-plugins"
    # SDDM / Qt Dependencies to prevent greeter crashes on Wayland
    "qt5-wayland" "qt5-quickcontrols" "qt5-quickcontrols2" "qt5-graphicaleffects" "qt6-wayland"
)

# ==============================================================================
# Early Distro Detection & TUI Dependency Bootstrap
# ==============================================================================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${C_RED}Cannot detect OS. /etc/os-release not found.${RESET}"
    exit 1
fi

case $OS in
    arch|endeavouros|manjaro|cachyos)
        PKGS=("${ARCH_PKGS[@]}")
        
        # 1. Ensure basic pacman tools are present
        if ! command -v fzf &> /dev/null || ! command -v lspci &> /dev/null || ! command -v jq &> /dev/null || ! command -v curl &> /dev/null; then
            echo -e "${C_CYAN}Bootstrapping TUI dependencies (fzf, pciutils, jq, curl)...${RESET}"
            sudo pacman -Sy --noconfirm --needed fzf pciutils jq curl > /dev/null 2>&1
        fi

        # 2. Ensure multilib is enabled for lib32-* driver support
        if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
            echo -e "${C_CYAN}Enabling multilib repository for 32-bit driver support...${RESET}"
            sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
            sudo pacman -Sy --noconfirm > /dev/null 2>&1
        fi
        
        # 3. Automatically install 'yay' if no AUR helper is found on a clean system
        if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
            echo -e "${C_CYAN}Installing 'yay' (AUR helper) to fetch custom packages...${RESET}"
            sudo pacman -S --noconfirm --needed base-devel git
            git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin > /dev/null 2>&1
            (cd /tmp/yay-bin && makepkg -si --noconfirm > /dev/null 2>&1)
            rm -rf /tmp/yay-bin
        fi
        
        # 4. Set the correct package manager
        if command -v yay &> /dev/null; then
            PKG_MANAGER="yay -S --noconfirm --needed"
        elif command -v paru &> /dev/null; then
            PKG_MANAGER="paru -S --noconfirm --needed"
        else
            PKG_MANAGER="sudo pacman -S --noconfirm --needed"
        fi
        ;;
    *)
        echo -e "${C_RED}Unsupported OS ($OS). This script strictly supports Arch Linux and its derivatives.${RESET}"
        exit 1
        ;;
esac

# ==============================================================================
# Hardware Information Gathering & Universal GPU Detection
# ==============================================================================
USER_NAME=$USER
OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)

# Detect ALL GPUs (VGA, 3D, and Display controllers) instead of just the first one
GPU_RAW=$(lspci -nn | grep -iE 'vga|3d|display')

# Flatten multi-line output into a single string and strip revision info for a cleaner TUI
GPU_INFO=$(echo "$GPU_RAW" | cut -d: -f3 | sed -E 's/ \(rev [0-9a-f]+\)//g' | xargs)
[[ -z "$GPU_INFO" ]] && GPU_INFO="Unknown / Virtual Machine"

# Categorize GPU for the driver menu
GPU_VENDOR="Unknown / Generic VM"
if echo "$GPU_INFO" | grep -qi "nvidia"; then
    GPU_VENDOR="NVIDIA"
elif echo "$GPU_INFO" | grep -qi "amd\|radeon"; then
    GPU_VENDOR="AMD"
elif echo "$GPU_INFO" | grep -qi "intel"; then
    GPU_VENDOR="INTEL"
elif echo "$GPU_INFO" | grep -qi "vmware\|virtualbox\|qxl\|virtio\|bochs"; then
    GPU_VENDOR="VM"
fi