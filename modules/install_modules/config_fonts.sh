


config_fonts(){

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
}




