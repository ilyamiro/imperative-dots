#!/usr/bin/env bash

# ==============================================================================
# Script Versioning & Initialization
# ==============================================================================
DOTS_VERSION="1.0.1"
VERSION_FILE="$HOME/.local/state/imperative-dots-version"

mkdir -p "$(dirname "$VERSION_FILE")"

if [ -f "$VERSION_FILE" ]; then
    LOCAL_VERSION=$(cat "$VERSION_FILE")
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
# Global Variables & Initial States
# ==============================================================================
KB_SHORTCUT_DISPLAY="Not Set"
KB_HYPR_CONF=""
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
WEATHER_API_KEY=""
FAILED_PKGS=()

INSTALL_SWAYOSD=false
INSTALL_NVIM=false
INSTALL_ZSH=false

# ==============================================================================
# Package Arrays
# ==============================================================================
ARCH_PKGS=(
    "hyprland" "kitty" "cava" "rofi-wayland" "swaync" 
    "pavucontrol" "alsa-utils" "swww" "networkmanager-dmenu-git"
    "wl-clipboard" "fd" "qt6-multimedia" "qt6-5compat" "ripgrep"
    "cliphist" "jq" "socat" "pamixer" "brightnessctl" "acpi" "iw"
    "bluez" "bluez-utils" "libnotify" "networkmanager" "lm_sensors" "bc" 
    "pulseaudio-alsa" "ladspa" "imagemagick" "wget" "file" "git" "psmisc"
    "matugen-bin" "ffmpeg" "fastfetch" "quickshell-git"
    "grim" "playerctl" "satty" "yq" "xdg-desktop-portal-gtk" "slurp" "mpvpaper"
    "wmctrl" "power-profiles-daemon"
)

FEDORA_PKGS=(
    "hyprland" "kitty" "cava" "rofi-wayland" "swaync" 
    "pavucontrol" "alsa-utils" "swww" "networkmanager-dmenu"
    "wl-clipboard" "fd-find" "qt6-qtmultimedia" "qt6-qt5compat" "ripgrep"
    "cliphist" "jq" "socat" "pamixer" "brightnessctl" "acpi" "iw"
    "bluez" "bluez-tools" "libnotify" "NetworkManager" "lm_sensors" "bc" 
    "pulseaudio-utils" "ladspa" "imagemagick" "wget" "file" "git" "psmisc"
    "matugen" "ffmpeg" "fastfetch" "quickshell"
    "grim" "playerctl" "satty" "yq" "xdg-desktop-portal-gtk" "slurp" "mpvpaper"
    "wmctrl" "power-profiles-daemon"
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
        if ! command -v fzf &> /dev/null || ! command -v lspci &> /dev/null; then
            echo -e "${C_CYAN}Bootstrapping TUI dependencies (fzf, pciutils)...${RESET}"
            sudo pacman -Sy --noconfirm --needed fzf pciutils > /dev/null 2>&1
        fi
        
        # 2. Automatically install 'yay' if no AUR helper is found on a clean system
        if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
            echo -e "${C_CYAN}Installing 'yay' (AUR helper) to fetch custom packages...${RESET}"
            sudo pacman -S --noconfirm --needed base-devel git
            git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin > /dev/null 2>&1
            (cd /tmp/yay-bin && makepkg -si --noconfirm > /dev/null 2>&1)
            rm -rf /tmp/yay-bin
        fi
        
        # 3. Set the correct package manager
        if command -v yay &> /dev/null; then
            PKG_MANAGER="yay -S --noconfirm --needed"
        elif command -v paru &> /dev/null; then
            PKG_MANAGER="paru -S --noconfirm --needed"
        else
            # Fallback if AUR compilation failed for some reason
            PKG_MANAGER="sudo pacman -S --noconfirm --needed"
        fi
        ;;
    fedora)
        PKG_MANAGER="sudo dnf install -y"
        PKGS=("${FEDORA_PKGS[@]}")
        if ! command -v fzf &> /dev/null || ! command -v lspci &> /dev/null; then
            echo -e "${C_CYAN}Bootstrapping TUI dependencies (fzf, pciutils)...${RESET}"
            sudo dnf install -y fzf pciutils > /dev/null 2>&1
        fi
        ;;
    *)
        echo -e "${C_RED}Unsupported OS ($OS). This script strictly supports Arch derivatives and Fedora.${RESET}"
        exit 1
        ;;
esac

# ==============================================================================
# Hardware Information Gathering
# ==============================================================================
USER_NAME=$USER
OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
GPU_INFO=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | cut -d: -f3 | xargs | head -n 1)
[[ -z "$GPU_INFO" ]] && GPU_INFO="Unknown / Virtual Machine"

