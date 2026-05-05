#!/usr/bin/env bash

draw_header() {
    clear
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

    local OSC8_GH="\e]8;;https://github.com/ilyamiro/imperative-dots.git\a"
    local OSC8_TW="\e]8;;https://twitter.com/ilyamirox\a"
    local OSC8_RD="\e]8;;https://reddit.com/u/ilyamiro1\a"
    local OSC8_KF="\e]8;;https://ko-fi.com/ilyamiro\a"
    local OSC8_END="\e]8;;\a"

    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD}${C_GREEN} GitHub:${RESET}  ${OSC8_GH}https://github.com/ilyamiro/imperative-dots.git${OSC8_END}\n"
    printf "\033[K${BOLD}${C_CYAN} Twitter:${RESET} ${OSC8_TW}@ilyamirox${OSC8_END}  |  ${BOLD}${C_RED}Reddit:${RESET} ${OSC8_RD}u/ilyamiro1${OSC8_END}\n"
    printf "\033[K${BOLD}${C_MAGENTA} Donate:${RESET}  ${OSC8_KF}Donate on Ko-fi (Help the project!)${OSC8_END}\n"
    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD} User:           ${RESET} %s\n" "$USER_NAME"
    printf "\033[K${BOLD} OS:             ${RESET} %s\n" "$OS_NAME"
    printf "\033[K${BOLD} CPU:            ${RESET} %s\n" "$CPU_INFO"
    printf "\033[K${BOLD} GPU:            ${RESET} %s\n" "$GPU_INFO"
    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD} Server Version: ${RESET} %s\n" "$DOTS_VERSION"
    printf "\033[K${BOLD} Local Version:  ${RESET} %s\n" "$LOCAL_VERSION"
    printf "\033[K${C_BLUE} =================================================================${RESET}\n\n"
}

# ==============================================================================
# Submenus
# ==============================================================================

