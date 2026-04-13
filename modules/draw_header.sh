# ==============================================================================
# Interactive TUI Functions
# ==============================================================================

draw_header() {
    printf "\033[H"
    printf "${BOLD}${C_CYAN}"
    cat << "EOF"
████████╗██████╗  █████╗ ███╗   ██╗ ██████╗ ██╗   ██╗██╗██╗      █████╗ ███╗   ██╗██████╗      ██╗    ██████╗ 
╚══██╔══╝██╔══██╗██╔══██╗████╗  ██║██╔═══██╗██║   ██║██║██║     ██╔══██╗████╗  ██║██╔══██╗    ███║   ██╔═████╗
   ██║   ██████╔╝███████║██╔██╗ ██║██║   ██║██║   ██║██║██║     ███████║██╔██╗ ██║██║  ██║    ╚██║   ██║██╔██║
   ██║   ██╔══██╗██╔══██║██║╚██╗██║██║▄▄ ██║██║   ██║██║██║     ██╔══██║██║╚██╗██║██║  ██║     ██║   ████╔╝██║
   ██║   ██║  ██║██║  ██║██║ ╚████║╚██████╔╝╚██████╔╝██║███████╗██║  ██║██║ ╚████║██████╔╝     ██║██╗╚██████╔╝
   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚══▀▀═╝  ╚═════╝ ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝      ╚═╝╚═╝ ╚═════╝ 
                                                                                                              
EOF
    printf "${RESET}\n"

    # OSC 8 Escape Sequences for Clickable Hyperlinks
    local OSC8_GH="\e]8;;https://github.com/Duban-sg/tranquiland-dots.git\a"
    local OSC8_ORGH="\e]8;;https://github.com/ilyamiro/imperative-dots.git\a"
    local OSC8_TW="\e]8;;https://twitter.com/ilyamirox\a"
    local OSC8_RD="\e]8;;https://reddit.com/r/ilyamiro1\a"
    local OSC8_END="\e]8;;\a"

    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD}${C_GREEN} GitHub:${RESET}  ${OSC8_GH}Duban-sg/tranquiland-dots${OSC8_END} \n"
    printf "\033[K${BOLD}${C_GREEN} GitHub original Project:${RESET} ${OSC8_ORGH}ilyamiro/imperative-dots${OSC8_END} \n"
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
