#!/usr/bin/env bash

# ==============================================================================
# Script Versioning & Initialization
# ==============================================================================
DOTS_VERSION="1.0.13"
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

# ==============================================================================
# Interactive TUI Functions
# ==============================================================================

draw_header() {
    printf "\033[H"
    printf "${BOLD}${C_CYAN}"
    cat << "EOF"
 ██╗██╗     ██╗   ██╗ █████╗ ███╗   ███╗██╗██████╗  ██████╗ 
 ██║██║     ╚██╗ ██╔╝██╔══██╗████╗ ████║██║██╔══██╗██╔═══██╗
 ██║██║      ╚████╔╝ ███████║██╔████╔██║██║██████╔╝██║   ██║
 ██║██║       ╚██╔╝  ██╔══██║██║╚██╔╝██║██║██╔══██╗██║   ██║
 ██║███████╗   ██║   ██║  ██║██║ ╚═╝ ██║██║██║  ██║╚██████╔╝
 ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝ 
EOF
    printf "${RESET}\n"

    # OSC 8 Escape Sequences for Clickable Hyperlinks
    local OSC8_GH="\e]8;;https://github.com/ilyamiro/imperative-dots.git\a"
    local OSC8_TW="\e]8;;https://twitter.com/ilyamirox\a"
    local OSC8_RD="\e]8;;https://reddit.com/r/ilyamiro1\a"
    local OSC8_END="\e]8;;\a"

    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD}${C_GREEN} GitHub:${RESET}  ${OSC8_GH}https://github.com/ilyamiro/imperative-dots.git${OSC8_END}\n"
    printf "\033[K${BOLD}${C_CYAN} Twitter:${RESET} ${OSC8_TW}@ilyamirox${OSC8_END}  |  ${BOLD}${C_RED}Reddit:${RESET} ${OSC8_RD}r/ilyamiro1${OSC8_END}\n"
    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD} User:           ${RESET} %s\n" "$USER_NAME"
    printf "\033[K${BOLD} OS:             ${RESET} %s\n" "$OS_NAME"
    printf "\033[K${BOLD} CPU:            ${RESET} %s\n" "$CPU_INFO"
    printf "\033[K${BOLD} GPU:            ${RESET} %s\n" "$GPU_INFO"
    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD} Server Version: ${RESET} %s\n" "$DOTS_VERSION"
    printf "\033[K${BOLD} Local Version:  ${RESET} %s\n" "$LOCAL_VERSION"
    printf "\033[K${C_BLUE} =================================================================${RESET}\n\n"
    printf "\033[J"
}

manage_packages() {
    while true; do
        draw_header
        local action
        action=$(echo -e "1. View Packages to be Installed\n2. Add Custom Packages\n3. Back to Main Menu" | fzf \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=15 \
            --prompt=" Package Manager > " \
            --pointer=">" \
            --header=" Use ARROW KEYS and ENTER ")

        case "$action" in
            *"1"*)
                echo "${PKGS[@]}" | tr ' ' '\n' | fzf \
                    --layout=reverse \
                    --border=rounded \
                    --margin=1,2 \
                    --height=25 \
                    --prompt=" Current Packages > " \
                    --pointer=">" \
                    --header=" Press ESC or ENTER to return to menu "
                ;;
            *"2"*)
                echo -e "${C_CYAN}Enter package names to add (separated by space) ${BOLD}[Leave empty and press ENTER to cancel]${RESET}${C_CYAN}:${RESET}"
                read -r new_pkgs
                if [ -n "$new_pkgs" ]; then
                    PKGS+=($new_pkgs)
                    echo -e "${C_GREEN}Packages added!${RESET}"
                    sleep 1
                fi
                ;;
            *"3"*) VISITED_PKGS=true; break ;;
            *) VISITED_PKGS=true; break ;;
        esac
    done
}