# ==============================================================================
# Interactive TUI Functions
# ==============================================================================

draw_header() {
    clear
    printf "${BOLD}${C_CYAN}"
    cat << "EOF"
 ██╗██╗  ██╗   ██╗ █████╗ ███╗   ███╗██╗██████╗  ██████╗ 
 ██║██║  ╚██╗ ██╔╝██╔══██╗████╗ ████║██║██╔══██╗██╔═══██╗
 ██║██║   ╚████╔╝ ███████║██╔████╔██║██║██████╔╝██║   ██║
 ██║██║    ╚██╔╝  ██╔══██║██║╚██╔╝██║██║██╔══██╗██║   ██║
 ██║███████╗██║   ██║  ██║██║ ╚═╝ ██║██║██║  ██║╚██████╔╝
 ╚═╝╚══════╝╚═╝   ╚═╝  ╚═╝╚═╝    ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝ 
EOF
    printf "${RESET}\n"
    printf "${C_MAGENTA}=================================================================${RESET}\n"
    printf "${BOLD} User:${RESET}            %s\n" "$USER_NAME"
    printf "${BOLD} OS:  ${RESET}            %s\n" "$OS_NAME"
    printf "${BOLD} CPU: ${RESET}            %s\n" "$CPU_INFO"
    printf "${BOLD} GPU: ${RESET}            %s\n" "$GPU_INFO"
    printf "${C_MAGENTA}-----------------------------------------------------------------${RESET}\n"
    printf "${BOLD} Server Version:${RESET}  %s\n" "$DOTS_VERSION"
    printf "${BOLD} Local Version: ${RESET}  %s\n" "$LOCAL_VERSION"
    printf "${C_MAGENTA}=================================================================${RESET}\n\n"
}

manage_packages() {
    while true; do
        draw_header
        local action
        action=$(echo -e "1. View Packages to be Installed\n2. Add Custom Packages\n3. Back to Main Menu" | fzf \
            --layout=reverse \
            --prompt="Package Manager > " \
            --header="Use ARROW KEYS and ENTER")

        case "$action" in
            *"1"*)
                echo "${PKGS[@]}" | tr ' ' '\n' | fzf \
                    --layout=reverse \
                    --prompt="Current Packages > " \
                    --header="Press ESC or ENTER to return to menu."
                ;;
            *"2"*)
                echo -e "${C_CYAN}Enter package names to add (separated by space):${RESET}"
                read -r new_pkgs
                if [ -n "$new_pkgs" ]; then
                    PKGS+=($new_pkgs)
                    echo -e "${C_GREEN}Packages added!${RESET}"
                    sleep 1
                fi
                ;;
            *"3"*) break ;;
            *) break ;;
        esac
    done
}

set_keyboard_shortcut() {
    local choice
    choice=$(echo -e "Alt + Shift\nSuper + Space\nCtrl + Shift\nCaps Lock" | fzf \
        --layout=reverse \
        --prompt="Select Layout Toggle Shortcut > " \
        --header="Select the keybind to switch languages")
    
    if [[ -n "$choice" ]]; then
        KB_SHORTCUT_DISPLAY="$choice"
        case "$choice" in
            "Alt + Shift") KB_HYPR_CONF="grp:alt_shift_toggle" ;;
            "Super + Space") KB_HYPR_CONF="grp:win_space_toggle" ;;
            "Ctrl + Shift") KB_HYPR_CONF="grp:ctrl_shift_toggle" ;;
            "Caps Lock") KB_HYPR_CONF="grp:caps_toggle" ;;
        esac
    fi
}

set_wallpaper_dir() {
    local dir
    dir=$(find "$HOME" -maxdepth 4 -type d -not -path "*/\.*" 2>/dev/null | fzf \
        --layout=reverse \
        --prompt="Select Wallpaper Directory > " \
        --header="Use ARROW KEYS. ENTER to confirm. ESC to cancel." \
        --preview="ls -la {} | head -n 20")
    
    if [[ -n "$dir" ]]; then
        WALLPAPER_DIR="$dir"
    fi
}

