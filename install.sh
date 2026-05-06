#!/usr/bin/env bash

# ==============================================================================
# Entry Point
# ==============================================================================
DOTS_VERSION="1.7.3"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$INSTALL_DIR/lib/constants.sh"
source "$INSTALL_DIR/lib/detect.sh"
source "$INSTALL_DIR/lib/telemetry.sh"
source "$INSTALL_DIR/lib/tui.sh"
source "$INSTALL_DIR/lib/packages.sh"
source "$INSTALL_DIR/lib/dotfiles.sh"
source "$INSTALL_DIR/lib/settings.sh"
source "$INSTALL_DIR/lib/services.sh"
source "$INSTALL_DIR/lib/theming.sh"

# ==============================================================================
# State Initialization
# ==============================================================================
init_state() {
    setterm -blank 0 -powerdown 0 2>/dev/null || true
    printf '\033[9;0]' 2>/dev/null || true

    WEATHER_API_KEY=""
    WEATHER_CITY_ID=""
    WEATHER_UNIT=""
    FAILED_PKGS=()
    PKGS=("${ARCH_PKGS[@]}")

    LOCAL_DEV=false
    TARGET_BRANCH="master"

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --dev)   TARGET_BRANCH="dev"; shift ;;
            --local) LOCAL_DEV=true; shift ;;
            *)       shift ;;
        esac
    done

    [[ "$TARGET_BRANCH" == "dev" ]] && \
        echo -e "${C_YELLOW}[!] RUNNING IN DEVELOPMENT MODE (Branch: dev)${RESET}"

    OPT_SDDM=false
    OPT_NVIM=false
    OPT_ZSH=false
    OPT_WALLPAPERS=false
    OPT_OVERRIDE_KEYBINDS=false
    OPT_OVERRIDE_STARTUPS=false

    INSTALL_NVIM=false
    INSTALL_ZSH=false
    INSTALL_SDDM=false
    REPLACE_DM=false
    SETUP_SDDM_THEME=false
    SDDM_WAYLAND=false

    DRIVER_CHOICE="None (Skipped)"
    DRIVER_PKGS=()
    HAS_NVIDIA_PROPRIETARY=false
    LAST_COMMIT=""
    KEEP_OLD_ENV=true
    ENABLE_TELEMETRY=true

    VISITED_PKGS=false
    VISITED_OVERVIEW=false
    VISITED_WEATHER=false
    VISITED_DRIVERS=false
    VISITED_KEYBOARD=false

    KB_LAYOUTS="us"
    KB_LAYOUTS_DISPLAY="English (US)"
    KB_OPTIONS="grp:alt_shift_toggle"

    SETTINGS_FILE="$TARGET_CONFIG_DIR/hypr/settings.json"

    mkdir -p "$(dirname "$VERSION_FILE")"
    if [ -f "$VERSION_FILE" ] && [ -s "$VERSION_FILE" ]; then
        source "$VERSION_FILE"
        if [ -n "$LOCAL_VERSION" ] && [ "$LOCAL_VERSION" != "Not Installed" ]; then
            [ -n "$KB_LAYOUTS" ]      && VISITED_KEYBOARD=true
            [ -n "$WEATHER_API_KEY" ] && VISITED_WEATHER=true
            [[ "$DRIVER_CHOICE" != "None (Skipped)" && -n "$DRIVER_CHOICE" ]] && VISITED_DRIVERS=true
        fi
    else
        LOCAL_VERSION="Not Installed"
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    init_state "$@"

    detect_os
    detect_hardware
    detect_user_dirs
    bootstrap_dependencies

    init_telemetry_id
    sync_state_from_settings
    send_telemetry "init"

    run_main_menu

    # Installation
    clear
    draw_header
    echo -e "${BOLD}${C_BLUE}::${RESET} ${BOLD}Starting Installation Process...${RESET}\n"

    send_telemetry "full"
    echo -e "${C_CYAN}[ INFO ]${RESET} Requesting sudo privileges for installation..."
    sudo -v

    resolve_conflicts
    install_packages
    setup_nvidia
    setup_display_manager_service
    setup_repo
    fetch_wallpapers
    copy_dotfiles
    bake_hardware_env
    persist_weather_config
    restore_qs_colors
    deploy_cava_wrapper
    setup_audio
    setup_easyeffects
    setup_zsh
    install_fonts
    apply_system_adaptations
    sync_settings
    setup_gtk_qt
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Enabling Core System Services..."
    setup_network
    setup_sddm_theme
    compile_templates
    save_version_state

    print_completion
    send_telemetry "done"
}

main "$@"