manage_packages() {
    while true; do
        draw_header
        local action
        action=$(echo -e "1. View Packages to be Installed\n2. Add Custom Packages\n3. Back to Main Menu" | fzf \
            --layout=reverse --border=rounded --margin=1,2 --height=15 \
            --prompt=" Package Manager > " --pointer=">" \
            --header=" Use ARROW KEYS and ENTER ")

        case "$action" in
            *"1"*)
                echo "${PKGS[@]}" | tr ' ' '\n' | fzf \
                    --layout=reverse --border=rounded --margin=1,2 --height=25 \
                    --prompt=" Current Packages > " --pointer=">" \
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
            *"3"*|*) VISITED_PKGS=true; break ;;
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

        local current_driver="None"
        if command -v lsmod &>/dev/null; then
            if lsmod | grep -wq nvidia; then current_driver="nvidia"
            elif lsmod | grep -wq nouveau; then current_driver="nouveau"
            elif lsmod | grep -Ewq "amdgpu|radeon"; then current_driver="amd"
            elif lsmod | grep -Ewq "i915|xe"; then current_driver="intel"
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
            "AMD")   options="1. Install AMD Mesa & Vulkan Drivers (RADV)\n2. Skip Driver Installation" ;;
            "INTEL") options="1. Install Intel Mesa & Vulkan Drivers (ANV)\n2. Skip Driver Installation" ;;
            *)       options="1. Install Generic Mesa Drivers (For VMs / Software Rendering)\n2. Skip Driver Installation" ;;
        esac

        local choice
        choice=$(echo -e "$options\nBack to Main Menu" | fzf \
            --ansi --layout=reverse --border=rounded --margin=1,2 --height=15 \
            --prompt=" Drivers > " --pointer=">" \
            --header=" Select the graphics drivers to install ")

        [[ "$choice" == *"Back"* ]] && break

        if [[ "$choice" != *"Skip"* ]]; then
            echo -e "\n${BOLD}${C_RED}=================== ACTION REQUIRED ===================${RESET}"
            echo -e "${C_YELLOW}You have selected to AUTOMATICALLY install/configure drivers.${RESET}"
            echo -e "${C_YELLOW}If your system already has working drivers, this might break your boot sequence.${RESET}"
            echo -n -e "Are you ${BOLD}${C_RED}100% sure${RESET} you want to proceed? (y/n): "
            read -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "\n${C_RED}Driver setup aborted. Returning to menu...${RESET}"
                sleep 1.2
                continue
            fi
        fi

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
        # --- Americas ---
        "us - English (US)" "ca - English/French (Canada)" "ca-multix - Canadian Multilingual"
        "latam - Spanish (Latin America)" "br - Portuguese (Brazil)" "ar - Arabic (Latin America)"
        "bo - Bolivia" "cl - Chile" "co - Colombia" "cr - Costa Rica" "cu - Cuba" 
        "do - Dominican Republic" "ec - Ecuador" "sv - El Salvador" "gt - Guatemala" 
        "hn - Honduras" "mx - Mexico" "ni - Nicaragua" "pa - Panama" "py - Paraguay" 
        "pe - Peru" "pr - Puerto Rico" "uy - Uruguay" "ve - Venezuela"

        # --- Europe (West, Central, & North) ---
        "gb - English (UK)" "ie - English (Ireland)" "gd - Scottish Gaelic" "cy-gb - Welsh"
        "fr - French" "be - Belgian" "ch - Swiss" "de - German" "at - Austrian" 
        "nl - Dutch" "lu - Luxembourgish" "es - Spanish" "pt - Portuguese" 
        "it - Italian" "mt - Maltese" "se - Swedish" "no - Norwegian" "dk - Danish" 
        "fi - Finnish" "is - Icelandic" "fo - Faroese" "gl - Greenlandic"
        "pl - Polish" "cz - Czech" "sk - Slovak" "hu - Hungarian" 
        "ad - Andorra" "mc - Monaco" "sm - San Marino" "va - Vatican"
        "epo - Esperanto" "eu - Basque" "ca-fr - Catalan" 

        # --- Europe (East) & Caucasus ---
        "ru - Russian" "ua - Ukrainian" "by - Belarusian" "ro - Romanian" "bg - Bulgarian" 
        "rs - Serbian" "hr - Croatian" "si - Slovenian" "mk - Macedonian" "ba - Bosnian" 
        "me - Montenegrin" "gr - Greek" "cy - Cyprus" "ee - Estonian" "lv - Latvian" 
        "lt - Lithuanian" "md - Moldovan" "am - Armenian" "ge - Georgian" "az - Azerbaijani" 
        "kz - Kazakh" "kg - Kyrgyz" "tj - Tajik" "tm - Turkmen" "uz - Uzbek" 
        "mn - Mongolian" "tat - Tatar" "chu - Chuvash" "os - Ossetian" "udm - Udmurt" 
        "kbd - Kabardian" "che - Chechen"

        # --- Asia & Pacific ---
        "au - English (Australia)" "nz - English (New Zealand)" 
        "cn - Chinese" "jp - Japanese" "kr - Korean" "tw - Taiwanese" "hk - Hong Kong"
        "in - Indian" "pk - Pakistani" "bd - Bangla" "lk - Sri Lankan" "np - Nepali" 
        "mv - Maldivian (Dhivehi)" "bt - Bhutanese (Dzongkha)" "af - Afghan (Pashto/Dari)"
        "th - Thai" "vn - Vietnamese" "la - Lao" "mm - Burmese" "kh - Khmer" 
        "id - Indonesian" "my - Malay" "ph - Filipino" "sg - Singaporean" 
        "bn - Bengali" "ta - Tamil" "te - Telugu" "gu - Gujarati" "pa - Punjabi" 
        "ml - Malayalam" "kn - Kannada" "or - Odia" "as - Assamese" "ur - Urdu"

        # --- Middle East & North Africa ---
        "il - Hebrew" "ara - Arabic" "iq - Iraqi" "sy - Syrian" "ir - Persian (Farsi)"
        "ma - Moroccan" "dz - Algerian" "eg - Egyptian" "ly - Libyan" "tn - Tunisian" 
        "sd - Sudanese" "lb - Lebanese" "jo - Jordanian" "ps - Palestinian" 
        "sa - Saudi Arabian" "kw - Kuwaiti" "bh - Bahraini" "qa - Qatari" "ae - UAE" 
        "om - Omani" "ye - Yemeni"

        # --- Sub-Saharan Africa ---
        "za - English (South Africa)" "ng - Nigerian" "et - Ethiopian" "sn - Senegalese"
        "ke - Kenyan" "tz - Tanzanian" "gh - Ghanaian" "cm - Cameroonian" "ci - Ivorian"
        "ml - Malian" "gn - Guinean" "cd - Congolese (DRC)" "cg - Congolese (RC)"
        "rw - Rwandan" "bi - Burundian" "ug - Ugandan" "zm - Zambian" "zw - Zimbabwean"
        "mw - Malawian" "mz - Mozambican" "ao - Angolan" "na - Namibian" "bw - Motswana"
        "mg - Malagasy" "so - Somali" "dj - Djiboutian" "er - Eritrean" "tg - Togolese"
        "bj - Beninese" "bf - Burkinabe" "ne - Nigerien" "td - Chadian" "cf - Central African"
        "gq - Equatorial Guinean" "ga - Gabonese"

        # --- Alternative Layouts ---
        "us-intl - US International" "dvorak - US Dvorak" "colemak - US Colemak" 
        "norman - US Norman" "workman - US Workman" "math - Mathematics" "brai - Braille"
    )

    local selected_codes=()
    local selected_names=()

    if [[ -n "$KB_LAYOUTS" ]]; then
        IFS=',' read -ra tmp_codes <<< "$KB_LAYOUTS"
        for code in "${tmp_codes[@]}"; do selected_codes+=("$(echo "$code" | xargs)"); done
    else
        selected_codes=("us")
    fi

    if [[ -n "$KB_LAYOUTS_DISPLAY" ]]; then
        IFS=',' read -ra tmp_names <<< "$KB_LAYOUTS_DISPLAY"
        for name in "${tmp_names[@]}"; do selected_names+=("$(echo "$name" | xargs)"); done
    else
        selected_names=("English (US)")
    fi

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"
        [ ${#selected_codes[@]} -gt 0 ] && \
            echo -e "Currently added (US is mandatory): ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"

        local choice
        choice=$(printf "%s\n" "Done (Finish Selection)" "Reset (Clear All Except US)" "${available_layouts[@]}" | fzf \
            --layout=reverse --border=rounded --margin=1,2 --height=20 \
            --prompt=" Add Layout > " --pointer=">" \
            --header=" Select a language to add, or select Done ")

        [[ -z "$choice" || "$choice" == *"Done"* ]] && break

        if [[ "$choice" == *"Reset"* ]]; then
            selected_codes=("us")
            selected_names=("English (US)")
            continue
        fi

        local code name duplicate=false
        code=$(echo "$choice" | awk '{print $1}')
        name=$(echo "$choice" | cut -d'-' -f2- | sed 's/^ //')

        for existing in "${selected_codes[@]}"; do
            [[ "$existing" == "$code" ]] && duplicate=true && break
        done

        if [ "$duplicate" = false ]; then
            selected_codes+=("$code")
            selected_names+=("$name")
        fi
    done

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"
        echo -e "Currently added: ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"
        echo -e "${C_CYAN}Choose a key combination to switch between layouts:${RESET}"

        local options="1. Alt + Shift (grp:alt_shift_toggle)\n2. Win + Space (grp:win_space_toggle)\n"
        options+="3. Caps Lock (grp:caps_toggle)\n4. Ctrl + Shift (grp:ctrl_shift_toggle)\n"
        options+="5. Ctrl + Alt (grp:ctrl_alt_toggle)\n6. Right Alt (grp:toggle)\n7. No Toggle (Single Layout)"

        local choice
        choice=$(echo -e "$options" | fzf \
            --ansi --layout=reverse --border=rounded --margin=1,2 --height=15 \
            --prompt=" Toggle Keybind > " --pointer=">" \
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
            *)     kb_opt="grp:alt_shift_toggle" ;;
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
    draw_header
    echo -e "${BOLD}${C_MAGENTA}=== System Overview & Keybinds ===${RESET}\n"
    echo -e "This configuration is an adaptation of the ${BOLD}${C_CYAN}ilyamiro/nixos-configuration${RESET} setup."
    echo -e "Here are the core keybindings to navigate your new system once installed:\n"

    print_kb() {
        printf "  ${C_CYAN}[${RESET} ${BOLD}%-17s${RESET} ${C_CYAN}]${RESET}  ${C_YELLOW}➜${RESET}  %s\n" "$1" "$2"
    }

    echo -e "${BOLD}${C_BLUE}--- Applications ---${RESET}"
    print_kb "SUPER + RETURN" "Open Terminal (kitty)"
    print_kb "SUPER + D"      "Open App Launcher (rofi)"
    print_kb "SUPER + F"      "Open Browser (Firefox)"
    print_kb "SUPER + E"      "Open File Manager (nautilus)"
    print_kb "SUPER + C"      "Clipboard History (rofi)"
    echo ""

    echo -e "${BOLD}${C_BLUE}--- Quickshell Widgets ---${RESET}"
    print_kb "SUPER + M"       "Toggle Monitors"
    print_kb "SUPER + Q"       "Toggle Music"
    print_kb "SUPER + B"       "Toggle Battery"
    print_kb "SUPER + W"       "Toggle Wallpaper"
    print_kb "SUPER + S"       "Toggle Calendar"
    print_kb "SUPER + N"       "Toggle Network"
    print_kb "SUPER + SHIFT+T" "Toggle FocusTime"
    print_kb "SUPER + V"       "Toggle Volume Control"
    echo ""

    echo -e "${BOLD}${C_BLUE}--- Window Management ---${RESET}"
    print_kb "ALT + F4"        "Close Active Window / Widget"
    print_kb "SUPER + SHIFT+F" "Toggle Floating"
    print_kb "SUPER + Arrows"  "Move Focus"
    print_kb "SUPER + CTRL+Arr" "Move Window"
    echo ""

    echo -e "${BOLD}${C_BLUE}--- System Controls ---${RESET}"
    print_kb "SUPER + L"    "Lock Screen"
    print_kb "Print Screen" "Screenshot"
    print_kb "SHIFT + Print" "Screenshot (Edit)"
    print_kb "ALT + SHIFT"  "Switch Keyboard Layout"
    echo ""

    echo -e "${BOLD}${C_GREEN}Press ENTER to return to the Main Menu...${RESET}"
    read -r
    VISITED_OVERVIEW=true
}

set_weather_api() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== OpenWeatherMap Interactive Setup ===${RESET}"

        local ENV_FILE="$HOME/.config/hypr/scripts/quickshell/calendar/.env"

        if [ -f "$ENV_FILE" ] || [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
            echo -e "${C_GREEN}An existing Weather configuration (.env) was detected.${RESET}"
            echo -e "${BOLD}${C_YELLOW}Press ENTER without typing anything to KEEP your existing configuration.${RESET}\n"
        else
            echo -e "${BOLD}${C_YELLOW}Without this, weather widgets WILL NOT WORK.${RESET}\n"
            echo -e "${C_MAGENTA}How to get a free API key:${RESET}"
            echo -e "  1. Visit ${C_BLUE}https://openweathermap.org/${RESET}"
            echo -e "  2. Create a free account and log in."
            echo -e "  3. Click your profile name -> 'My API keys'."
            echo -e "  4. Generate a new key and paste it below."
            echo -e "  ${BOLD}${C_YELLOW}Note: New keys may take a couple of hours to activate.${RESET}\n"
        fi

        read -p "Enter your OpenWeather API Key (or press Enter to skip/keep): " input_key

        if [[ -z "$input_key" ]]; then
            if [ -f "$ENV_FILE" ] || [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
                echo -e "\n${C_GREEN}Keeping existing weather configuration.${RESET}"
                KEEP_OLD_ENV=true
                VISITED_WEATHER=true
                sleep 1.5
                break
            else
                echo -e "\n${C_RED}WARNING: You did not enter an API key.${RESET}"
                echo -n -e "Are you ${BOLD}${C_RED}100% sure${RESET} you want to proceed without it? (y/n): "
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    WEATHER_API_KEY="Skipped"
                    WEATHER_CITY_ID=""
                    WEATHER_UNIT=""
                    KEEP_OLD_ENV=false
                    VISITED_WEATHER=true
                    break
                fi
                continue
            fi
        fi

        input_key=$(echo "$input_key" | tr -d ' ')
        if [[ ${#input_key} -ne 32 ]]; then
            echo -e "\n${C_YELLOW}Warning: OpenWeather API keys are typically exactly 32 characters long.${RESET}"
            echo -e "${C_YELLOW}Your key is ${#input_key} characters long.${RESET}"
            echo -n "Are you sure this key is correct? (y/n): "
            read -r confirm_key
            [[ ! "$confirm_key" =~ ^[Yy]$ ]] && continue
        fi

        WEATHER_API_KEY="$input_key"

        echo -e "\n${C_CYAN}Let's set your location using your City ID.${RESET}"
        echo -e "1. Go to ${C_BLUE}https://openweathermap.org/${RESET} and search for your city."
        echo -e "2. Look at the URL — it ends with the City ID number.\n"
        read -p "Enter City ID: " input_id

        if [[ -z "$input_id" || ! "$input_id" =~ ^[0-9]+$ ]]; then
            echo -e "${C_RED}Invalid City ID. It must be a number.${RESET}"
            sleep 1.5
            continue
        fi

        WEATHER_CITY_ID="$input_id"

        local unit_choice
        unit_choice=$(echo -e "metric (Celsius)\nimperial (Fahrenheit)\nstandard (Kelvin)" | fzf \
            --layout=reverse --border=rounded --margin=1,2 --height=12 \
            --prompt=" Select Temperature Unit > " --pointer=">" \
            --header=" Choose your preferred unit format ")

        WEATHER_UNIT=$(echo "$unit_choice" | awk '{print $1}')
        [[ -z "$WEATHER_UNIT" ]] && WEATHER_UNIT="metric"

        KEEP_OLD_ENV=false
        echo -e "\n${C_GREEN}Weather configuration complete!${RESET}"
        sleep 2.5
        VISITED_WEATHER=true
        break
    done
}

manage_telemetry() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Telemetry Configuration ===${RESET}\n"
        echo -e "To help improve this dotfile environment, this script can send"
        echo -e "anonymous hardware statistics when you start the installation.\n"
        echo -e "${BOLD}What is sent if enabled:${RESET}"
        echo -e "  - Script Version, OS Name, Kernel, RAM, DE, CPU, GPU\n"
        echo -e "${BOLD}${C_YELLOW}Absolutely NO personal data, IP addresses, or usernames are collected.${RESET}\n"

        local current_status="${DIM}OFF${RESET}"
        [[ "$ENABLE_TELEMETRY" == true ]] && current_status="${C_GREEN}ON${RESET}"
        echo -e "Current Status: ${BOLD}$current_status${RESET}\n"

        local action
        action=$(echo -e "1. Enable Telemetry\n2. Disable Telemetry\n3. Back to Main Menu" | fzf \
            --layout=reverse --border=rounded --margin=1,2 --height=12 \
            --prompt=" Telemetry > " --pointer=">" \
            --header=" Use ARROW KEYS and ENTER ")

        case "$action" in
            *"1"*)
                ENABLE_TELEMETRY=true
                echo -e "${C_GREEN}Telemetry Enabled. Thank you!${RESET}"
                sleep 1; break
                ;;
            *"2"*)
                if [[ "$ENABLE_TELEMETRY" == true ]]; then
                    echo -n -e "\nAre you sure you want to disable telemetry? (y/n) "
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        ENABLE_TELEMETRY=false
                        echo -e "${C_YELLOW}Telemetry Disabled.${RESET}"
                        sleep 1.2; break
                    fi
                else
                    break
                fi
                ;;
            *) break ;;
        esac
    done
}

prompt_optional_features_menu() {
    detect_display_manager

    local DM_LABEL="Display Manager Integration (SDDM)"
    [[ "$CURRENT_DM" == "sddm" ]] && DM_LABEL="Configure SDDM Theme (sddm detected)"
    [[ -n "$CURRENT_DM" && "$CURRENT_DM" != "sddm" ]] && DM_LABEL="Replace $CURRENT_DM with SDDM"

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Optional Component Setup ===${RESET}\n"

        local S_SDDM S_NVIM S_ZSH S_WP S_KB_OVR S_STARTUPS_OVR
        S_SDDM=$([ "$OPT_SDDM" = true ]             && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")
        S_NVIM=$([ "$OPT_NVIM" = true ]             && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")
        S_ZSH=$([ "$OPT_ZSH" = true ]               && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")
        S_WP=$([ "$OPT_WALLPAPERS" = true ]         && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")
        S_KB_OVR=$([ "$OPT_OVERRIDE_KEYBINDS" = true ]  && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")
        S_STARTUPS_OVR=$([ "$OPT_OVERRIDE_STARTUPS" = true ] && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")

        local MENU_ITEMS
        MENU_ITEMS="1. $S_SDDM $DM_LABEL\n"
        MENU_ITEMS+="2. $S_NVIM Neovim Matugen Configuration\n"
        MENU_ITEMS+="3. $S_ZSH Zsh Shell Setup\n"
        MENU_ITEMS+="4. $S_WP Download FULL Wallpaper Pack (Unchecked = 3 Random)\n"
        MENU_ITEMS+="5. $S_KB_OVR Override Keybinds (Unchecked = Keep Local)\n"
        MENU_ITEMS+="6. $S_STARTUPS_OVR Override Startups (Unchecked = Keep Local, Add missing ones)\n"
        MENU_ITEMS+="7. ${BOLD}${C_GREEN}Proceed with Installation / Update${RESET}\n"
        MENU_ITEMS+="8. ${DIM}Back to Main Menu${RESET}"

        local choice
        choice=$(echo -e "$MENU_ITEMS" | fzf \
            --ansi --layout=reverse --border=rounded --margin=1,2 --height=15 \
            --prompt=" Options > " --pointer=">" \
            --header=" SPACE or ENTER to toggle. Select Proceed when ready. ")

        case "$choice" in
            *"1."*) OPT_SDDM=$([ "$OPT_SDDM" = true ] && echo false || echo true) ;;
            *"2."*) OPT_NVIM=$([ "$OPT_NVIM" = true ] && echo false || echo true) ;;
            *"3."*) OPT_ZSH=$([ "$OPT_ZSH" = true ] && echo false || echo true) ;;
            *"4."*) OPT_WALLPAPERS=$([ "$OPT_WALLPAPERS" = true ] && echo false || echo true) ;;
            *"5."*) OPT_OVERRIDE_KEYBINDS=$([ "$OPT_OVERRIDE_KEYBINDS" = true ] && echo false || echo true) ;;
            *"6."*) OPT_OVERRIDE_STARTUPS=$([ "$OPT_OVERRIDE_STARTUPS" = true ] && echo false || echo true) ;;
            *"7."*)
                if [ "$OPT_SDDM" = true ]; then
                    if [[ -z "$CURRENT_DM" ]]; then
                        INSTALL_SDDM=true; SETUP_SDDM_THEME=true; PKGS+=("sddm")
                    elif [[ "$CURRENT_DM" == "sddm" ]]; then
                        SETUP_SDDM_THEME=true
                    else
                        INSTALL_SDDM=true; REPLACE_DM=true; SETUP_SDDM_THEME=true; PKGS+=("sddm")
                    fi
                    clear; draw_header
                    echo -e "${BOLD}${C_CYAN}=== SDDM Configuration ===${RESET}\n"
                    echo -e "Do you want to force SDDM to run natively on Wayland?"
                    echo -e "${DIM}(May cause issues with some NVIDIA setups. Default is No.)${RESET}"
                    read -p "Force SDDM Wayland backend? (y/N): " sddm_wayland
                    [[ "$sddm_wayland" =~ ^[Yy]$ ]] && SDDM_WAYLAND=true || SDDM_WAYLAND=false
                fi
                [ "$OPT_NVIM" = true ] && { INSTALL_NVIM=true; PKGS+=("neovim" "lua-language-server" "unzip" "nodejs" "npm" "python3"); }
                [ "$OPT_ZSH" = true ]  && { INSTALL_ZSH=true;  PKGS+=("zsh"); }
                return 0
                ;;
            *"8."*) return 1 ;;
        esac
    done
}

