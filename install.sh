#!/usr/bin/env bash

# ==============================================================================
# Init Script
# ==============================================================================

#APP_NAME="TRANQUILAND"
#TEMPORAL=$(mktemp -d)

#echo "Iniciando $APP_NAME..."
#git clone https://github.com/Duban-sg/tranquiland-dots.git $TEMPORAL
#cd $TEMPORAL

# ==============================================================================
# clean temporals 
# ==============================================================================

#limpiar() {
#  echo "Eliminando archivos temporales..."
#  rm -rf "$TEMPORAL"
#}
#trap limpiar EXIT


# ==============================================================================
# import modules
# ==============================================================================
source ./modules/global_var.sh
source ./modules/draw_header.sh
source ./modules/manage_packages.sh
source ./modules/manage_drivers.sh
source ./modules/manage_keyboard.sh
source ./modules/prompt_optional_features.sh
source ./modules/set_weather_api.sh
source ./modules/show_overview.sh
source ./modules/install_modules/install_process.sh


menu_full_install(){
        # Progress checkmarks for submenus
    S_PKG=$( [ "$VISITED_PKGS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_OVW=$( [ "$VISITED_OVERVIEW" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_WTH=$( [ "$VISITED_WEATHER" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_DRV=$( [ "$VISITED_DRIVERS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_KBD=$( [ "$VISITED_KEYBOARD" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_RED}[ ]${RESET}" )
    S_TEL=$( [ "$ENABLE_TELEMETRY" = true ] && echo -e "${C_GREEN}[ON]${RESET}" || echo -e "${DIM}[OFF]${RESET}" )

    if [[ -z "$WEATHER_API_KEY" ]]; then
        if [ -f "$HOME/.config/hypr/scripts/quickshell/calendar/.env" ]; then
            API_DISPLAY="Set (from .env file)"
        else
            API_DISPLAY="Not Set"
        fi
    elif [[ "$WEATHER_API_KEY" == "Skipped" ]]; then API_DISPLAY="Skipped"
    else API_DISPLAY="Set ($WEATHER_UNIT, ID: $WEATHER_CITY_ID)"; fi

    # Determine label for the install button
    if [ "$LOCAL_VERSION" != "Not Installed" ] && [ -n "$LOCAL_VERSION" ]; then
        INSTALL_LABEL="UPDATE"
    else
        INSTALL_LABEL="START"
    fi

    # Build the color-coded menu string
    MENU_ITEMS="1. $S_PKG ${C_GREEN}Manage Packages${RESET} [${#PKGS[@]} queued, Optional]\n"
    MENU_ITEMS+="2. $S_OVW ${C_CYAN}Overview & Keybinds${RESET} [Optional]\n"
    MENU_ITEMS+="3. $S_WTH ${C_YELLOW}Set Weather API Key${RESET} [${API_DISPLAY}, Optional]\n"
    MENU_ITEMS+="4. $S_DRV ${C_RED}[ DRIVERS ] Setup${RESET} [${DRIVER_CHOICE}, Optional]\n"
    MENU_ITEMS+="5. $S_KBD ${C_BLUE}Keyboard Layout Setup${RESET} [${KB_LAYOUTS_DISPLAY:-$KB_LAYOUTS}]\n"
    MENU_ITEMS+="6. $S_TEL ${C_CYAN}Telemetry Settings${RESET}\n"
    MENU_ITEMS+="7. ${BOLD}${C_MAGENTA}${INSTALL_LABEL}${RESET}\n"
    MENU_ITEMS+="8. ${DIM}Exit${RESET}"

    # We use --ansi flag in fzf so the color codes render properly inside the menu list
    MENU_OPTION=$(echo -e "$MENU_ITEMS" | fzf \
        --ansi \
        --layout=reverse \
        --border=rounded \
        --margin=1,2 \
        --height=16 \
        --prompt=" Menu full install > " \
        --pointer=">" \
        --header=" Navigate with ARROWS. Select with ENTER. ")

    # FIXED: Added the dot and matched exactly against the list prefix
    case "$MENU_OPTION" in
        *"1."*) manage_packages ;;
        *"2."*) show_overview ;;
        *"3."*) set_weather_api ;;
        *"4."*) manage_drivers ;;
        *"5."*) manage_keyboard ;;
        *"6."*) manage_telemetry ;;
        *"7."*) 
            if [ "$VISITED_KEYBOARD" = false ]; then
                echo -e "\n${C_RED}[!] You must configure your Keyboard Layouts in the submenu before starting.${RESET}"
                sleep 2.5
                continue
            fi
            prompt_optional_features
            init_full_install
            break 
            ;;
        *"7"*) break ;;
        *) break ;;
    esac
}


# ==============================================================================
# Menu 
# ==============================================================================

clear
while true; do
    draw_header
    MENU_ITEMS="1. ${C_GREEN}Full Install${RESET} [Install packages and .configs]\n"
    MENU_ITEMS+="2. ${C_CYAN}Install Only Config${RESET} [Install .configs]\n"
    MENU_ITEMS+="3. ${DIM}Exit${RESET}"

    OPTION_INSTALL=$(echo -e "$MENU_ITEMS" | fzf \
        --ansi \
        --layout=reverse \
        --border=rounded \
        --margin=1,2 \
        --height=16 \
        --prompt=" Main Menu > " \
        --pointer=">" \
        --header=" Navigate with ARROWS. Select with ENTER. ")


    case "$OPTION_INSTALL" in
        *"1"*) menu_full_install ;;
        *"2"*) 
            init_install_theme_and_config 
            break
            ;;
        *"3"*) clear; exit 0 ;;
        *) exit 0 ;;
    esac
done


