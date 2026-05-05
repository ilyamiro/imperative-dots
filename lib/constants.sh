#!/usr/bin/env bash

# ==============================================================================
# Version
# ==============================================================================
DOTS_VERSION="1.7.2"
VERSION_FILE="$HOME/.local/state/imperative-dots-version"

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
# URLs
# ==============================================================================
REPO_URL="https://github.com/ilyamiro/imperative-dots"
WORKER_URL="https://dots-telemetry.ilyamiro-work.workers.dev"
WALLPAPER_REPO="https://github.com/ilyamiro/shell-wallpapers.git"

# ==============================================================================
# Paths
# ==============================================================================
CLONE_DIR="$HOME/.hyprland-dots"
TARGET_CONFIG_DIR="$HOME/.config"

# ==============================================================================
# Package List
# ==============================================================================
ARCH_PKGS=(
    "hyprland" "hypridle" "kitty" "cava" "zbar" "pavucontrol" "alsa-utils" "awww" "networkmanager-dmenu-git"
    "wl-clipboard" "fd" "qt6-multimedia" "qt6-5compat" "ripgrep"
    "cliphist" "jq" "socat" "inotify-tools" "pamixer" "brightnessctl" "acpi" "iw"
    "bluez" "bluez-utils" "libnotify" "networkmanager" "lm_sensors" "bc"
    "pipewire" "wireplumber" "pipewire-pulse" "pipewire-alsa" "pipewire-jack" "libpulse" "python"
    "imagemagick" "wget" "file" "git" "psmisc"
    "matugen-bin" "ffmpeg" "fastfetch" "quickshell-git" "unzip" "python-websockets" "qt6-websockets"
    "grim" "playerctl" "satty" "yq" "xdg-desktop-portal-gtk" "slurp" "mpvpaper"
    "wmctrl" "power-profiles-daemon" "easyeffects" "swayosd-git" "nautilus" "lsp-plugins" "hyprpolkitagent"
    "qt5-wayland" "qt5-quickcontrols" "qt5-quickcontrols2" "qt5-graphicaleffects" "qt6-wayland"
    "qt5ct" "qt6ct" "gpu-screen-recorder" "adw-gtk-theme"
)