# ==============================================================================
# Main Menu
# ==============================================================================

run_main_menu() {
    while true; do
        draw_header

        local S_PKG S_OVW S_WTH S_DRV S_KBD S_TEL API_DISPLAY INSTALL_LABEL
        S_PKG=$([ "$VISITED_PKGS" = true ]     && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}")
        S_OVW=$([ "$VISITED_OVERVIEW" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}")
        S_WTH=$([ "$VISITED_WEATHER" = true ]  && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}")
        S_DRV=$([ "$VISITED_DRIVERS" = true ]  && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}")
        S_KBD=$([ "$VISITED_KEYBOARD" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_RED}[ ]${RESET}")
        S_TEL=$([ "$ENABLE_TELEMETRY" = true ] && echo -e "${C_GREEN}[ON]${RESET}" || echo -e "${DIM}[OFF]${RESET}")

        if [[ -z "$WEATHER_API_KEY" ]]; then
            [ -f "$HOME/.config/hypr/scripts/quickshell/calendar/.env" ] \
                && API_DISPLAY="Set (from .env file)" \
                || API_DISPLAY="Not Set"
        elif [[ "$WEATHER_API_KEY" == "Skipped" ]]; then
            API_DISPLAY="Skipped"
        else
            API_DISPLAY="Set ($WEATHER_UNIT, ID: $WEATHER_CITY_ID)"
        fi

        [ "$LOCAL_VERSION" != "Not Installed" ] && [ -n "$LOCAL_VERSION" ] \
            && INSTALL_LABEL="UPDATE" || INSTALL_LABEL="START"

        local MENU_ITEMS
        MENU_ITEMS="1. $S_PKG ${C_GREEN}Manage Packages${RESET} [${#PKGS[@]} queued, Optional]\n"
        MENU_ITEMS+="2. $S_OVW ${C_CYAN}Overview & Keybinds${RESET} [Optional]\n"
        MENU_ITEMS+="3. $S_WTH ${C_YELLOW}Set Weather API Key${RESET} [${API_DISPLAY}, Optional]\n"
        MENU_ITEMS+="4. $S_DRV ${C_RED}[ DRIVERS ] Setup${RESET} [${DRIVER_CHOICE}, Optional]\n"
        MENU_ITEMS+="5. $S_KBD ${C_BLUE}Keyboard Layout Setup${RESET} [${KB_LAYOUTS_DISPLAY:-$KB_LAYOUTS}]\n"
        MENU_ITEMS+="6. $S_TEL ${C_CYAN}Telemetry Settings${RESET}\n"
        MENU_ITEMS+="7. ${BOLD}${C_MAGENTA}${INSTALL_LABEL}${RESET}\n"
        MENU_ITEMS+="8. ${DIM}Exit${RESET}"

        local MENU_OPTION
        MENU_OPTION=$(echo -e "$MENU_ITEMS" | fzf \
            --ansi --layout=reverse --border=rounded --margin=1,2 --height=17 \
            --prompt=" Main Menu > " --pointer=">" \
            --header=" Navigate with ARROWS. Select with ENTER. ")

        case "$MENU_OPTION" in
            *"1."*) manage_packages ;;
            *"2."*) show_overview ;;
            *"3."*) set_weather_api ;;
            *"4."*) manage_drivers ;;
            *"5."*) manage_keyboard ;;
            *"6."*) manage_telemetry ;;
            *"7."*)
                if [ "$VISITED_KEYBOARD" = false ]; then
                    echo -e "\n${C_RED}[!] You must configure your Keyboard Layouts before starting.${RESET}"
                    sleep 2.5; continue
                fi
                prompt_optional_features_menu && break || continue
                ;;
            *"8."*|*) clear; exit 0 ;;
        esac
    done
}