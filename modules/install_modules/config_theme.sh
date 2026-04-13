



config_theme(){

    if [[ "$SETUP_SDDM_THEME" == true ]]; then
        if [ -d "$REPO_DIR/.config/sddm/themes/matugen-minimal" ]; then
            sudo mkdir -p /usr/share/sddm/themes/matugen-minimal
            sudo cp -r "$REPO_DIR/.config/sddm/themes/matugen-minimal/"* /usr/share/sddm/themes/matugen-minimal/
            
            # FIX 1: Provide a valid fallback QML file. 
            # If this file is empty, SDDM can crash before Matugen even gets to run.
            cat <<EOF | sudo tee /usr/share/sddm/themes/matugen-minimal/Colors.qml > /dev/null
pragma Singleton
import QtQuick
QtObject {
    readonly property color base: "#1e1e2e"
    readonly property color crust: "#11111b"
    readonly property color mantle: "#181825"
    readonly property color text: "#cdd6f4"
    readonly property color subtext0: "#a6adc8"
    readonly property color surface0: "#313244"
    readonly property color surface1: "#45475a"
    readonly property color surface2: "#585b70"
    readonly property color mauve: "#cba6f7"
    readonly property color red: "#f38ba8"
    readonly property color peach: "#fab387"
    readonly property color blue: "#89b4fa"
    readonly property color green: "#a6e3a1"
}
EOF
            sudo chown $USER:$USER /usr/share/sddm/themes/matugen-minimal/Colors.qml
            
            # FIX 2: Use a drop-in file for the theme instead of overwriting all of /etc/sddm.conf
            # This preserves the distro's default Wayland/X11 configuration.
            sudo mkdir -p /etc/sddm.conf.d
            echo -e "[Theme]\nCurrent=matugen-minimal" | sudo tee /etc/sddm.conf.d/10-matugen-theme.conf > /dev/null
            
            printf "  -> SDDM Theme configured %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
        fi
    fi
}