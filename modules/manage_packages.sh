#!/usr/bin/env bash

# ==============================================================================
# Function to select default packages
# ==============================================================================

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