set_weather_api() {
    while true; do
        clear
        echo -e "${BOLD}${C_CYAN}=== OpenWeatherMap API Key Setup ===${RESET}"
        echo -e "${BOLD}${C_YELLOW}WARNING: Without this key, the weather widgets in your Quickshell setup WILL NOT WORK.${RESET}\n"
        echo -e "To get your free API key, follow these steps:"
        echo -e "  1. Go to ${BOLD}https://openweathermap.org/${RESET}"
        echo -e "  2. Create a free account."
        echo -e "  3. Generate a new key from 'My API Keys', copy it, and paste it here.\n"
        
        read -p "Enter your OpenWeather API Key (or press Enter to skip): " input_key
        
        if [[ -z "$input_key" ]]; then
            echo -e "\n${C_RED}WARNING: You did not enter an API key.${RESET}"
            read -p "Are you absolutely sure you want to proceed without it? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                WEATHER_API_KEY="Skipped"
                break
            fi
        else
            WEATHER_API_KEY="$input_key"
            echo -e "\n${C_GREEN}API Key Saved locally for installation!${RESET}"
            sleep 1.5
            break
        fi
    done
}

prompt_optional_features() {
    clear
    draw_header
    echo -e "${BOLD}${C_CYAN}=== Optional Component Setup ===${RESET}\n"

    echo -e "${BOLD}1. SwayOSD Integration${RESET}"
    read -p "Do you want to install and configure SwayOSD? (y/N): " choice_sway
    if [[ "$choice_sway" =~ ^[Yy]$ ]]; then
        INSTALL_SWAYOSD=true
        if [[ "$OS" == "fedora" ]]; then PKGS+=("swayosd"); else PKGS+=("swayosd-git"); fi
        echo -e "${C_GREEN}>> SwayOSD added to queue.${RESET}\n"
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

# ==============================================================================
# Main Menu Loop
# ==============================================================================
while true; do
    draw_header
    
    if [[ -z "$WEATHER_API_KEY" ]]; then API_DISPLAY="Not Set"
    elif [[ "$WEATHER_API_KEY" == "Skipped" ]]; then API_DISPLAY="Skipped"
    else API_DISPLAY="Set (Hidden)"; fi

    MENU_OPTION=$(echo -e "1. Manage Packages [${#PKGS[@]} queued]\n2. Set Keyboard Switcher [${KB_SHORTCUT_DISPLAY}]\n3. Set Wallpaper Dir [${WALLPAPER_DIR}]\n4. Set Weather API Key [${API_DISPLAY}]\n5. START INSTALLATION\n6. Exit" | fzf \
        --layout=reverse \
        --prompt="Main Menu > " \
        --header="Navigate with ARROWS. Select with ENTER.")

    case "$MENU_OPTION" in
        *"1"*) manage_packages ;;
        *"2"*) set_keyboard_shortcut ;;
        *"3"*) set_wallpaper_dir ;;
        *"4"*) set_weather_api ;;
        *"5"*) prompt_optional_features; break ;;
        *"6"*) clear; exit 0 ;;
        *) exit 0 ;;
    esac
done

# ==============================================================================
# Installation Process
# ==============================================================================
clear
draw_header
echo -e "${BOLD}${C_BLUE}::${RESET} ${BOLD}Starting Installation Process...${RESET}\n"

# --- 1. Install Dependencies ---
echo -e "${C_CYAN}[ INFO ]${RESET} Installing System Packages...\n"
if [[ "$OS" == "fedora" ]]; then
    sudo dnf copr enable -y errornointernet/quickshell > /dev/null 2>&1 || true
fi

TOTAL_PKGS=${#PKGS[@]}
CURRENT_PKG=0

for pkg in "${PKGS[@]}"; do
    ((CURRENT_PKG++))
    PERCENT=$((CURRENT_PKG * 100 / TOTAL_PKGS))
    BAR_WIDTH=30
    FILLED=$((PERCENT * BAR_WIDTH / 100))
    EMPTY=$((BAR_WIDTH - FILLED))
    BAR=$(printf "%${FILLED}s" | tr ' ' '█')
    SPACES=$(printf "%${EMPTY}s" | tr ' ' '-')

    # Print the loading bar state
    printf "\r${C_CYAN}[%s%s] %3d%%${RESET} | Installing %-30s" "$BAR" "$SPACES" "$PERCENT" "$pkg"

    if $PKG_MANAGER "$pkg" > /dev/null 2>&1; then
        # Overwrite with success state
        printf "\r${C_CYAN}[%s%s] %3d%%${RESET} | %-30s ${C_GREEN}[ OK ]${RESET}       \n" "$BAR" "$SPACES" "$PERCENT" "$pkg"
    else
        # Overwrite with failure state
        printf "\r${C_CYAN}[%s%s] %3d%%${RESET} | %-30s ${C_RED}[ FAILED ]${RESET}   \n" "$BAR" "$SPACES" "$PERCENT" "$pkg"
        FAILED_PKGS+=("$pkg")
    fi
done

# --- 2. Fallback Binaries ---
if [[ "$OS" == "fedora" ]]; then
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing Fallback Binaries for Fedora..."
    export PATH="$HOME/.local/bin:$PATH"
    mkdir -p "$HOME/.local/bin"
    
    for tool in "swww:LGFae/swww" "matugen:InioX/matugen"; do
        bin_name="${tool%%:*}"
        repo="${tool##*:}"
        if ! command -v "$bin_name" &> /dev/null; then
            printf "  -> Fetching %-30s " "$bin_name"
            url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep "browser_download_url" | grep "x86_64" | grep "linux" | grep -v "musl" | cut -d '"' -f 4 | head -n 1)
            if [ -n "$url" ]; then
                curl -sL "$url" -o "/tmp/$bin_name.tar.gz"
                tar -xzf "/tmp/$bin_name.tar.gz" -C "/tmp"
                find "/tmp" -type f -name "$bin_name" -exec mv {} "$HOME/.local/bin/" \;
                [[ "$bin_name" == "swww" ]] && find "/tmp" -type f -name "swww-daemon" -exec mv {} "$HOME/.local/bin/" \; 2>/dev/null
                chmod +x "$HOME/.local/bin/"*
                printf "${C_GREEN}[ OK ]${RESET}\n"
            else
                printf "${C_RED}[ FAILED ]${RESET}\n"
                FAILED_PKGS+=("$bin_name (Binary)")
            fi
        fi
    done
