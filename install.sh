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
WALLPAPER_DIR="$HOME/Images/Wallpapers"
WEATHER_API_KEY=""
WEATHER_CITY_ID=""
WEATHER_UNIT=""
FAILED_PKGS=()

INSTALL_SWAYOSD=false
INSTALL_NVIM=false
INSTALL_ZSH=false

# ==============================================================================
# Package Arrays
# ==============================================================================
ARCH_PKGS=(
    "hyprland" "kitty" "cava" "rofi-wayland" "swaync" 
    "pavucontrol" "alsa-utils" "awww" "networkmanager-dmenu-git"
    "wl-clipboard" "fd" "qt6-multimedia" "qt6-5compat" "ripgrep"
    "cliphist" "jq" "socat" "pamixer" "brightnessctl" "acpi" "iw"
    "bluez" "bluez-utils" "libnotify" "networkmanager" "lm_sensors" "bc" 
    "pulseaudio-alsa" "ladspa" "imagemagick" "wget" "file" "git" "psmisc"
    "matugen-bin" "ffmpeg" "fastfetch" "quickshell-git" "unzip"
    "grim" "playerctl" "satty" "yq" "xdg-desktop-portal-gtk" "slurp" "mpvpaper"
    "wmctrl" "power-profiles-daemon" "easyeffects" "sddm"
)

FEDORA_PKGS=(
    "hyprland" "kitty" "cava" "rofi-wayland" "swaync" 
    "pavucontrol" "alsa-utils" "awww" "networkmanager-dmenu"
    "wl-clipboard" "fd-find" "qt6-qtmultimedia" "qt6-qt5compat" "ripgrep"
    "cliphist" "jq" "socat" "pamixer" "brightnessctl" "acpi" "iw"
    "bluez" "bluez-tools" "libnotify" "NetworkManager" "lm_sensors" "bc" 
    "pulseaudio-utils" "ladspa" "imagemagick" "wget" "file" "git" "psmisc"
    "matugen" "ffmpeg" "fastfetch" "quickshell" "unzip"
    "grim" "playerctl" "satty" "yq" "xdg-desktop-portal-gtk" "slurp" "mpvpaper"
    "wmctrl" "power-profiles-daemon" "easyeffects" "sddm"
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
            PKG_MANAGER="sudo pacman -S --noconfirm --needed"
        fi
        ;;
    fedora)
        PKG_MANAGER="sudo dnf install -y"
        PKGS=("${FEDORA_PKGS[@]}")
        if ! command -v fzf &> /dev/null || ! command -v lspci &> /dev/null || ! command -v jq &> /dev/null || ! command -v curl &> /dev/null; then
            echo -e "${C_CYAN}Bootstrapping TUI dependencies (fzf, pciutils, jq, curl)...${RESET}"
            sudo dnf install -y fzf pciutils jq curl > /dev/null 2>&1
        fi
        ;;
    *)
        echo -e "${C_RED}Unsupported OS ($OS). This script strictly supports Arch derivatives and Fedora.${RESET}"
        exit 1
        ;;
esac

# ==============================================================================
# Hardware Information Gathering & Nvidia Detection
# ==============================================================================
USER_NAME=$USER
OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
GPU_INFO=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | cut -d: -f3 | xargs | head -n 1)
[[ -z "$GPU_INFO" ]] && GPU_INFO="Unknown / Virtual Machine"

HAS_NVIDIA=false
if echo "$GPU_INFO" | grep -qi "nvidia"; then
    HAS_NVIDIA=true
    if [[ "$OS" == "fedora" ]]; then
        PKGS+=("akmod-nvidia" "xorg-x11-drv-nvidia-cuda")
    else
        PKGS+=("nvidia-dkms" "nvidia-utils" "lib32-nvidia-utils" "linux-headers")
    fi
fi

# ==============================================================================
# Interactive TUI Functions
# ==============================================================================

