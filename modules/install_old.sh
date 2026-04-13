


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
    
    # Fix for SDDM black screen on logout (forces dangling wayland session processes to close)
    echo "  -> Applying systemd logind workaround for Wayland logout black screens..."
    sudo sed -i 's/^#*KillUserProcesses=.*/KillUserProcesses=yes/' /etc/systemd/logind.conf
    sudo systemctl restart systemd-logind 2>/dev/null || true
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
# Attempt to start it locally if DBUS is available (fails silently in TTY, which is fine since --global catches the next login)
systemctl --user start pipewire wireplumber pipewire-pulse 2>/dev/null || true

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

    # 1. Inject SwayOSD Autostart (Looking for the new 'awww-daemon' entry)
    sed -i '/^exec-once = awww-daemon/a exec-once = swayosd-server --top-margin 0.9 --style ~/.config/swayosd/style.css' "$HYPR_CONF"

    # 2. Inject Environment Variables for Quickshell
    sed -i "/^env = NIXOS_OZONE_WL,1/a env = WALLPAPER_DIR,$WALLPAPER_DIR\nenv = SCRIPT_DIR,$HOME/.config/hypr/scripts" "$HYPR_CONF"
    
    # 3. Inject Advanced Nvidia specific configurations (ONLY IF PROPRIETARY IS CHOSEN)
    if [ "$HAS_NVIDIA_PROPRIETARY" = true ]; then
        sed -i '/^env = NIXOS_OZONE_WL,1/a env = LIBVA_DRIVER_NAME,nvidia\nenv = XDG_SESSION_TYPE,wayland\nenv = GBM_BACKEND,nvidia-drm\nenv = __GLX_VENDOR_LIBRARY_NAME,nvidia\nenv = WLR_NO_HARDWARE_CURSORS,1\ncursor {\n    no_hardware_cursors = true\n}' "$HYPR_CONF"
    fi
else
    echo -e "${C_RED}Warning: hyprland.conf not found at $HYPR_CONF${RESET}"
fi

# 4. Patch WallpaperPicker.qml dynamically
if [ -f "$WP_QML" ]; then
    # Injecting the properly evaluated bash variable straight into the QML instead of the hardcoded Quickshell.env string
    sed -i "s|Quickshell.env(\"HOME\") + \"/Pictures/Wallpapers\"|\"$WALLPAPER_DIR\"|g" "$WP_QML"
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
        
        # FIX 2: Use a drop-in file for the theme instead of overwriting all of /etc/sddm.conf
        # This preserves the distro's default Wayland/X11 configuration.
        sudo mkdir -p /etc/sddm.conf.d
        echo -e "[Theme]\nCurrent=matugen-minimal" | sudo tee /etc/sddm.conf.d/10-matugen-theme.conf > /dev/null
        
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