fi

# --- 3. Repository Cloning ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up Dotfiles Repository..."
REPO_URL="https://github.com/ilyamiro/imperative-dots.git"
CLONE_DIR="$HOME/.hyprland-dots"

# Check for a specific unique file so we don't mistake ~/.config for the repo
if [ -f "$(pwd)/install.sh" ] && [ -d "$(pwd)/.config" ]; then
    REPO_DIR="$(pwd)"
    echo "  -> Running from local repository at $REPO_DIR"
else
    if [ -d "$CLONE_DIR" ]; then
        git -C "$CLONE_DIR" pull > /dev/null 2>&1
    else
        git clone "$REPO_URL" "$CLONE_DIR" > /dev/null 2>&1
    fi
    REPO_DIR="$CLONE_DIR"
fi

# --- 4. Symlinks & Backups ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Applying Configurations & Backing Up Old Ones..."
TARGET_CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"

CONFIG_FOLDERS=("cava" "hypr" "kitty" "rofi" "swaync" "matugen" "zsh")
if [ "$INSTALL_SWAYOSD" = true ]; then CONFIG_FOLDERS+=("swayosd"); fi
if [ "$INSTALL_NVIM" = true ]; then CONFIG_FOLDERS+=("nvim"); fi

mkdir -p "$TARGET_CONFIG_DIR" "$BACKUP_DIR"

for folder in "${CONFIG_FOLDERS[@]}"; do
    TARGET_PATH="$TARGET_CONFIG_DIR/$folder"
    SOURCE_PATH="$REPO_DIR/.config/$folder"

    if [ -d "$SOURCE_PATH" ]; then
        if [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ]; then
            mv "$TARGET_PATH" "$BACKUP_DIR/$folder"
        fi
        ln -s "$SOURCE_PATH" "$TARGET_PATH"
        printf "  -> Symlinked %-28s ${C_GREEN}[ OK ]${RESET}\n" "$folder"
    fi
done