draw_header() {
    # Move cursor to top left (\033[H) instead of clearing screen to prevent flashing
    printf "\033[H"
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
    printf "\033[K${C_MAGENTA}=================================================================${RESET}\n"
    printf "\033[K${BOLD} User:${RESET}              %s\n" "$USER_NAME"
    printf "\033[K${BOLD} OS:  ${RESET}              %s\n" "$OS_NAME"
    printf "\033[K${BOLD} CPU: ${RESET}              %s\n" "$CPU_INFO"
    printf "\033[K${BOLD} GPU: ${RESET}              %s\n" "$GPU_INFO"
    if [ "$HAS_NVIDIA" = true ]; then
        printf "\033[K${C_GREEN}${BOLD} -> NVIDIA Detected. Drivers queued.${RESET}\n"
    fi
    printf "\033[K${C_MAGENTA}-----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD} Server Version:${RESET}  %s\n" "$DOTS_VERSION"
    printf "\033[K${BOLD} Local Version: ${RESET}  %s\n" "$LOCAL_VERSION"
    printf "\033[K${C_MAGENTA}=================================================================${RESET}\n\n"
    # \033[J clears everything below the cursor so fzf renders cleanly
    printf "\033[J"
}

manage_packages() {
    while true; do
        draw_header
        local action
        action=$(echo -e "1. View Packages to be Installed\n2. Add Custom Packages\n3. Back to Main Menu" | fzf \
            --layout=reverse \
            --height=12 \
            --prompt="Package Manager > " \
            --header="Use ARROW KEYS and ENTER")

        case "$action" in
            *"1"*)
                echo "${PKGS[@]}" | tr ' ' '\n' | fzf \
                    --layout=reverse \
                    --height=25 \
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
    draw_header
    local choice
    choice=$(echo -e "Alt + Shift\nSuper + Space\nCtrl + Shift\nCaps Lock" | fzf \
        --layout=reverse \
        --height=12 \
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

set_weather_api() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== OpenWeatherMap Interactive Setup ===${RESET}"
        echo -e "${BOLD}${C_YELLOW}WARNING: Without this, weather widgets WILL NOT WORK.${RESET}\n"
        
        read -p "Enter your OpenWeather API Key (or press Enter to skip): " input_key
        
        if [[ -z "$input_key" ]]; then
            echo -e "\n${C_RED}WARNING: You did not enter an API key.${RESET}"
            read -p "Are you absolutely sure you want to proceed without it? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                WEATHER_API_KEY="Skipped"
                WEATHER_CITY_ID=""
                WEATHER_UNIT=""
                break
            fi
            continue
        fi
        
        WEATHER_API_KEY="$input_key"
        
        echo -e "\n${C_CYAN}Let's find your exact City ID.${RESET}"
        read -p "Enter your city name (e.g., London, New York): " input_city
        
        if [[ -n "$input_city" ]]; then
            echo -e "Searching for '${input_city}'..."
            
            # Use echo -n to prevent jq from encoding a newline character which breaks the API call
            encoded_city=$(echo -n "$input_city" | jq -sRr @uri)
            api_response=$(curl -s "http://api.openweathermap.org/data/2.5/find?q=${encoded_city}&appid=${WEATHER_API_KEY}")
            
            # Validate API Key & Response
            status_code=$(echo "$api_response" | jq -r '.cod | tostring')
            if [[ "$status_code" != "200" ]]; then
                error_msg=$(echo "$api_response" | jq -r '.message')
                echo -e "\n${C_RED}API Error: ${error_msg}${RESET}"
                echo -e "Please check your API key and try again.\n"
                read -p "Press Enter to retry..."
                continue
            fi
            
            # Check if any cities matched
            count=$(echo "$api_response" | jq -r '.count')
            if [[ "$count" == "0" ]]; then
                echo -e "\n${C_RED}No cities found matching '${input_city}'.${RESET}"
                read -p "Press Enter to retry..."
                continue
            fi
            
            # Create a selection menu of matched cities
            selected_city=$(echo "$api_response" | jq -r '.list[] | "\(.id) | \(.name), \(.sys.country) (Lat: \(.coord.lat), Lon: \(.coord.lon))"' | fzf \
                --layout=reverse --height=15 \
                --prompt="Select your exact city > " \
                --header="Use ARROWS to navigate. ENTER to confirm.")
            
            if [[ -n "$selected_city" ]]; then
                WEATHER_CITY_ID=$(echo "$selected_city" | awk '{print $1}')
                city_display=$(echo "$selected_city" | cut -d'|' -f2 | xargs)
                echo -e "${C_GREEN}Selected: ${city_display} (ID: ${WEATHER_CITY_ID})${RESET}"
            else
                echo -e "${C_RED}City selection cancelled.${RESET}"
                continue
            fi
        else
            echo -e "${C_RED}City name cannot be empty.${RESET}"
            continue
        fi
        
        # Ask for standard units
        unit_choice=$(echo -e "metric (Celsius)\nimperial (Fahrenheit)\nstandard (Kelvin)" | fzf \
            --layout=reverse --height=10 \
            --prompt="Select Temperature Unit > " \
            --header="Choose your preferred unit format")
        
        WEATHER_UNIT=$(echo "$unit_choice" | awk '{print $1}')
        [[ -z "$WEATHER_UNIT" ]] && WEATHER_UNIT="metric"
        
        echo -e "\n${C_GREEN}Weather configuration complete!${RESET}"
        sleep 1.5
        break
    done
}