manage_drivers() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Hardware Driver Configuration ===${RESET}"
        echo -e "${BOLD}${C_RED}=================== EXPERIMENTAL WARNING ===================${RESET}"
        echo -e "${C_RED}This automated driver installer is highly experimental and${RESET}"
        echo -e "${C_RED}can be unreliable across different kernel/distro variations.${RESET}"
        echo -e "${C_RED}It is strongly recommended to SKIP this and install your${RESET}"
        echo -e "${C_RED}graphics drivers manually according to your distro's wiki.${RESET}"
        echo -e "${BOLD}${C_RED}============================================================${RESET}\n"
        echo -e "Detected GPU Vendor: ${BOLD}${C_YELLOW}$GPU_VENDOR${RESET}\n"

        # Determine if a kernel driver is currently in use to prevent conflicts
        local current_driver="None"
        if command -v lsmod &> /dev/null; then
            if lsmod | grep -wq nvidia; then
                current_driver="nvidia"
            elif lsmod | grep -wq nouveau; then
                current_driver="nouveau"
            elif lsmod | grep -Ewq "amdgpu|radeon"; then
                current_driver="amd"
            elif lsmod | grep -Ewq "i915|xe"; then
                current_driver="intel"
            fi
        fi

        local options=""
        case "$GPU_VENDOR" in
            "NVIDIA")
                if [[ "$current_driver" == "nouveau" ]]; then
                    echo -e "${C_YELLOW}[!] Notice: Open-source 'nouveau' drivers are currently loaded.${RESET}"
                    echo -e "${C_RED}[!] Proprietary installation is locked out to prevent initramfs conflicts/black screens.${RESET}\n"
                    options="1. Update/Keep Nouveau (Open Source)\n2. Skip Driver Installation"
                elif [[ "$current_driver" == "nvidia" ]]; then
                    echo -e "${C_YELLOW}[!] Notice: Proprietary 'nvidia' drivers are currently loaded.${RESET}"
                    echo -e "${C_RED}[!] Open-source installation is locked out to prevent conflicts.${RESET}\n"
                    options="1. Update/Keep Proprietary NVIDIA Drivers\n2. Skip Driver Installation"
                else
                    options="1. Install Proprietary NVIDIA Drivers (Recommended for Gaming/Wayland)\n2. Install Nouveau (Open Source, Better VM compat)\n3. Skip Driver Installation"
                fi
                ;;
            "AMD")
                options="1. Install AMD Mesa & Vulkan Drivers (RADV)\n2. Skip Driver Installation"
                ;;
            "INTEL")
                options="1. Install Intel Mesa & Vulkan Drivers (ANV)\n2. Skip Driver Installation"
                ;;
            *)
                options="1. Install Generic Mesa Drivers (For VMs / Software Rendering)\n2. Skip Driver Installation"
                ;;
        esac

        local choice
        choice=$(echo -e "$options\nBack to Main Menu" | fzf \
            --ansi \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=15 \
            --prompt=" Drivers > " \
            --pointer=">" \
            --header=" Select the graphics drivers to install ")

        if [[ "$choice" == *"Back"* ]]; then break; fi

        # Require confirmation to INSTALL drivers, rather than skipping.
        if [[ "$choice" != *"Skip"* ]]; then
            echo -e "\n${BOLD}${C_RED}=================== ACTION REQUIRED ===================${RESET}"
            echo -e "${C_YELLOW}You have selected to AUTOMATICALLY install/configure drivers.${RESET}"
            echo -e "${C_YELLOW}If your system already has working drivers, this might break your boot sequence.${RESET}"
            echo -n -e "Are you ${BOLD}${C_RED}100% sure${RESET} you want to proceed with this driver installation? (y/n): "
            read -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "\n${C_RED}Driver setup aborted. Returning to menu...${RESET}"
                sleep 1.2
                continue
            fi
        fi

        # Strictly reset states before applying the verified configuration
        DRIVER_PKGS=()
        HAS_NVIDIA_PROPRIETARY=false

        if [[ "$choice" == *"Proprietary NVIDIA"* ]]; then
            DRIVER_CHOICE="NVIDIA Proprietary"
            HAS_NVIDIA_PROPRIETARY=true
            DRIVER_PKGS+=("nvidia-dkms" "nvidia-utils" "lib32-nvidia-utils" "linux-headers" "egl-wayland")
        
        elif [[ "$choice" == *"Nouveau"* ]]; then
            DRIVER_CHOICE="NVIDIA Nouveau"
            DRIVER_PKGS+=("mesa" "vulkan-nouveau" "lib32-mesa")

        elif [[ "$choice" == *"AMD"* ]]; then
            DRIVER_CHOICE="AMD Drivers"
            DRIVER_PKGS+=("mesa" "vulkan-radeon" "lib32-vulkan-radeon" "lib32-mesa" "xf86-video-amdgpu")

        elif [[ "$choice" == *"Intel"* ]]; then
            DRIVER_CHOICE="Intel Drivers"
            DRIVER_PKGS+=("mesa" "vulkan-intel" "lib32-vulkan-intel" "lib32-mesa" "intel-media-driver")

        elif [[ "$choice" == *"Generic"* ]]; then
            DRIVER_CHOICE="Generic / VM"
            DRIVER_PKGS+=("mesa" "lib32-mesa")

        elif [[ "$choice" == *"Skip"* ]]; then
            DRIVER_CHOICE="Skipped"
            DRIVER_PKGS=()
        fi

        echo -e "\n${C_GREEN}Driver configuration saved!${RESET}"
        sleep 1.2
        VISITED_DRIVERS=true
        break
    done
}

