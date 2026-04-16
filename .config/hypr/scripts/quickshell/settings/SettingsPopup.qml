import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    focus: true

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        currentWidth: Screen.width
    }
    
    function s(val) { 
        return scaler.s(val); 
    }

    // -------------------------------------------------------------------------
    // KEYBOARD SHORTCUTS
    // -------------------------------------------------------------------------
    Keys.onEscapePressed: {
        closeSequence.start();
        event.accepted = true;
    }

    MatugenColors { id: _theme }
    // -------------------------------------------------------------------------
    // COLORS
    // -------------------------------------------------------------------------
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color overlay0: _theme.overlay0
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color blue: _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color green: _theme.green
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red

    property real colorBlend: 0.0
    SequentialAnimation on colorBlend {
        loops: Animation.Infinite
        running: true
        NumberAnimation { to: 1.0; duration: 15000; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: 15000; easing.type: Easing.InOutSine }
    }
    
    property color ambientPurple: Qt.tint(root.mauve, Qt.rgba(root.pink.r, root.pink.g, root.pink.b, colorBlend))
    property color ambientBlue: Qt.tint(root.blue, Qt.rgba(root.sapphire.r, root.sapphire.g, root.sapphire.b, colorBlend))

    // -------------------------------------------------------------------------
    // SSOT GLOBAL SETTINGS & UPDATES
    // -------------------------------------------------------------------------
    property real setUiScale: 1.0
    property bool setOpenGuideAtStartup: true
    property bool setTopbarHelpIcon: true
    property string setWallpaperDir: {
        const dir = Quickshell.env("WALLPAPER_DIR")
        return (dir && dir !== "") 
        ? dir 
        : Quickshell.env("HOME") + "/Pictures/Wallpapers"
    }
    property string setLanguage: ""
    property string setKbOptions: "grp:alt_shift_toggle"

    property var kbToggleModelArr: [
        { label: "Alt + Shift", val: "grp:alt_shift_toggle" },
        { label: "Win + Space", val: "grp:win_space_toggle" },
        { label: "Caps Lock", val: "grp:caps_toggle" },
        { label: "Ctrl + Shift", val: "grp:ctrl_shift_toggle" },
        { label: "Ctrl + Alt", val: "grp:ctrl_alt_toggle" },
        { label: "Right Alt", val: "grp:toggle" },
        { label: "No Toggle", val: "" }
    ]

    function getKbToggleLabel(val) {
        for (let i = 0; i < root.kbToggleModelArr.length; i++) {
            if (root.kbToggleModelArr[i].val === val) return root.kbToggleModelArr[i].label;
        }
        return "Alt + Shift";
    }

    function saveAppSettings() {
        let config = {
            "uiScale": root.setUiScale,
            "openGuideAtStartup": root.setOpenGuideAtStartup,
            "topbarHelpIcon": root.setTopbarHelpIcon,
            "wallpaperDir": root.setWallpaperDir,
            "language": root.setLanguage,
            "kbOptions": root.setKbOptions
        };
        let jsonString = JSON.stringify(config, null, 2);
        
        let cmd = "mkdir -p ~/.config/hypr/ && echo '" + jsonString + "' > ~/.config/hypr/settings.json && notify-send 'Quickshell' 'Settings Applied Successfully!'";
                  
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    Process {
        id: hyprLangReader
        command: ["bash", "-c", "grep -m1 '^ *kb_layout *=' ~/.config/hypr/hyprland.conf | cut -d'=' -f2 | tr -d ' '"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out.length > 0 && root.setLanguage === "") {
                    root.setLanguage = out;
                }
            }
        }
    }

    Process {
        id: settingsReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        let parsed = JSON.parse(this.text);
                        if (parsed.uiScale !== undefined) root.setUiScale = parsed.uiScale;
                        if (parsed.openGuideAtStartup !== undefined) root.setOpenGuideAtStartup = parsed.openGuideAtStartup;
                        if (parsed.topbarHelpIcon !== undefined) root.setTopbarHelpIcon = parsed.topbarHelpIcon;
                        if (parsed.wallpaperDir !== undefined) root.setWallpaperDir = parsed.wallpaperDir;
                        if (parsed.language !== undefined && parsed.language !== "") root.setLanguage = parsed.language;
                        if (parsed.kbOptions !== undefined) root.setKbOptions = parsed.kbOptions;
                    } else {
                        root.saveAppSettings();
                    }
                } catch (e) {
                    console.log("Error parsing global settings:", e);
                }
            }
        }
    }

    ListModel {
        id: langModel
        ListElement { code: "us"; name: "English (US)" }
        ListElement { code: "gb"; name: "English (UK)" }
        ListElement { code: "au"; name: "English (Australia)" }
        ListElement { code: "ca"; name: "English/French (Canada)" }
        ListElement { code: "ie"; name: "English (Ireland)" }
        ListElement { code: "nz"; name: "English (New Zealand)" }
        ListElement { code: "za"; name: "English (South Africa)" }
        ListElement { code: "fr"; name: "French" }
        ListElement { code: "de"; name: "German" }
        ListElement { code: "es"; name: "Spanish" }
        ListElement { code: "pt"; name: "Portuguese" }
        ListElement { code: "it"; name: "Italian" }
        ListElement { code: "se"; name: "Swedish" }
        ListElement { code: "no"; name: "Norwegian" }
        ListElement { code: "dk"; name: "Danish" }
        ListElement { code: "fi"; name: "Finnish" }
        ListElement { code: "pl"; name: "Polish" }
        ListElement { code: "ru"; name: "Russian" }
        ListElement { code: "ua"; name: "Ukrainian" }
        ListElement { code: "cn"; name: "Chinese" }
        ListElement { code: "jp"; name: "Japanese" }
        ListElement { code: "kr"; name: "Korean" }
    }

    ListModel { id: pathSuggestModel }
    ListModel { id: langSearchModel }

    function updateLangSearch(query) {
        langSearchModel.clear();
        let q = query.trim().toLowerCase();
        if (q === "") return;
        for (let i = 0; i < langModel.count; i++) {
            let item = langModel.get(i);
            if (item.code.toLowerCase().includes(q) || item.name.toLowerCase().includes(q)) {
                langSearchModel.append({ code: item.code, name: item.name });
            }
        }
    }

    Process {
        id: pathSuggestProc
        property string query: ""
        command: ["bash", "-c", "eval ls -dp " + query + "* 2>/dev/null | grep '/$' | head -n 5 || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                pathSuggestModel.clear();
                if (this.text) {
                    let lines = this.text.trim().split('\n');
                    for (let i = 0; i < lines.length; i++) {
                        if (lines[i].length > 0) {
                            pathSuggestModel.append({ path: lines[i] });
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // ANIMATIONS
    // -------------------------------------------------------------------------
    property real introBase: 0.0
    property real introContent: 0.0

    Component.onCompleted: { 
        startupSequence.start(); 
    }

    ParallelAnimation {
        id: startupSequence
        NumberAnimation { 
            target: root
            property: "introBase"
            from: 0.0
            to: 1.0
            duration: 900
            easing.type: Easing.OutExpo 
        }
        SequentialAnimation { 
            PauseAnimation { duration: 150 }
            NumberAnimation { 
                target: root
                property: "introContent"
                from: 0.0
                to: 1.0
                duration: 1000
                easing.type: Easing.OutBack
                easing.overshoot: 1.02 
            } 
        }
    }

    SequentialAnimation {
        id: closeSequence
        ParallelAnimation { 
            NumberAnimation { 
                target: root
                property: "introContent"
                to: 0.0
                duration: 150
                easing.type: Easing.InExpo 
            }
        }
        NumberAnimation { 
            target: root
            property: "introBase"
            to: 0.0
            duration: 200
            easing.type: Easing.InQuart 
        }
        ScriptAction { 
            script: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]) 
        }
    }

    // -------------------------------------------------------------------------
    // BACKGROUND AMBIENCE
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        opacity: introBase
        scale: 0.95 + (0.05 * introBase)
        
        Rectangle {
            anchors.fill: parent
            radius: root.s(16)
            color: root.base
            border.color: root.surface0
            border.width: 1
            clip: true
            
            property real time: 0
            NumberAnimation on time { 
                from: 0
                to: Math.PI * 2
                duration: 20000
                loops: Animation.Infinite
                running: true 
            }
            
            Rectangle {
                width: root.s(600)
                height: root.s(600)
                radius: root.s(300)
                x: parent.width * 0.6 + Math.cos(parent.time) * root.s(100)
                y: parent.height * 0.1 + Math.sin(parent.time * 1.5) * root.s(100)
                color: root.ambientPurple
                opacity: 0.04
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blurMax: 80; blur: 1.0 }
            }
            
            Rectangle {
                width: root.s(700)
                height: root.s(700)
                radius: root.s(350)
                x: parent.width * 0.1 + Math.sin(parent.time * 0.8) * root.s(150)
                y: parent.height * 0.4 + Math.cos(parent.time * 1.2) * root.s(100)
                color: root.ambientBlue
                opacity: 0.03
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blurMax: 90; blur: 1.0 }
            }
        }
    }

    // -------------------------------------------------------------------------
    // CONTENT AREA
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        opacity: introContent
        scale: 0.95 + (0.05 * introContent)
        transform: Translate { y: root.s(20) * (1.0 - introContent) }

        ColumnLayout {
            id: settingsMainCol
            anchors.fill: parent
            anchors.margins: root.s(40)
            spacing: root.s(20)

            property real iconColWidth: root.s(32)
            property real controlColWidth: root.s(240)

            // --- HEADER & APPLY BUTTON ---
            RowLayout {
                Layout.fillWidth: true
                
                Text { 
                    text: "System Settings"
                    font.family: "JetBrains Mono"
                    font.weight: Font.Black
                    font.pixelSize: root.s(32)
                    color: root.text
                    Layout.alignment: Qt.AlignVCenter 
                }
                
                Item { Layout.fillWidth: true } 

                Rectangle {
                    Layout.preferredWidth: root.s(120)
                    Layout.preferredHeight: root.s(44)
                    radius: root.s(22)
                    color: mainSaveMa.containsMouse ? Qt.alpha(root.green, 0.9) : Qt.alpha(root.green, 0.7)
                    border.color: root.green
                    border.width: 1
                    scale: mainSaveMa.pressed ? 0.95 : (mainSaveMa.containsMouse ? 1.05 : 1.0)
                    
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: root.s(8)
                        Text { text: "󰆓"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.base }
                        Text { text: "APPLY"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14); color: root.base }
                    }
                    
                    MouseArea { 
                        id: mainSaveMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.saveAppSettings() 
                    }
                }

                // Add close button standalone
                Rectangle {
                    Layout.preferredWidth: root.s(44)
                    Layout.preferredHeight: root.s(44)
                    radius: root.s(22)
                    color: standaloneCloseMa.containsMouse ? Qt.alpha(root.red, 0.15) : "transparent"
                    border.color: standaloneCloseMa.containsMouse ? root.red : root.surface1
                    border.width: 1
                    scale: standaloneCloseMa.pressed ? 0.95 : (standaloneCloseMa.containsMouse ? 1.05 : 1.0)

                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text { anchors.centerIn: parent; text: "✖"; font.family: "JetBrains Mono"; font.pixelSize: root.s(14); color: standaloneCloseMa.containsMouse ? root.red : root.subtext0 }

                    MouseArea {
                        id: standaloneCloseMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: closeSequence.start()
                    }
                }
            }

            // --- SETTINGS LIST (VISUAL BOXES) ---
            
            // Setting Box 1: Startup & Topbar Icon
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: root.s(121)
                radius: root.s(8)
                color: Qt.alpha(root.surface0, 0.4)
                border.color: root.surface1
                border.width: 1
                
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)
                            
                            Item {
                                Layout.preferredWidth: settingsMainCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.peach }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Open guide at startup"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Automatically launch this configuration guide when logging in."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            
                            Item {
                                Layout.preferredWidth: settingsMainCol.controlColWidth
                                Layout.fillHeight: true
                                
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46)
                                    height: root.s(26)
                                    radius: root.s(13)
                                    color: root.setOpenGuideAtStartup ? root.peach : root.surface2
                                    
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    
                                    Rectangle {
                                        width: root.s(20)
                                        height: root.s(20)
                                        radius: root.s(10)
                                        color: root.base
                                        y: root.s(3)
                                        x: root.setOpenGuideAtStartup ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    
                                    MouseArea { 
                                        anchors.fill: parent
                                        onClicked: root.setOpenGuideAtStartup = !root.setOpenGuideAtStartup
                                        cursorShape: Qt.PointingHandCursor 
                                    }
                                }
                            }
                        }
                    }
                    
                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)
                            
                            Item {
                                Layout.preferredWidth: settingsMainCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰋖"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Show a help icon button on the very left of the topbar to toggle a guide popup"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            Item {
                                Layout.preferredWidth: settingsMainCol.controlColWidth
                                Layout.fillHeight: true
                                
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46)
                                    height: root.s(26)
                                    radius: root.s(13)
                                    color: root.setTopbarHelpIcon ? root.peach : root.surface2
                                    
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    
                                    Rectangle {
                                        width: root.s(20)
                                        height: root.s(20)
                                        radius: root.s(10)
                                        color: root.base
                                        y: root.s(3)
                                        x: root.setTopbarHelpIcon ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    
                                    MouseArea { 
                                        anchors.fill: parent
                                        onClicked: root.setTopbarHelpIcon = !root.setTopbarHelpIcon
                                        cursorShape: Qt.PointingHandCursor 
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Setting Box 2: UI Scale
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(60)
                radius: root.s(8)
                color: Qt.alpha(root.surface0, 0.4)
                border.color: root.surface1
                border.width: 1
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(15)
                    spacing: root.s(20)
                    
                    Item {
                        Layout.preferredWidth: settingsMainCol.iconColWidth
                        Layout.alignment: Qt.AlignVCenter
                        Text { anchors.centerIn: parent; text: "󰁦"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                    }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.s(4)
                        Text { text: "Global UI scale factor"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                        Text { text: "Adjust the base sizing scalar for all quickshell components."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    
                    Item {
                        Layout.preferredWidth: settingsMainCol.controlColWidth
                        Layout.fillHeight: true
                        
                        RowLayout {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.s(10)
                            
                            Rectangle {
                                width: root.s(30)
                                height: root.s(30)
                                radius: root.s(6)
                                color: sMinusMa.pressed ? root.surface2 : root.surface1
                                Text { anchors.centerIn: parent; text: "-"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                MouseArea { id: sMinusMa; anchors.fill: parent; onClicked: root.setUiScale = Math.max(0.5, (root.setUiScale - 0.1).toFixed(1)) }
                            }
                            
                            Text { 
                                text: root.setUiScale.toFixed(1) + "x"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Black
                                font.pixelSize: root.s(14)
                                color: root.text
                                Layout.minimumWidth: root.s(40)
                                horizontalAlignment: Text.AlignHCenter 
                            }
                            
                            Rectangle {
                                width: root.s(30)
                                height: root.s(30)
                                radius: root.s(6)
                                color: sPlusMa.pressed ? root.surface2 : root.surface1
                                Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                MouseArea { id: sPlusMa; anchors.fill: parent; onClicked: root.setUiScale = Math.min(2.0, (root.setUiScale + 0.1).toFixed(1)) }
                            }
                        }
                    }
                }
            }

            // Setting Box 3: Keyboard Language & Switcher
            Rectangle {
                z: 10
                Layout.fillWidth: true
                implicitHeight: kbCol.implicitHeight
                radius: root.s(8)
                color: Qt.alpha(root.surface0, 0.4)
                border.color: root.surface1
                border.width: 1
                
                ColumnLayout {
                    id: kbCol
                    anchors.fill: parent
                    spacing: 0
                    
                    // --- Part 1: Language ---
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: langBoxContent.implicitHeight + root.s(30)

                        RowLayout {
                            id: langBoxContent
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(15)
                            spacing: root.s(20)
                            
                            Item {
                                Layout.preferredWidth: settingsMainCol.iconColWidth
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: root.s(5)
                                Text { anchors.centerIn: parent; text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: root.s(4)
                                Text { text: "System keyboard layouts"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Active layouts matched directly to hyprland.conf. Click ✖ to remove."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: root.s(8)
                                    Layout.topMargin: root.s(5)
                                    
                                    Repeater {
                                        model: root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : []
                                        
                                        Rectangle {
                                            width: langChipLayout.implicitWidth + root.s(24)
                                            height: root.s(30)
                                            radius: root.s(15)
                                            color: root.surface1
                                            border.color: root.surface2
                                            border.width: 1
                                            
                                            RowLayout {
                                                id: langChipLayout
                                                anchors.centerIn: parent
                                                spacing: root.s(8)
                                                
                                                Text { 
                                                    text: modelData
                                                    font.family: "JetBrains Mono"
                                                    font.weight: Font.Bold
                                                    font.pixelSize: root.s(13)
                                                    color: root.text 
                                                }
                                                
                                                Text { 
                                                    text: "✖"
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: root.s(14)
                                                    color: chipMa.containsMouse ? root.red : root.subtext0
                                                    Behavior on color { ColorAnimation { duration: 150 } } 
                                                }
                                            }
                                            
                                            MouseArea {
                                                id: chipMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    let arr = root.setLanguage.split(",").filter(x => x.trim() !== "");
                                                    arr.splice(index, 1);
                                                    root.setLanguage = arr.join(",");
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Item {
                                Layout.preferredWidth: settingsMainCol.controlColWidth
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignTop
                                
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: root.s(5)
                                    width: parent.width
                                    height: root.s(32)
                                    radius: root.s(6)
                                    color: root.surface0
                                    border.color: langInput.activeFocus ? root.green : root.surface2
                                    border.width: 1
                                    
                                    TextInput {
                                        id: langInput
                                        anchors.fill: parent
                                        anchors.margins: root.s(8)
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: root.s(12)
                                        color: root.text
                                        clip: true
                                        selectByMouse: true
                                        onTextChanged: { root.updateLangSearch(text); }
                                        Text { text: "Search to add..."; color: root.subtext0; visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    
                                    Rectangle {
                                        width: parent.width
                                        height: Math.min(root.s(150), langSearchModel.count * root.s(30))
                                        y: parent.height + root.s(4)
                                        radius: root.s(6)
                                        color: root.surface0
                                        border.color: root.green
                                        border.width: 1
                                        visible: langInput.activeFocus && langSearchModel.count > 0 && langInput.text.trim() !== ""
                                        clip: true
                                        
                                        ListView {
                                            anchors.fill: parent
                                            model: langSearchModel
                                            interactive: true
                                            ScrollBar.vertical: ScrollBar { active: true; policy: ScrollBar.AsNeeded }
                                            delegate: Rectangle {
                                                width: parent.width
                                                height: root.s(30)
                                                color: sMa.containsMouse ? root.surface2 : "transparent"
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: root.s(10)
                                                    anchors.rightMargin: root.s(10)
                                                    spacing: root.s(8)
                                                    Text { text: model.code; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.text }
                                                    Text { text: model.name; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                                MouseArea {
                                                    id: sMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        let arr = root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : [];
                                                        if (!arr.includes(model.code)) {
                                                            arr.push(model.code);
                                                            root.setLanguage = arr.join(",");
                                                        }
                                                        langInput.text = "";
                                                        langInput.focus = false;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                    // --- Part 2: Layout Switcher ---
                    Item {
                        id: layoutSwitcherBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        property bool isDropdownOpen: false

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsMainCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(4)
                                Text { text: "Layout switcher shortcut"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Choose a key combination to switch between layouts."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsMainCol.controlColWidth
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignVCenter
                                
                                Rectangle {
                                    id: kbToggleSelector
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: root.s(32)
                                    radius: root.s(6)
                                    color: root.surface0
                                    border.color: layoutSwitcherBox.isDropdownOpen ? root.green : root.surface2
                                    border.width: 1
                                    
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: root.s(8)
                                        Text { 
                                            text: root.getKbToggleLabel(root.setKbOptions)
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(12)
                                            color: root.text
                                            Layout.fillWidth: true 
                                        }
                                        Text { 
                                            text: layoutSwitcherBox.isDropdownOpen ? "▴" : "▾"
                                            font.pixelSize: root.s(14)
                                            color: root.subtext0 
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: layoutSwitcherBox.isDropdownOpen = !layoutSwitcherBox.isDropdownOpen
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: root.kbToggleModelArr.length * root.s(30)
                                        y: parent.height + root.s(4)
                                        radius: root.s(6)
                                        color: root.surface0
                                        border.color: root.green
                                        border.width: 1
                                        visible: layoutSwitcherBox.isDropdownOpen
                                        clip: true

                                        ListView {
                                            anchors.fill: parent
                                            model: root.kbToggleModelArr
                                            interactive: false
                                            delegate: Rectangle {
                                                width: parent.width
                                                height: root.s(30)
                                                color: toggleMa.containsMouse ? root.surface2 : "transparent"
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: root.s(10)
                                                    anchors.rightMargin: root.s(10)
                                                    Text { 
                                                        text: modelData.label
                                                        font.family: "JetBrains Mono"
                                                        font.pixelSize: root.s(11)
                                                        color: root.setKbOptions === modelData.val ? root.green : root.text
                                                        Layout.fillWidth: true 
                                                    }
                                                }
                                                MouseArea {
                                                    id: toggleMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.setKbOptions = modelData.val;
                                                        layoutSwitcherBox.isDropdownOpen = false;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Setting Box 4: Wallpaper Directory
            Rectangle {
                z: 5 
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(60)
                radius: root.s(8)
                color: Qt.alpha(root.surface0, 0.4)
                border.color: wpDirInput.activeFocus ? root.mauve : root.surface1
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(15)
                    spacing: root.s(20)
                    
                    Item {
                        Layout.preferredWidth: settingsMainCol.iconColWidth
                        Layout.alignment: Qt.AlignVCenter
                        Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                    }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.s(4)
                        Text { text: "Wallpaper directory"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                        Text { text: "Set source path for the background engine. Use absolute paths."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    
                    Item {
                        Layout.preferredWidth: settingsMainCol.controlColWidth
                        Layout.fillHeight: true
                        
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: root.s(32)
                            radius: root.s(6)
                            color: root.surface0
                            border.color: root.surface2
                            border.width: 1
                            
                            TextInput {
                                id: wpDirInput
                                anchors.fill: parent
                                anchors.margins: root.s(8)
                                verticalAlignment: TextInput.AlignVCenter
                                text: root.setWallpaperDir
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(12)
                                color: root.text
                                clip: true
                                selectByMouse: true
                                onTextChanged: { 
                                    root.setWallpaperDir = text; 
                                    if (activeFocus) { 
                                        pathSuggestProc.query = text; 
                                        pathSuggestProc.running = false; 
                                        pathSuggestProc.running = true; 
                                    } 
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: pathSuggestModel.count * root.s(28)
                                y: parent.height + root.s(4)
                                radius: root.s(6)
                                color: root.surface0
                                border.color: root.mauve
                                border.width: 1
                                visible: pathSuggestModel.count > 0 && wpDirInput.activeFocus
                                clip: true
                                
                                ListView {
                                    anchors.fill: parent
                                    model: pathSuggestModel
                                    interactive: false
                                    delegate: Rectangle {
                                        width: parent.width
                                        height: root.s(28)
                                        color: suggestMa.containsMouse ? root.surface2 : "transparent"
                                        Text { 
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: root.s(8)
                                            text: model.path
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(11)
                                            color: root.text
                                            elide: Text.ElideMiddle
                                            width: parent.width - root.s(16) 
                                        }
                                        MouseArea {
                                            id: suggestMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { 
                                                wpDirInput.text = model.path; 
                                                pathSuggestModel.clear(); 
                                                wpDirInput.focus = false; 
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}

