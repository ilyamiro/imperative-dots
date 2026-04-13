
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