manage_keyboard() {
    local available_layouts=(
        "us - English (US)" "gb - English (UK)" "au - English (Australia)"
        "ca - English/French (Canada)" "ie - English (Ireland)"
        "nz - English (New Zealand)" "za - English (South Africa)"
        "fr - French" "be - Belgian" "ch - Swiss"
        "de - German" "at - Austrian" "nl - Dutch" "lu - Luxembourgish"
        "es - Spanish" "pt - Portuguese" "br - Portuguese (Brazil)"
        "it - Italian" "gr - Greek" "mt - Maltese"
        "se - Swedish" "no - Norwegian" "dk - Danish"
        "fi - Finnish" "is - Icelandic"
        "pl - Polish" "cz - Czech" "sk - Slovak" "hu - Hungarian"
        "ro - Romanian" "bg - Bulgarian" "ru - Russian" "ua - Ukrainian"
        "by - Belarusian" "rs - Serbian" "hr - Croatian" "si - Slovenian"
        "mk - Macedonian" "ba - Bosnian" "me - Montenegrin"
        "lt - Lithuanian" "lv - Latvian" "ee - Estonian"
        "am - Armenian" "ge - Georgian" "kz - Kazakh" "kg - Kyrgyz"
        "tj - Tajik" "tm - Turkmen" "uz - Uzbek" "mn - Mongolian"
        "il - Hebrew" "ara - Arabic" "ir - Persian (Farsi)"
        "iq - Iraqi" "sy - Syrian"
        "in - Indian" "pk - Pakistani" "bd - Bangla"
        "th - Thai" "vn - Vietnamese" "la - Lao"
        "mm - Burmese" "kh - Khmer"
        "cn - Chinese" "jp - Japanese" "kr - Korean" "tw - Taiwanese"
        "ng - Nigerian" "ma - Moroccan" "dz - Algerian" "et - Ethiopian"
        "latam - Spanish (Latin America)"
        "al - Albanian" "fo - Faroese"
    )
    local selected_codes=()
    local selected_names=()

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"
        
        if [ ${#selected_codes[@]} -gt 0 ]; then
            echo -e "Currently added: ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"
        fi

        local choice
        choice=$(printf "%s\n" "Done (Finish Selection)" "${available_layouts[@]}" | fzf \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=20 \
            --prompt=" Add Layout > " \
            --pointer=">" \
            --header=" Select a language to add, or select Done ")

        if [[ -z "$choice" || "$choice" == *"Done"* ]]; then
            # Enforce at least one layout
            if [ ${#selected_codes[@]} -eq 0 ]; then
                selected_codes=("us")
                selected_names=("English (US)")
            fi
            break
        fi

        local code=$(echo "$choice" | awk '{print $1}')
        local name=$(echo "$choice" | cut -d'-' -f2- | sed 's/^ //')

        selected_codes+=("$code")
        selected_names+=("$name")
    done

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"
        echo -e "Currently added: ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"
        echo -e "${C_CYAN}Choose a key combination to switch between layouts:${RESET}"
        
        local options="1. Alt + Shift (grp:alt_shift_toggle)\n"
        options+="2. Win + Space (grp:win_space_toggle)\n"
        options+="3. Caps Lock (grp:caps_toggle)\n"
        options+="4. Ctrl + Shift (grp:ctrl_shift_toggle)\n"
        options+="5. Ctrl + Alt (grp:ctrl_alt_toggle)\n"
        options+="6. Right Alt (grp:toggle)\n"
        options+="7. No Toggle (Single Layout)"

        local choice
        choice=$(echo -e "$options" | fzf \
            --ansi \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=15 \
            --prompt=" Toggle Keybind > " \
            --pointer=">" \
            --header=" Select layout switching method ")

        local kb_opt=""
        case "$choice" in
            *"1"*) kb_opt="grp:alt_shift_toggle" ;;
            *"2"*) kb_opt="grp:win_space_toggle" ;;
            *"3"*) kb_opt="grp:caps_toggle" ;;
            *"4"*) kb_opt="grp:ctrl_shift_toggle" ;;
            *"5"*) kb_opt="grp:ctrl_alt_toggle" ;;
            *"6"*) kb_opt="grp:toggle" ;;
            *"7"*) kb_opt="" ;;
            *) kb_opt="grp:alt_shift_toggle" ;;
        esac

        KB_LAYOUTS=$(IFS=','; echo "${selected_codes[*]}")
        KB_LAYOUTS_DISPLAY=$(IFS=', '; echo "${selected_names[*]}")
        KB_OPTIONS="$kb_opt"

        echo -e "\n${C_GREEN}Keyboard configured: Layouts = $KB_LAYOUTS_DISPLAY | Switch = ${KB_OPTIONS:-None}${RESET}"
        sleep 1.5
        VISITED_KEYBOARD=true
        break
    done
}

