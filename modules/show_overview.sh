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