prompt_optional_features() {
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
# Hard clear the screen once so \033[H works perfectly from the top
clear

while true; do
    draw_header
    
    if [[ -z "$WEATHER_API_KEY" ]]; then API_DISPLAY="Not Set"
    elif [[ "$WEATHER_API_KEY" == "Skipped" ]]; then API_DISPLAY="Skipped"
    else API_DISPLAY="Set ($WEATHER_UNIT, ID: $WEATHER_CITY_ID)"; fi

    MENU_OPTION=$(echo -e "1. Manage Packages [${#PKGS[@]} queued]\n2. Set Keyboard Switcher [${KB_SHORTCUT_DISPLAY}]\n3. Set Weather API Key [${API_DISPLAY}]\n4. START INSTALLATION\n5. Exit" | fzf \
        --layout=reverse \
        --height=12 \
        --prompt="Main Menu > " \
        --header="Navigate with ARROWS. Select with ENTER.")

    case "$MENU_OPTION" in
        *"1"*) manage_packages ;;
        *"2"*) set_keyboard_shortcut ;;
        *"3"*) set_weather_api ;;
        *"4"*) prompt_optional_features; break ;;
        *"5"*) clear; exit 0 ;;
        *) exit 0 ;;
    esac
done

# ==============================================================================
# Installation Process
# ==============================================================================
clear
draw_header
echo -e "${BOLD}${C_BLUE}::${RESET} ${BOLD}Starting Installation Process...${RESET}\n"

# Pre-authenticate sudo to prevent password prompts from breaking during piped commands
echo -e "${C_CYAN}[ INFO ]${RESET} Requesting sudo privileges for installation..."
sudo -v

# --- 1. Install Dependencies ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing System Packages...\n"
if [[ "$OS" == "fedora" ]]; then
    sudo dnf copr enable -y errornointernet/quickshell > /dev/null 2>&1 || true
fi

for pkg in "${PKGS[@]}"; do
    echo -e "\n${C_CYAN}=================================================================${RESET}"
    echo -e "${C_BLUE}::${RESET} ${BOLD}Installing ${pkg}...${RESET}"
    echo -e "${C_CYAN}=================================================================${RESET}"
    
    if [[ "$OS" == "fedora" ]]; then
        if $PKG_MANAGER "$pkg"; then
            echo -e "\n${C_GREEN}[ OK ] Successfully installed ${pkg}${RESET}"
        else
            echo -e "\n${C_RED}[ FAILED ] Failed to install ${pkg}${RESET}"
            FAILED_PKGS+=("$pkg")
        fi
    else
        # Arch: Pipe 'yes ""' (Enter keystrokes) to automatically choose the default provider (1)
        # Limit CARGO_BUILD_JOBS to prevent OOM errors during heavy Rust compilations (like swayosd)
        if yes "" | env CARGO_BUILD_JOBS=2 $PKG_MANAGER "$pkg"; then
            echo -e "\n${C_GREEN}[ OK ] Successfully installed ${pkg}${RESET}"
        else
            echo -e "\n${C_RED}[ FAILED ] Failed to install ${pkg}${RESET}"
            FAILED_PKGS+=("$pkg")
        fi
    fi
    sleep 0.5
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

# --- 3. Display Manager Cleanup & SDDM Setup ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Configuring Display Manager (SDDM)..."
DMS=("lightdm" "gdm" "gdm3" "lxdm" "lxdm-gtk3" "ly")
for dm in "${DMS[@]}"; do
    if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
        echo "  -> Disabling conflicting Display Manager: $dm"
        sudo systemctl disable "$dm.service" --now 2>/dev/null || true
    fi
    # Uninstall conflicting display managers
    if [[ "$OS" == "fedora" ]]; then
        sudo dnf remove -y "$dm" > /dev/null 2>&1 || true
    else
        sudo pacman -Rns --noconfirm "$dm" > /dev/null 2>&1 || true
    fi