show_overview() {
    clear
    draw_header
    echo -e "${BOLD}${C_MAGENTA}=== System Overview & Keybinds ===${RESET}\n"
    echo -e "This configuration is an adaptation of the ${BOLD}${C_CYAN}ilyamiro/nixos-configuration${RESET} setup."
    echo -e "Here are the core keybindings to navigate your new system once installed:\n"

    # Formatting helper for perfect alignment
    print_kb() {
        printf "  ${C_CYAN}[${RESET} ${BOLD}%-17s${RESET} ${C_CYAN}]${RESET}  ${C_YELLOW}➜${RESET}  %s\n" "$1" "$2"
    }

    echo -e "${BOLD}${C_BLUE}--- Applications ---${RESET}"
    print_kb "SUPER + RETURN" "Open Terminal (kitty)"
    print_kb "SUPER + D" "Open App Launcher (rofi)"
    print_kb "SUPER + F" "Open Browser (Firefox)"
    print_kb "SUPER + E" "Open File Manager (nautilus)"
    print_kb "SUPER + C" "Clipboard History (rofi)"
    echo ""

    echo -e "${BOLD}${C_BLUE}--- Quickshell Widgets ---${RESET}"
    print_kb "SUPER + M" "Toggle Monitors"
    print_kb "SUPER + Q" "Toggle Music"
    print_kb "SUPER + B" "Toggle Battery"
    print_kb "SUPER + W" "Toggle Wallpaper"
    print_kb "SUPER + S" "Toggle Calendar"
    print_kb "SUPER + N" "Toggle Network"
    print_kb "SUPER + SHIFT + T" "Toggle FocusTime"
    print_kb "SUPER + SHIFT + S" "Toggle Stewart (RESERVED FOR FUTURE VOICE ASSISTANT)"
    print_kb "SUPER + V" "Toggle Volume Control"
    echo ""

    echo -e "${BOLD}${C_BLUE}--- Window Management ---${RESET}"
    print_kb "ALT + F4" "Close Active Window / Widget"
    print_kb "SUPER + SHIFT + F" "Toggle Floating"
    print_kb "SUPER + Arrows" "Move Focus"
    print_kb "SUPER + CTRL + Arr" "Move Window"
    echo ""

    echo -e "${BOLD}${C_BLUE}--- System Controls ---${RESET}"
    print_kb "SUPER + L" "Lock Screen"
    print_kb "Print Screen" "Screenshot"
    print_kb "SHIFT + Print" "Screenshot (Edit)"
    print_kb "ALT + SHIFT" "Switch Keyboard Layout"
    echo ""

    echo -e "${BOLD}${C_GREEN}Press ENTER to return to the Main Menu...${RESET}"
    read -r
    VISITED_OVERVIEW=true
}

