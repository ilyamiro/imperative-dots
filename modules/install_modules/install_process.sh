


#!/bin/bash
DIR_ACTUAL="$(pwd)"


source "$DIR_ACTUAL/resolve_package.sh"
source "$DIR_ACTUAL/install_drivers.sh"
source "$DIR_ACTUAL/config_display_manager.sh"
source "$DIR_ACTUAL/config_wallpapers.sh"
source "$DIR_ACTUAL/copy_dotfiles.sh"
source "$DIR_ACTUAL/config_fonts.sh"
source "$DIR_ACTUAL/config_Adaptability.sh"
source "$DIR_ACTUAL/config_theme.sh"



init_display() {
    clear
    draw_header
    echo -e "\e[1;34m=== INSTALADOR IMPERATIVE-DOTS ===\e[0m"
    echo "" # Espacio reservado para la barra de progreso (Línea 2)
    echo "----------------------------------"
}

finish_display(){
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
}

# Función de progreso: uso -> mostrar_progreso actual total
show_progress() {

    local actual=$1
    local ancho_barra=30
    
    # Cálculos
    local porcentaje=$(( actual * 100 / total ))
    local rellenos=$(( actual * ancho_barra / total ))
    local vacios=$(( ancho_barra - rellenos ))

    # Guardar posición actual del cursor
    tput sc 

    # Mover el cursor a la línea 2, columna 0 (donde está el espacio vacío)
    tput cup 16 0 

    # Construir y pintar la barra (con colores)
    local barra_visual=$(printf "%${rellenos}s" | tr ' ' '#')
    local vacio_visual=$(printf "%${vacios}s" | tr ' ' '-')
    
    # \e[K limpia la línea antes de escribir para que no queden restos
    printf "\e[K\e[1;32mProgreso: [%s%s] %d%%\e[0m" "$barra_visual" "$vacio_visual" "$porcentaje"

    # Restaurar el cursor a su posición original
    tput rc
}

# Combine Base Packages with chosen Driver Packages
combine_base_package(){
    
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
}

finalize_version_marker(){
    
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
}


# ==============================================================================
# Installation Process
# ==============================================================================
init_install() {

    init_display

    show_progress 1 
    # Pre-authenticate sudo to prevent password prompts from breaking during piped commands
    echo -e "${C_CYAN}[ INFO ]${RESET} Requesting sudo privileges for installation..."
    sudo -v

    # --- 2. Resolve Package Conflicts ---
    show_progress 2 
    resolve_package

    combine_base_package

    # --- 3. Install Dependencies & Drivers ---
    show_progress 3 
    install_drivers

    # --- 4. Display Manager Cleanup & SDDM Setup ---
    show_progress 4 
    config_display_manager

    # --- 5. Repository Cloning & Wallpapers ---
    show_progress 5 
    config_wallpapers

    # --- 6. Copying Dotfiles & Backups ---
    show_progress 6 
    copy_dotfiles

    # --- 7. Fonts ---
    show_progress 7 
    config_fonts

    # --- 8. Adaptability Phase ---
    show_progress 8 
    config_Adaptability

    # --- 9. Setup SDDM Theme and Config ---
    show_progress 9 
    config_theme

    # --- 9. Finalize Version Marker & User State Persistence ---
    show_progress 10 
    finalize_version_marker

    # --- 9. Final Output ---
    show_progress 11 
    finish_display

}