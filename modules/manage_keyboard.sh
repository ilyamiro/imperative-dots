
manage_keyboard() {
    local available_layouts=(
        "us - English (US)" "gb - English (UK)" "ru - Russian" "ua - Ukrainian"
        "de - German" "fr - French" "es - Spanish" "it - Italian" "pl - Polish"
        "pt - Portuguese" "br - Portuguese (Brazil)" "se - Swedish" "no - Norwegian"
        "dk - Danish" "fi - Finnish" "nl - Dutch" "tr - Turkish" "cz - Czech"
        "hu - Hungarian" "ro - Romanian" "jp - Japanese" "kr - Korean" "cn - Chinese"
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