set_weather_api() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== OpenWeatherMap Interactive Setup ===${RESET}"
        echo -e "${BOLD}${C_YELLOW}Without this, weather widgets WILL NOT WORK.${RESET}\n"
        
        echo -e "${C_MAGENTA}How to get a free API key:${RESET}"
        echo -e "  1. Visit ${C_BLUE}https://openweathermap.org/${RESET}"
        echo -e "  2. Create a free account and log in."
        echo -e "  3. Click your profile name -> 'My API keys'."
        echo -e "  4. Generate a new key and paste it below."
        echo -e "  ${BOLD}${C_YELLOW}Note: New API keys may take a couple of hours to activate. This installer will NOT block you from using a fresh key.${RESET}\n"
        
        read -p "Enter your OpenWeather API Key (or press Enter to skip): " input_key
        
        if [[ -z "$input_key" ]]; then
            echo -e "\n${C_RED}WARNING: You did not enter an API key.${RESET}"
            echo -n -e "Are you ${BOLD}${C_RED}100% sure${RESET} you want to proceed without it? (y/n): "
            read -r confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                WEATHER_API_KEY="Skipped"
                WEATHER_CITY_ID=""
                WEATHER_UNIT=""
                VISITED_WEATHER=true
                break
            fi
            continue
        fi

        # Soft validation to ensure it looks like a valid key without querying the API
        input_key=$(echo "$input_key" | tr -d ' ')
        if [[ ${#input_key} -ne 32 ]]; then
            echo -e "\n${C_YELLOW}Warning: OpenWeather API keys are typically exactly 32 characters long.${RESET}"
            echo -e "${C_YELLOW}Your key is ${#input_key} characters long.${RESET}"
            echo -n "Are you sure this key is correct? (y/n): "
            read -r confirm_key
            if [[ ! "$confirm_key" =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        
        WEATHER_API_KEY="$input_key"
        
        echo -e "\n${C_CYAN}Let's set your location using your City ID.${RESET}"
        echo -e "1. Go to ${C_BLUE}https://openweathermap.org/${RESET} and search for your city."
        echo -e "2. Look at the URL in your browser. It will look something like this:"
        echo -e "   ${DIM}https://openweathermap.org/city/${RESET}${BOLD}2643743${RESET}"
        echo -e "3. Copy that number at the end (the City ID) and paste it below.\n"
        
        read -p "Enter City ID: " input_id

        if [[ -z "$input_id" || ! "$input_id" =~ ^[0-9]+$ ]]; then
            echo -e "${C_RED}Invalid City ID. It must be a number.${RESET}"
            sleep 1.5
            continue
        fi

        WEATHER_CITY_ID="$input_id"
        
        # Ask for standard units
        echo ""
        unit_choice=$(echo -e "metric (Celsius)\nimperial (Fahrenheit)\nstandard (Kelvin)" | fzf \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=12 \
            --prompt=" Select Temperature Unit > " \
            --pointer=">" \
            --header=" Choose your preferred unit format ")
        
        WEATHER_UNIT=$(echo "$unit_choice" | awk '{print $1}')
        [[ -z "$WEATHER_UNIT" ]] && WEATHER_UNIT="metric"
        
        echo -e "\n${C_GREEN}Weather configuration complete! Widget will update once your key is activated by OpenWeather.${RESET}"
        sleep 2.5
        VISITED_WEATHER=true
        break
    done
}

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

# ==============================================================================
# Main Menu Loop
# ==============================================================================
# Hard clear the screen once so \033[H works perfectly from the top
clear

while true; do
    draw_header
    
    # Progress checkmarks for submenus
    S_PKG=$( [ "$VISITED_PKGS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_OVW=$( [ "$VISITED_OVERVIEW" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_WTH=$( [ "$VISITED_WEATHER" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_DRV=$( [ "$VISITED_DRIVERS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_KBD=$( [ "$VISITED_KEYBOARD" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_RED}[ ]${RESET}" )

    if [[ -z "$WEATHER_API_KEY" ]]; then API_DISPLAY="Not Set"
    elif [[ "$WEATHER_API_KEY" == "Skipped" ]]; then API_DISPLAY="Skipped"
    else API_DISPLAY="Set ($WEATHER_UNIT, ID: $WEATHER_CITY_ID)"; fi

    # Build the color-coded menu string
    MENU_ITEMS="1. $S_PKG ${C_GREEN}Manage Packages${RESET} [${#PKGS[@]} queued, Optional]\n"
    MENU_ITEMS+="2. $S_OVW ${C_CYAN}Overview & Keybinds${RESET} [Optional]\n"
    MENU_ITEMS+="3. $S_WTH ${C_YELLOW}Set Weather API Key${RESET} [${API_DISPLAY}, Optional]\n"
    MENU_ITEMS+="4. $S_DRV ${C_RED}[ DRIVERS ] Setup${RESET} [${DRIVER_CHOICE}, Optional]\n"
    MENU_ITEMS+="5. $S_KBD ${C_BLUE}Keyboard Layout Setup${RESET} [${KB_LAYOUTS_DISPLAY:-$KB_LAYOUTS}]\n"
    MENU_ITEMS+="6. ${BOLD}${C_MAGENTA}START INSTALLATION${RESET}\n"
    MENU_ITEMS+="7. ${DIM}Exit${RESET}"

    # We use --ansi flag in fzf so the color codes render properly inside the menu list
    MENU_OPTION=$(echo -e "$MENU_ITEMS" | fzf \
        --ansi \
        --layout=reverse \
        --border=rounded \
        --margin=1,2 \
        --height=16 \
        --prompt=" Main Menu > " \
        --pointer=">" \
        --header=" Navigate with ARROWS. Select with ENTER. ")

    case "$MENU_OPTION" in
        *"1"*) manage_packages ;;
        *"2"*) show_overview ;;
        *"3"*) set_weather_api ;;
        *"4"*) manage_drivers ;;
        *"5"*) manage_keyboard ;;
        *"6"*) 
            if [ "$VISITED_KEYBOARD" = false ]; then
                echo -e "\n${C_RED}[!] You must configure your Keyboard Layouts in the submenu before starting.${RESET}"
                sleep 2.5
                continue
            fi
            prompt_optional_features
            break 
            ;;
        *"7"*) clear; exit 0 ;;
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

# --- 0. Resolve Package Conflicts ---
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

# Combine Base Packages with chosen Driver Packages
ALL_PKGS=("${PKGS[@]}" "${DRIVER_PKGS[@]}")
MISSING_PKGS=()

echo -e "\n${C_CYAN}[ INFO ]${RESET} Checking for already installed packages..."
for pkg in "${ALL_PKGS[@]}"; do
    # Skip empty entries if any
    [[ -z "$pkg" ]] && continue 

    # Check if package is installed locally
    if pacman -Q "$pkg" &>/dev/null; then
        true # Already installed, skip
    else
        MISSING_PKGS+=("$pkg")
    fi