done

sudo systemctl enable sddm.service -f
printf "  -> SDDM enabled successfully %-14s ${C_GREEN}[ OK ]${RESET}\n" ""

# --- 4. Repository Cloning & Wallpapers ---
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

echo -e "\n${C_CYAN}[ INFO ]${RESET} Fetching Wallpapers..."
WALLPAPER_REPO="https://github.com/ilyamiro/shell-wallpapers.git"
WALLPAPER_CLONE_DIR="/tmp/shell-wallpapers"

mkdir -p "$WALLPAPER_DIR"
if [ -d "$WALLPAPER_CLONE_DIR" ]; then
    rm -rf "$WALLPAPER_CLONE_DIR"
fi
git clone "$WALLPAPER_REPO" "$WALLPAPER_CLONE_DIR" > /dev/null 2>&1
if [ -d "$WALLPAPER_CLONE_DIR/images" ]; then
    cp -r "$WALLPAPER_CLONE_DIR/images/"* "$WALLPAPER_DIR/" 2>/dev/null || true
else
    cp -r "$WALLPAPER_CLONE_DIR/"* "$WALLPAPER_DIR/" 2>/dev/null || true
fi
rm -rf "$WALLPAPER_CLONE_DIR"
printf "  -> Wallpapers installed to %-12s ${C_GREEN}[ OK ]${RESET}\n" "$WALLPAPER_DIR"

# --- 5. Copying Dotfiles & Backups ---
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
        cp -r "$SOURCE_PATH" "$TARGET_PATH"
        printf "  -> Copied %-31s ${C_GREEN}[ OK ]${RESET}\n" "$folder"
    fi
done