if [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
    ENV_TARGET_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar"
    mkdir -p "$ENV_TARGET_DIR"
    echo "OPENWEATHER_KEY=\"$WEATHER_API_KEY\"" > "$ENV_TARGET_DIR/.env"
    chmod 600 "$ENV_TARGET_DIR/.env"
    printf "  -> Saved Weather API key to .env %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Deploy Cava Wrapper
mkdir -p "$HOME/.local/bin"
if [ -f "$REPO_DIR/utils/bin/cava" ]; then
    cp "$REPO_DIR/utils/bin/cava" "$HOME/.local/bin/cava"
    chmod +x "$HOME/.local/bin/cava"
    printf "  -> Deployed Cava wrapper %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

if [ "$INSTALL_ZSH" = true ] && command -v zsh &> /dev/null; then
    ln -sf "$TARGET_CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"
    chsh -s $(which zsh) "$USER"
    printf "  -> Zsh set as default shell %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 5. Fonts ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing Fonts..."
TARGET_FONTS_DIR="$HOME/.local/share/fonts"
REPO_FONTS_DIR="$REPO_DIR/.local/share/fonts"
mkdir -p "$TARGET_FONTS_DIR"

if [ -d "$REPO_FONTS_DIR" ]; then
    cp -r "$REPO_FONTS_DIR/"* "$TARGET_FONTS_DIR/" 2>/dev/null || true
    if command -v fc-cache &> /dev/null; then
        fc-cache -f "$TARGET_FONTS_DIR"
        printf "  -> Font cache updated %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
fi

# --- 6. Apply TUI User Preferences ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Writing User Preferences..."
USER_PREFS_FILE="$TARGET_CONFIG_DIR/hypr/user_prefs.conf"
mkdir -p "$(dirname "$USER_PREFS_FILE")"
echo "# Auto-generated by install script" > "$USER_PREFS_FILE"

if [ -n "$KB_HYPR_CONF" ]; then
    echo "input { kb_options = $KB_HYPR_CONF }" >> "$USER_PREFS_FILE"
fi

if [ -n "$WALLPAPER_DIR" ]; then
    echo "\$wallpaper_dir = $WALLPAPER_DIR" >> "$USER_PREFS_FILE"
fi
printf "  -> Preferences saved to user_prefs.conf ${C_GREEN}[ OK ]${RESET}\n"

# --- 7. Adaptability Phase ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Adapting configurations to your specific system..."

HYPR_CONF="$TARGET_CONFIG_DIR/hypr/hyprland.conf"
ZSH_RC="$HOME/.zshrc"
WP_QML="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper/WallpaperPicker.qml"
DIARY_MGR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar/diary_manager.sh"

if [ -f "$HYPR_CONF" ]; then
    # 1. Universal Monitor Setup
    sed -i 's/^monitor = .*/monitor = ,preferred,auto,1/' "$HYPR_CONF"

    # 2. Strip Personal App Keybindings
    sed -i '/exec, firefox/d' "$HYPR_CONF"
    sed -i '/exec, Telegram/d' "$HYPR_CONF"
    sed -i '/exec, obsidian/d' "$HYPR_CONF"

    # 3. Inject SwayOSD Autostart
    if [ "$INSTALL_SWAYOSD" = true ]; then
        sed -i '/^exec-once = swww-daemon/a exec-once = swayosd-server --top-margin 0.9 --style ~/.config/swayosd/style.css' "$HYPR_CONF"
    fi

    # 4. Inject Environment Variables for Quickshell
    sed -i "/^env = NIXOS_OZONE_WL,1/a env = WALLPAPER_DIR,$WALLPAPER_DIR\nenv = SCRIPT_DIR,$HOME/.config/hypr/scripts" "$HYPR_CONF"
else
    echo -e "${C_RED}Warning: hyprland.conf not found at $HYPR_CONF${RESET}"
fi

# 5. Patch WallpaperPicker.qml dynamically
if [ -f "$WP_QML" ]; then
    sed -i 's|Quickshell.env("HOME") + "/Images/Wallpapers"|Quickshell.env("WALLPAPER_DIR")|g' "$WP_QML"
fi

# 6. Remove Personal Diary Manager
if [ -f "$DIARY_MGR" ]; then
    rm -f "$DIARY_MGR"
fi

# 7. Zsh Dynamism
if [ -f "$ZSH_RC" ]; then
    echo -e "\n# Dynamic System Paths" >> "$ZSH_RC"
    echo "export WALLPAPER_DIR=\"$WALLPAPER_DIR\"" >> "$ZSH_RC"
    echo "export SCRIPT_DIR=\"$HOME/.config/hypr/scripts\"" >> "$ZSH_RC"
    sed -i "s/OS_LOGO_PLACEHOLDER/${OS}_small/g" "$ZSH_RC"
fi

printf "  -> System adaptations applied %-11s ${C_GREEN}[ OK ]${RESET}\n" ""

# --- 8. Finalize Version Marker ---
echo "$DOTS_VERSION" > "$VERSION_FILE"
printf "  -> Version marker updated (v%s) %-7s ${C_GREEN}[ OK ]${RESET}\n" "$DOTS_VERSION" ""

# ==============================================================================
# Final Output
# ==============================================================================
echo -e "\n${BOLD}${C_MAGENTA}=== Installation Complete ===${RESET}\n"

if [ ${#FAILED_PKGS[@]} -ne 0 ]; then
    echo -e "${BOLD}${C_RED}The following packages were NOT installed. Try building them yourself:${RESET}"
    for fp in "${FAILED_PKGS[@]}"; do
        echo -e "  - ${C_YELLOW}$fp${RESET}"
    done
    echo ""
fi

echo -e "Old configurations backed up to: ${C_CYAN}$BACKUP_DIR${RESET}"
echo -e "Please log out and log back in, or restart Hyprland to apply all changes.\n"