done

# --- 1. Install Dependencies & Drivers ---
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

# --- 2. Display Manager Cleanup & SDDM Setup ---
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
fi

# --- 3. Repository Cloning & Wallpapers ---
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
mkdir -p "$WALLPAPER_DIR"

if [ "$(ls -A "$WALLPAPER_DIR" 2>/dev/null | grep -E '\.(jpg|png|jpeg|gif|webp)$')" ]; then
    echo -e "  -> ${C_GREEN}Wallpapers already present in $WALLPAPER_DIR. Skipping download.${RESET}"
else
    WALLPAPER_REPO="https://github.com/ilyamiro/shell-wallpapers.git"
    WALLPAPER_CLONE_DIR="/tmp/shell-wallpapers"

    if [ -d "$WALLPAPER_CLONE_DIR" ]; then
        rm -rf "$WALLPAPER_CLONE_DIR"
    fi

    # Clone with a dynamic progress bar
    git clone --progress "$WALLPAPER_REPO" "$WALLPAPER_CLONE_DIR" 2>&1 | tr '\r' '\n' | while read -r line; do
        if [[ "$line" =~ Receiving\ objects:\ *([0-9]+)% ]]; then
            pc="${BASH_REMATCH[1]}"
            fill=$(printf "%*s" $((pc / 2)) "" | tr ' ' '#')
            empty=$(printf "%*s" $((50 - (pc / 2))) "" | tr ' ' '-')
            printf "\r\033[K  -> Downloading: [%s%s] %3d%%" "$fill" "$empty" "$pc"
        fi
    done
    echo "" # Ensure a clean new line after the progress bar finishes

    if [ -d "$WALLPAPER_CLONE_DIR/images" ]; then
        cp -r "$WALLPAPER_CLONE_DIR/images/"* "$WALLPAPER_DIR/" 2>/dev/null || true
    else
        cp -r "$WALLPAPER_CLONE_DIR/"* "$WALLPAPER_DIR/" 2>/dev/null || true
    fi
    rm -rf "$WALLPAPER_CLONE_DIR"
    printf "  -> Wallpapers installed to %-12s ${C_GREEN}[ OK ]${RESET}\n" "$WALLPAPER_DIR"
fi

# --- 4. Copying Dotfiles & Backups ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Applying Configurations & Backing Up Old Ones..."
TARGET_CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"

CONFIG_FOLDERS=("cava" "hypr" "kitty" "rofi" "swaync" "matugen" "zsh" "swayosd")
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

# Enable Pipewire natively for the user environment
# Using --global prevents silent failures when testers run this script from a TTY (without an active DBUS session)
sudo systemctl --global enable pipewire wireplumber pipewire-pulse 2>/dev/null || true
sudo systemctl enable --now swayosd-libinput-backend.service
# Attempt to start it locally if DBUS is available (fails silently in TTY, which is fine since --global catches the next login)
systemctl --user start pipewire wireplumber pipewire-pulse 2>/dev/null || true

# --- Create and enable SwayOSD user service ---
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
cat <<EOF > "$SYSTEMD_USER_DIR/swayosd.service"
[Unit]
Description=SwayOSD Service
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/env swayosd-server --top-margin 0.9 --style $HOME/.config/swayosd/style.css
Restart=on-failure

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable swayosd.service 2>/dev/null || true
systemctl --user start swayosd.service 2>/dev/null || true
printf "  -> SwayOSD user service configured %-17s ${C_GREEN}[ OK ]${RESET}\n" ""