if [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
    ENV_TARGET_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar"
    mkdir -p "$ENV_TARGET_DIR"
    
    # Write the .env file with all gathered parameters
    cat <<EOF > "$ENV_TARGET_DIR/.env"
# OpenWeather API Configuration
OPENWEATHER_KEY=${WEATHER_API_KEY}
OPENWEATHER_CITY_ID=${WEATHER_CITY_ID}
OPENWEATHER_UNIT=${WEATHER_UNIT}
EOF
    
    chmod 600 "$ENV_TARGET_DIR/.env"
    printf "  -> Saved Weather API config to .env %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Deploy Cava Wrapper
mkdir -p "$HOME/.local/bin"
if [ -f "$REPO_DIR/utils/bin/cava" ]; then
    cp "$REPO_DIR/utils/bin/cava" "$HOME/.local/bin/cava"
    chmod +x "$HOME/.local/bin/cava"
    printf "  -> Deployed Cava wrapper %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

if [ "$INSTALL_ZSH" = true ] && command -v zsh &> /dev/null; then
    cp "$TARGET_CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"
    chsh -s $(which zsh) "$USER"
    printf "  -> Zsh set as default shell %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 6. Fonts ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing Fonts..."
TARGET_FONTS_DIR="$HOME/.local/share/fonts"
REPO_FONTS_DIR="$REPO_DIR/.local/share/fonts"
mkdir -p "$TARGET_FONTS_DIR"

# Copy any remaining local fonts (like JetBrainsMono)
if [ -d "$REPO_FONTS_DIR" ]; then
    cp -r "$REPO_FONTS_DIR/"* "$TARGET_FONTS_DIR/" 2>/dev/null || true
fi

# Iosevka Nerd Font Pack Installation
printf "  -> Creating temporary directory... \n"
mkdir -p /tmp/iosevka-pack

printf "  -> Downloading latest full Iosevka Nerd Font pack... \n"
curl -fLo /tmp/iosevka-pack/Iosevka.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.zip

printf "  -> Extracting fonts... \n"
unzip -q /tmp/iosevka-pack/Iosevka.zip -d /tmp/iosevka-pack/

printf "  -> Installing fonts to IosevkaNerdFont directory... \n"
mkdir -p "$TARGET_FONTS_DIR/IosevkaNerdFont"
mv /tmp/iosevka-pack/*.ttf "$TARGET_FONTS_DIR/IosevkaNerdFont/"

printf "  -> Cleaning up temporary files... \n"
rm -rf /tmp/iosevka-pack
rm -f ~/.local/share/fonts/IosevkaNerdFont/*Mono*.ttf

# Fix permissions so fontconfig can actually read them
find "$TARGET_FONTS_DIR" -type f -exec chmod 644 {} \; 2>/dev/null
find "$TARGET_FONTS_DIR" -type d -exec chmod 755 {} \; 2>/dev/null

if command -v fc-cache &> /dev/null; then
    # Force cache update verbosely so we ensure the system registers it
    fc-cache -f "$TARGET_FONTS_DIR" > /dev/null 2>&1
    printf "  -> Font cache updated %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 7. Apply TUI User Preferences ---
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

# --- 8. Adaptability Phase ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Adapting configurations to your specific system..."

HYPR_CONF="$TARGET_CONFIG_DIR/hypr/hyprland.conf"
ZSH_RC="$HOME/.zshrc"
WP_QML="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper/WallpaperPicker.qml"
DIARY_MGR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar/diary_manager.sh"
WP_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper"

if [ -f "$HYPR_CONF" ]; then
    # 1. Inject SwayOSD Autostart (Looking for the new 'awww-daemon' entry)
    if [ "$INSTALL_SWAYOSD" = true ]; then
        sed -i '/^exec-once = awww-daemon/a exec-once = swayosd-server --top-margin 0.9 --style ~/.config/swayosd/style.css' "$HYPR_CONF"
    fi

    # 2. Inject Environment Variables for Quickshell
    sed -i "/^env = NIXOS_OZONE_WL,1/a env = WALLPAPER_DIR,$WALLPAPER_DIR\nenv = SCRIPT_DIR,$HOME/.config/hypr/scripts" "$HYPR_CONF"
    
    # 3. Inject Nvidia specific configurations if detected
    if [ "$HAS_NVIDIA" = true ]; then
        sed -i '/^env = NIXOS_OZONE_WL,1/a env = LIBVA_DRIVER_NAME,nvidia\nenv = XDG_SESSION_TYPE,wayland\nenv = GBM_BACKEND,nvidia-drm\nenv = __GLX_VENDOR_LIBRARY_NAME,nvidia\nenv = WLR_NO_HARDWARE_CURSORS,1' "$HYPR_CONF"
    fi
else
    echo -e "${C_RED}Warning: hyprland.conf not found at $HYPR_CONF${RESET}"
fi

# 4. Patch WallpaperPicker.qml dynamically
if [ -f "$WP_QML" ]; then
    sed -i 's|Quickshell.env("HOME") + "/Images/Wallpapers"|Quickshell.env("WALLPAPER_DIR")|g' "$WP_QML"
fi

# 5. Rename all instances of swww to awww in quickshell/wallpaper files
if [ -d "$WP_DIR" ]; then
    find "$WP_DIR" -type f -exec sed -i 's/swww/awww/g' {} +
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

# 8. Remove Schedule Directory
SCHEDULE_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar/schedule"
if [ -d "$SCHEDULE_DIR" ]; then
    rm -rf "$SCHEDULE_DIR"
fi

# 9. Setup SDDM Theme and Config
if [ -d "$REPO_DIR/.config/sddm/themes/matugen-minimal" ]; then
    sudo mkdir -p /usr/share/sddm/themes/matugen-minimal
    sudo cp -r "$REPO_DIR/.config/sddm/themes/matugen-minimal/"* /usr/share/sddm/themes/matugen-minimal/
    sudo touch /usr/share/sddm/themes/matugen-minimal/Colors.qml
    sudo chown $USER:$USER /usr/share/sddm/themes/matugen-minimal/Colors.qml
    
    echo -e "[Theme]\nCurrent=matugen-minimal" | sudo tee /etc/sddm.conf > /dev/null
    printf "  -> SDDM Theme configured %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

printf "  -> System adaptations applied %-11s ${C_GREEN}[ OK ]${RESET}\n" ""

# --- 9. Finalize Version Marker ---
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
echo -e "Please log out and log back in, or restart Hyprland to apply all changes."
echo -e "-> Note: You must restart Quickshell (or log out and back in) for Qt to see the new font weights.\n"
