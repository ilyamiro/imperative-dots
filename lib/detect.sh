
#!/usr/bin/env bash
 
detect_os() {
    if [ ! -f /etc/os-release ]; then
        echo -e "${C_RED}Cannot detect OS. /etc/os-release not found.${RESET}"
        exit 1
    fi
 
    DETECTED_OS=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
    OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
 
    case "$DETECTED_OS" in
        arch|endeavouros|manjaro|cachyos|parch|garuda)
            OS="$DETECTED_OS"
            ;;
        fedora)
            echo -e "${C_RED}Unsupported OS ($DETECTED_OS). This script strictly supports Arch Linux and its derivatives.${RESET}"
            echo -e "${C_YELLOW}Fedora install scripts coming soon.${RESET}"
            exit 1
            ;;
        *)
            echo -e "${C_RED}Unsupported OS ($DETECTED_OS). This script strictly supports Arch Linux and its derivatives.${RESET}"
            exit 1
            ;;
    esac
}
 
detect_hardware() {
    USER_NAME=$USER
    CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
 
    GPU_RAW=$(lspci -nn | grep -iE 'vga|3d|display')
    GPU_INFO=$(echo "$GPU_RAW" | cut -d: -f3 | sed -E 's/ \(rev [0-9a-f]+\)//g' | xargs)
    [[ -z "$GPU_INFO" ]] && GPU_INFO="Unknown / Virtual Machine"
 
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
}
 
detect_user_dirs() {
    USER_PICTURES_DIR=""
 
    if [ -f "$HOME/.config/user-dirs.dirs" ]; then
        USER_PICTURES_DIR=$(grep '^XDG_PICTURES_DIR' "$HOME/.config/user-dirs.dirs" \
            | cut -d= -f2 | tr -d '"' | sed "s|\$HOME|$HOME|g")
    fi
    if [[ -z "$USER_PICTURES_DIR" || "$USER_PICTURES_DIR" == "$HOME" ]]; then
        USER_PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null)"
    fi
    if [[ -z "$USER_PICTURES_DIR" || "$USER_PICTURES_DIR" == "$HOME" ]]; then
        USER_PICTURES_DIR="$HOME/Pictures"
    fi
    USER_PICTURES_DIR="${USER_PICTURES_DIR%/}"
 
    USER_VIDEOS_DIR=""
 
    if [ -f "$HOME/.config/user-dirs.dirs" ]; then
        USER_VIDEOS_DIR=$(grep '^XDG_VIDEOS_DIR' "$HOME/.config/user-dirs.dirs" \
            | cut -d= -f2 | tr -d '"' | sed "s|\$HOME|$HOME|g")
    fi
    if [[ -z "$USER_VIDEOS_DIR" || "$USER_VIDEOS_DIR" == "$HOME" ]]; then
        USER_VIDEOS_DIR="$(xdg-user-dir VIDEOS 2>/dev/null)"
    fi
    if [[ -z "$USER_VIDEOS_DIR" || "$USER_VIDEOS_DIR" == "$HOME" ]]; then
        USER_VIDEOS_DIR="$HOME/Videos"
    fi
    USER_VIDEOS_DIR="${USER_VIDEOS_DIR%/}"
 
    WALLPAPER_DIR="$USER_PICTURES_DIR/Wallpapers"
}
 
detect_display_manager() {
    local DM_SERVICES=("gdm" "gdm3" "lightdm" "sddm" "lxdm" "lxdm-gtk3" "ly")
    CURRENT_DM=""
    for dm in "${DM_SERVICES[@]}"; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
            CURRENT_DM="$dm"
            break
        fi
    done
}