if [ "$INSTALL_ZSH" = true ] && command -v zsh &> /dev/null; then
    if [ -f "$HOME/.zshrc" ]; then
        echo -e "  -> Extracting existing aliases from ~/.zshrc..."
        mkdir -p "$TARGET_CONFIG_DIR/zsh"
        grep "^alias " "$HOME/.zshrc" > "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" || true
        if [ -s "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ]; then
            printf "  -> Custom aliases backed up %-16s ${C_GREEN}[ OK ]${RESET}\n" ""
        else
            rm -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh"
        fi
    fi

    cp "$TARGET_CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"
    chsh -s $(which zsh) "$USER"

    if [ -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ]; then
        echo -e "\n# Load User Aliases" >> "$HOME/.zshrc"
        echo "source $TARGET_CONFIG_DIR/zsh/user_aliases.zsh" >> "$HOME/.zshrc"
    fi

    printf "  -> Zsh set as default shell %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 5. Fonts ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing Fonts..."
TARGET_FONTS_DIR="$HOME/.local/share/fonts"
REPO_FONTS_DIR="$REPO_DIR/.local/share/fonts"
mkdir -p "$TARGET_FONTS_DIR"

# Copy any remaining local fonts (like JetBrainsMono)
if [ -d "$REPO_FONTS_DIR" ]; then
    cp -r "$REPO_FONTS_DIR/"* "$TARGET_FONTS_DIR/" 2>/dev/null || true
fi

if [ -d "$TARGET_FONTS_DIR/IosevkaNerdFont" ] && [ "$(ls -A "$TARGET_FONTS_DIR/IosevkaNerdFont" 2>/dev/null | grep -i "\.ttf")" ]; then
    echo -e "  -> ${C_GREEN}Iosevka Nerd Fonts already installed in $TARGET_FONTS_DIR. Skipping download.${RESET}"
else
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
    sudo cp -r "$TARGET_FONTS_DIR/IosevkaNerdFont" /usr/share/fonts/

    printf "  -> Cleaning up temporary files... \n"
    rm -rf /tmp/iosevka-pack
    rm -f "$TARGET_FONTS_DIR/IosevkaNerdFont/"*Mono*.ttf
fi

# Fix permissions so fontconfig can actually read them
find "$TARGET_FONTS_DIR" -type f -exec chmod 644 {} \; 2>/dev/null
find "$TARGET_FONTS_DIR" -type d -exec chmod 755 {} \; 2>/dev/null

if command -v fc-cache &> /dev/null; then
    # Force cache update verbosely so we ensure the system registers it
    fc-cache -f "$TARGET_FONTS_DIR" > /dev/null 2>&1
    printf "  -> Font cache updated %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 6. Adaptability Phase ---
rm -f "$HOME/.cache/wallpaper_initialized" # if reinstalling
echo -e "\n${C_CYAN}[ INFO ]${RESET} Adapting configurations to your specific system..."

HYPR_CONF="$TARGET_CONFIG_DIR/hypr/hyprland.conf"
ZSH_RC="$HOME/.zshrc"
WP_QML="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper/WallpaperPicker.qml"
WP_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper"

# -> Desktop/Laptop Battery Adaptability <-
QS_BAT_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/battery"
echo -e "  -> Checking chassis for battery presence..."
if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then
    echo -e "  -> ${C_GREEN}Battery detected.${RESET} Keeping Laptop Battery widget."
else
    echo -e "  -> ${C_YELLOW}No battery detected (Desktop system).${RESET} Swapping to System Monitor widget."
    if [ -f "$QS_BAT_DIR/BatteryPopupAlt.qml" ]; then
        mv "$QS_BAT_DIR/BatteryPopup.qml" "$QS_BAT_DIR/BatteryPopup_laptop_backup.qml" 2>/dev/null || true
        mv "$QS_BAT_DIR/BatteryPopupAlt.qml" "$QS_BAT_DIR/BatteryPopup.qml" 2>/dev/null || true
    fi
fi

# -> Desktop/Ethernet Network Adaptability <-
QS_NET_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/network"
echo -e "  -> Checking for Wi-Fi interface..."
if ls /sys/class/net/w* 1> /dev/null 2>&1 || iw dev 2>/dev/null | grep -q Interface; then
    echo -e "  -> ${C_GREEN}Wi-Fi module detected.${RESET} Keeping standard Network widget."
else
    echo -e "  -> ${C_YELLOW}No Wi-Fi module detected (Desktop/Ethernet).${RESET} Swapping to Alternate Network widget."
    if [ -f "$QS_NET_DIR/NetworkPopupAlt.qml" ]; then
        mv "$QS_NET_DIR/NetworkPopup.qml" "$QS_NET_DIR/NetworkPopup_wifi_backup.qml" 2>/dev/null || true
        mv "$QS_NET_DIR/NetworkPopupAlt.qml" "$QS_NET_DIR/NetworkPopup.qml" 2>/dev/null || true
    fi
fi


if [ -f "$HYPR_CONF" ]; then
    
    # 0. Inject Keyboard Layout Configurations dynamically
    echo -e "  -> Applying Keyboard configuration..."
    sed -i "s/^ *kb_layout =.*/    kb_layout = $KB_LAYOUTS/" "$HYPR_CONF"
    if [ -n "$KB_OPTIONS" ]; then
        sed -i "s/^ *kb_options =.*/    kb_options = $KB_OPTIONS/" "$HYPR_CONF"
    else
        sed -i "s/^ *kb_options =.*/    kb_options = /" "$HYPR_CONF"
    fi

    # 1. Inject Environment Variables for Quickshell
    sed -i "/^env = NIXOS_OZONE_WL,1/a env = WALLPAPER_DIR,$WALLPAPER_DIR\nenv = SCRIPT_DIR,$HOME/.config/hypr/scripts" "$HYPR_CONF"
    
    # 2. Inject Advanced Nvidia specific configurations (ONLY IF PROPRIETARY IS CHOSEN)
    if [ "$HAS_NVIDIA_PROPRIETARY" = true ]; then
        sed -i '/^env = NIXOS_OZONE_WL,1/a env = LIBVA_DRIVER_NAME,nvidia\nenv = XDG_SESSION_TYPE,wayland\nenv = GBM_BACKEND,nvidia-drm\nenv = __GLX_VENDOR_LIBRARY_NAME,nvidia\nenv = WLR_NO_HARDWARE_CURSORS,1\ncursor {\n    no_hardware_cursors = true\n}' "$HYPR_CONF"
    fi
else
    echo -e "${C_RED}Warning: hyprland.conf not found at $HYPR_CONF${RESET}"
fi

# 4. Patch WallpaperPicker.qml dynamically
if [ -f "$WP_QML" ]; then
    # Injecting the properly evaluated bash variable straight into the QML instead of the hardcoded Quickshell.env string
    sed -i "s|Quickshell.env(\"HOME\") + \"/Images/Wallpapers\"|\"$WALLPAPER_DIR\"|g" "$WP_QML"
    
    # Inject --source-color-index 0 to Matugen commands for 4.0 compatibility
    sed -i 's/matugen image "[^"]*"/& --source-color-index 0/g' "$WP_QML"
fi

# 5. Rename all instances of swww to awww in quickshell/wallpaper files
if [ -d "$WP_DIR" ]; then
    find "$WP_DIR" -type f -exec sed -i 's/swww/awww/g' {} +
fi

# 6. Zsh Dynamism
if [ -f "$ZSH_RC" ]; then
    echo -e "\n# Dynamic System Paths" >> "$ZSH_RC"
    echo "export WALLPAPER_DIR=\"$WALLPAPER_DIR\"" >> "$ZSH_RC"
    echo "export SCRIPT_DIR=\"$HOME/.config/hypr/scripts\"" >> "$ZSH_RC"
    sed -i "s/OS_LOGO_PLACEHOLDER/${OS}_small/g" "$ZSH_RC"
fi

echo -e "\n${C_CYAN}[ INFO ]${RESET} Enabling Core System Services..."
sudo systemctl enable NetworkManager.service
printf "  -> NetworkManager enabled %-20s ${C_GREEN}[ OK ]${RESET}\n" ""

# 7. Setup SDDM Theme and Config
if [[ "$SETUP_SDDM_THEME" == true ]]; then
    if [ -d "$REPO_DIR/.config/sddm/themes/matugen-minimal" ]; then
        sudo mkdir -p /usr/share/sddm/themes/matugen-minimal
        sudo cp -r "$REPO_DIR/.config/sddm/themes/matugen-minimal/"* /usr/share/sddm/themes/matugen-minimal/
        
        # FIX 1: Provide a valid fallback QML file. 
        # If this file is empty, SDDM can crash before Matugen even gets to run.
        cat <<EOF | sudo tee /usr/share/sddm/themes/matugen-minimal/Colors.qml > /dev/null
pragma Singleton
import QtQuick
QtObject {
    readonly property color base: "#1e1e2e"
    readonly property color crust: "#11111b"
    readonly property color mantle: "#181825"
    readonly property color text: "#cdd6f4"
    readonly property color subtext0: "#a6adc8"
    readonly property color surface0: "#313244"
    readonly property color surface1: "#45475a"
    readonly property color surface2: "#585b70"
    readonly property color mauve: "#cba6f7"
    readonly property color red: "#f38ba8"
    readonly property color peach: "#fab387"
    readonly property color blue: "#89b4fa"
    readonly property color green: "#a6e3a1"
}
EOF
        sudo chown $USER:$USER /usr/share/sddm/themes/matugen-minimal/Colors.qml
        
        # FIX 2: Use a drop-in file for the theme and force SDDM to run as a Wayland greeter
        sudo mkdir -p /etc/sddm.conf.d
        cat <<EOF | sudo tee /etc/sddm.conf.d/10-wayland-matugen.conf > /dev/null
[Theme]
Current=matugen-minimal

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1
EOF
        
        printf "  -> SDDM Theme configured %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
fi

# --- 8. Finalize Version Marker & User State Persistence ---
cat <<EOF > "$VERSION_FILE"
LOCAL_VERSION="$DOTS_VERSION"
WEATHER_API_KEY="$WEATHER_API_KEY"
WEATHER_CITY_ID="$WEATHER_CITY_ID"
WEATHER_UNIT="$WEATHER_UNIT"
DRIVER_CHOICE="$DRIVER_CHOICE"
KB_LAYOUTS="$KB_LAYOUTS"
KB_LAYOUTS_DISPLAY="$KB_LAYOUTS_DISPLAY"
KB_OPTIONS="$KB_OPTIONS"
WALLPAPER_DIR="$WALLPAPER_DIR"
EOF
printf "  -> Configuration and version state saved %-7s ${C_GREEN}[ OK ]${RESET}\n" ""

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
