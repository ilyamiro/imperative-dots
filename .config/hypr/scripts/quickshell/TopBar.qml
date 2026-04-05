import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray

PanelWindow {
    id: barWindow
    
    anchors {
        top: true
        left: true
        right: true
    }
    
    // --- Responsive Scaling Logic ---
    // Bases the scale on a 1920px width monitor. 
    // - Shrinks dynamically for very small screens (SVGA/XGA) down to 35%.
    // - Scales up progressively (non-linearly) for larger screens (2K/4K).
    // --- Responsive Scaling Logic ---
    property real baseScale: {
        if (width <= 0) return 1.0;
        let r = width / 1920.0; // Ratio relative to 1080p
        
        if (r <= 1.0) {
            // SCALING DOWN:
            // Using Math.pow(r, 0.85) makes the bar shrink "slower" than the screen does.
            // On a 1280px screen (r=0.66), a linear scale is 0.66, 
            // but this power scale keeps it at ~0.70.
            return Math.max(0.35, Math.pow(r, 0.85));
        } else {
            // SCALING UP:
            // Keeps the existing progressive scaling for 2K/4K so it doesn't get huge.
            return Math.pow(r, 0.6);
        }
    }
    
    // Helper function to dynamically scale any pixel value
    function s(val) { 
        return Math.round(val * barWindow.baseScale); 
    }

    property int barHeight: s(48)

    // THICKER BAR, MINIMAL MARGINS (Scaled)
    height: barHeight
    margins { top: s(8); bottom: 0; left: s(4); right: s(4) }
    
    // exclusiveZone = height + top margin
    exclusiveZone: barHeight + s(4)
    color: "transparent"

    // Dynamic Matugen Palette
    MatugenColors {
        id: mocha
    }

    // --- State Variables ---
    
    // Triggers layout animations immediately to feel fast
    property bool isStartupReady: false
    Timer { interval: 10; running: true; onTriggered: barWindow.isStartupReady = true }
    
    // Prevents repeaters (Workspaces/Tray) from flickering on data updates
    property bool startupCascadeFinished: false
    Timer { interval: 1000; running: true; onTriggered: barWindow.startupCascadeFinished = true }
    
    // Data gating to prevent startup layout jumping
    property bool sysPollerLoaded: false
    property bool fastPollerLoaded: false
    
    // FIXED: Only wait for the instant data to load the UI. 
    // The slow network scripts will populate smoothly when they finish.
    property bool isDataReady: fastPollerLoaded
    // Failsafe: Force the layout to show after 600ms even if fast poller hangs
    Timer { interval: 600; running: true; onTriggered: barWindow.isDataReady = true }
    
    property string timeStr: ""
    property string fullDateStr: ""
    property int typeInIndex: 0
    property string dateStr: fullDateStr.substring(0, typeInIndex)

    property string weatherIcon: ""
    property string weatherTemp: "--°"
    property string weatherHex: mocha.yellow
    
    property string wifiStatus: "Off"
    property string wifiIcon: "󰤮"
    property string wifiSsid: ""
    
    property string btStatus: "Off"
    property string btIcon: "󰂲"
    property string btDevice: ""
    
    property string volPercent: "0%"
    property string volIcon: "󰕾"
    property bool isMuted: false
    
    property string batPercent: "100%"
    property string batIcon: "󰁹"
    property string batStatus: "Unknown"
    
    property string kbLayout: "us"
    
    ListModel { id: workspacesModel }
    
    property var musicData: { "status": "Stopped", "title": "", "artUrl": "", "timeStr": "" }

    // Derived properties for UI logic
    property bool isMediaActive: barWindow.musicData.status !== "Stopped" && barWindow.musicData.title !== ""
    property bool isWifiOn: barWindow.wifiStatus.toLowerCase() === "enabled" || barWindow.wifiStatus.toLowerCase() === "on"
    property bool isBtOn: barWindow.btStatus.toLowerCase() === "enabled" || barWindow.btStatus.toLowerCase() === "on"
    
    property bool isSoundActive: !barWindow.isMuted && parseInt(barWindow.volPercent) > 0
    property int batCap: parseInt(barWindow.batPercent) || 0
    property bool isCharging: barWindow.batStatus === "Charging" || barWindow.batStatus === "Full"
    property color batDynamicColor: {
        if (isCharging) return mocha.green;
        if (batCap >= 70) return mocha.blue;
        if (batCap >= 30) return mocha.yellow;
        return mocha.red;
    }

    // ==========================================
    // DATA FETCHING 
    // ==========================================

    // Workspaces --------------------------------
    // 1. The continuous background daemon
    Process {
        id: wsDaemon
        command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/workspaces.sh"]
        running: true
    }

    // 2. The lightweight reader
    Process {
        id: wsReader
        command: ["bash", "-c", "cat /tmp/qs_workspaces.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    try { 
                        let newData = JSON.parse(txt);
                        if (workspacesModel.count !== newData.length) {
                            workspacesModel.clear();
                            for (let i = 0; i < newData.length; i++) {
                                workspacesModel.append({ "wsId": newData[i].id.toString(), "wsState": newData[i].state });
                            }
                        } else {
                            for (let i = 0; i < newData.length; i++) {
                                if (workspacesModel.get(i).wsState !== newData[i].state) {
                                    workspacesModel.setProperty(i, "wsState", newData[i].state);
                                }
                                if (workspacesModel.get(i).wsId !== newData[i].id.toString()) {
                                    workspacesModel.setProperty(i, "wsId", newData[i].id.toString());
                                }
                            }
                        }
                    } catch(e) {}
                }
            }
        }
    }

    // 3. Ultra-fast 50ms loop.
    Timer { 
        interval: 50 
        running: true 
        repeat: true 
        onTriggered: wsReader.running = true 
    }

    // Music -------------------------------------
    // 1. Fast cache reader to smoothly update the timestamp 
    Process {
        id: musicPoller
        command: ["bash", "-c", "cat /tmp/music_info.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    try { barWindow.musicData = JSON.parse(txt); } catch(e) {}
                }
            }
        }
    }

    // 2. Direct executor for zero-latency UI state changes (play/pause skips)
    Process {
        id: musicForceRefresh
        running: true
        command: ["bash", "-c", "bash ~/.config/hypr/scripts/quickshell/music/music_info.sh | tee /tmp/music_info.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    try { barWindow.musicData = JSON.parse(txt); } catch(e) {}
                }
            }
        }
    }

    // 3. Lightweight timer to update the progress clock without freezing
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: musicPoller.running = true
    }

    // Unified System Info ------------------------
    Process {
        id: sysPoller
        running: true
        command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/sys_info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    try {
                        let data = JSON.parse(txt);
                        
                        // Targeted Updates
                        if (barWindow.wifiStatus !== data.wifi.status) barWindow.wifiStatus = data.wifi.status;
                        if (barWindow.wifiIcon !== data.wifi.icon) barWindow.wifiIcon = data.wifi.icon;
                        if (barWindow.wifiSsid !== data.wifi.ssid) barWindow.wifiSsid = data.wifi.ssid;

                        if (barWindow.btStatus !== data.bt.status) barWindow.btStatus = data.bt.status;
                        if (barWindow.btIcon !== data.bt.icon) barWindow.btIcon = data.bt.icon;
                        if (barWindow.btDevice !== data.bt.connected) barWindow.btDevice = data.bt.connected;

                        let newVol = data.audio.volume.toString() + "%";
                        if (barWindow.volPercent !== newVol) barWindow.volPercent = newVol;
                        if (barWindow.volIcon !== data.audio.icon) barWindow.volIcon = data.audio.icon;
                        
                        let newMuted = (data.audio.is_muted === "true");
                        if (barWindow.isMuted !== newMuted) barWindow.isMuted = newMuted;

                        let newBat = data.battery.percent.toString() + "%";
                        if (barWindow.batPercent !== newBat) barWindow.batPercent = newBat;
                        if (barWindow.batIcon !== data.battery.icon) barWindow.batIcon = data.battery.icon;
                        if (barWindow.batStatus !== data.battery.status) barWindow.batStatus = data.battery.status;

                        if (barWindow.kbLayout !== data.keyboard.layout) barWindow.kbLayout = data.keyboard.layout;

                        barWindow.sysPollerLoaded = true;
                        barWindow.fastPollerLoaded = true;
                    } catch(e) {}
                }
                // When the system/music waiter finishes, instantly refresh the music state
                musicForceRefresh.running = true; 
                sysWaiter.running = true;
            }
        }
    }
    
    Process {
        id: sysWaiter
        command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/sys_waiter.sh"]
        // Strictly use onExited. Quickshell will no longer hook into stdout, preventing pipe deadlocks.
        onExited: sysPoller.running = true 
    }

    // Weather remains a slow poll since it fetches from web
    Process {
        id: weatherPoller
        command: ["bash", "-c", `
            echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-icon)"
            echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-temp)"
            echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-hex)"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 3) {
                    barWindow.weatherIcon = lines[0];
                    barWindow.weatherTemp = lines[1];
                    barWindow.weatherHex = lines[2] || mocha.yellow;
                }
            }
        }
    }
    Timer { interval: 150000; running: true; repeat: true; triggeredOnStart: true; onTriggered: weatherPoller.running = true }

    // Native Qt Time Formatting
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            let d = new Date();
            barWindow.timeStr = Qt.formatDateTime(d, "hh:mm:ss AP");
            barWindow.fullDateStr = Qt.formatDateTime(d, "dddd, MMMM dd");
            if (barWindow.typeInIndex >= barWindow.fullDateStr.length) {
                barWindow.typeInIndex = barWindow.fullDateStr.length;
            }
        }
    }

    // Typewriter effect timer for the date
    Timer {
        id: typewriterTimer
        interval: 40
        running: barWindow.isStartupReady && barWindow.typeInIndex < barWindow.fullDateStr.length
        repeat: true
        onTriggered: barWindow.typeInIndex += 1
    }

    // ==========================================
    // UI LAYOUT
    // ==========================================
    Item {
        anchors.fill: parent

        // ---------------- CENTER (MUST BE DECLARED FIRST OR Z-INDEXED FOR PROPER ANCHORING BORDERS) ----------------
        Rectangle {
            id: centerBox
            anchors.centerIn: parent
            property bool isHovered: centerMouse.containsMouse
            color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
            radius: barWindow.s(14); border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
            height: barWindow.barHeight
            
            width: centerLayout.implicitWidth + barWindow.s(36)
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
            
            // Staggered Center Transition
            property bool showLayout: false
            opacity: showLayout ? 1 : 0
            transform: Translate {
                y: centerBox.showLayout ? 0 : barWindow.s(-30)
                Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
            }

            Timer {
                running: barWindow.isStartupReady
                interval: 150
                onTriggered: centerBox.showLayout = true
            }

            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

            // Hover Scaling
            scale: isHovered ? 1.03 : 1.0
            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
            Behavior on color { ColorAnimation { duration: 250 } }
            
            MouseArea {
                id: centerMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle calendar"])
            }

            // Using RowLayout to perfectly align children to vertical center naturally
            RowLayout {
                id: centerLayout
                anchors.centerIn: parent
                spacing: barWindow.s(24)

                // Clockbox
                ColumnLayout {
                    spacing: -2
                    Text { text: barWindow.timeStr; Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(16); font.weight: Font.Black; color: mocha.blue }
                    Text { text: barWindow.dateStr; Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.subtext0 }
                }

                // Weatherbox
                RowLayout {
                    spacing: barWindow.s(8)
                    Text { 
                        text: barWindow.weatherIcon; 
                        Layout.alignment: Qt.AlignVCenter;
                        font.family: "Iosevka Nerd Font"; 
                        font.pixelSize: barWindow.s(24); 
                        color: Qt.tint(barWindow.weatherHex, Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.4)) 
                    }
                    Text { 
                        text: barWindow.weatherTemp; 
                        Layout.alignment: Qt.AlignVCenter;
                        font.family: "JetBrains Mono"; 
                        font.pixelSize: barWindow.s(17); 
                        font.weight: Font.Black; 
                        color: mocha.peach 
                    }
                }
            }
        }

        // ---------------- LEFT ----------------
        RowLayout {
            id: leftLayout
            anchors.left: parent.left
            anchors.right: centerBox.left  // Hard boundary to prevent overlaps
            anchors.rightMargin: barWindow.s(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: barWindow.s(4) 

            // Staggered Main Transition
            property bool showLayout: false
            opacity: showLayout ? 1 : 0
            transform: Translate {
                x: leftLayout.showLayout ? 0 : barWindow.s(-30)
                Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
            }
            
            Timer {
                running: barWindow.isStartupReady
                interval: 10
                onTriggered: leftLayout.showLayout = true
            }

            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

            property int moduleHeight: barWindow.barHeight

            // Search 
            Rectangle {
                property bool isHovered: searchMouse.containsMouse
                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: barWindow.s(14); border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                Layout.preferredHeight: parent.moduleHeight; Layout.preferredWidth: barWindow.barHeight
                
                scale: isHovered ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                Behavior on color { ColorAnimation { duration: 200 } }
                
                Text {
                    anchors.centerIn: parent
                    text: "󰍉"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(24)
                    color: parent.isHovered ? mocha.blue : mocha.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                MouseArea {
                    id: searchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/rofi_show.sh drun"])
                }
            }

            // Notifications
            Rectangle {
                property bool isHovered: notifMouse.containsMouse
                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: barWindow.s(14); border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                Layout.preferredHeight: parent.moduleHeight; Layout.preferredWidth: barWindow.barHeight
                
                scale: isHovered ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                Behavior on color { ColorAnimation { duration: 200 } }
                
                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(18)
                    color: parent.isHovered ? mocha.yellow : mocha.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                MouseArea {
                    id: notifMouse
                    anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) Quickshell.execDetached(["swaync-client", "-t", "-sw"]);
                        if (mouse.button === Qt.RightButton) Quickshell.execDetached(["swaync-client", "-d"]);
                    }
                }
            }

            // Workspaces 
            Rectangle {
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: barWindow.s(14); border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                Layout.preferredHeight: parent.moduleHeight
                clip: true
                
                property real targetWidth: workspacesModel.count > 0 ? wsLayout.width + barWindow.s(20) : 0
                Layout.preferredWidth: targetWidth
                visible: targetWidth > 0
                opacity: workspacesModel.count > 0 ? 1 : 0
                
                Behavior on opacity { NumberAnimation { duration: 300 } }

                // Using standard Row completely removes internal width sizing bugs
                Row {
                    id: wsLayout
                    anchors.centerIn: parent
                    spacing: barWindow.s(6)
                    
                    Repeater {
                        model: workspacesModel
                        delegate: Rectangle {
                            id: wsPill
                            property bool isHovered: wsPillMouse.containsMouse
                            
                            // Mapped dynamically from the ListModel
                            property string stateLabel: model.wsState
                            property string wsName: model.wsId
                            
                            property real targetWidth: barWindow.s(32)
                            width: targetWidth
                            Behavior on targetWidth { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            
                            height: barWindow.s(32); radius: barWindow.s(10)
                            
                            color: stateLabel === "active" 
                                    ? mocha.mauve 
                                    : (isHovered 
                                        ? Qt.rgba(mocha.overlay0.r, mocha.overlay0.g, mocha.overlay0.b, 0.9) 
                                        : (stateLabel === "occupied" 
                                            ? Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.9) 
                                            : "transparent"))

                            scale: isHovered && stateLabel !== "active" ? 1.08 : 1.0
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            
                            property bool initAnimTrigger: false
                            opacity: initAnimTrigger ? 1 : 0
                            transform: Translate {
                                y: wsPill.initAnimTrigger ? 0 : barWindow.s(15)
                                Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                            }

                            Component.onCompleted: {
                                if (!barWindow.startupCascadeFinished) {
                                    animTimer.interval = index * 60;
                                    animTimer.start();
                                } else {
                                    initAnimTrigger = true;
                                }
                            }

                            Timer {
                                id: animTimer
                                running: false
                                repeat: false
                                onTriggered: wsPill.initAnimTrigger = true
                            }
                            
                            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 250 } }

                            Text {
                                anchors.centerIn: parent
                                text: wsName
                                font.family: "JetBrains Mono"
                                font.pixelSize: barWindow.s(14)
                                font.weight: stateLabel === "active" ? Font.Black : (stateLabel === "occupied" ? Font.Bold : Font.Medium)
                                
                                color: stateLabel === "active" 
                                        ? mocha.crust 
                                        : (isHovered 
                                            ? mocha.crust 
                                            : (stateLabel === "occupied" ? mocha.text : mocha.overlay0))
                                        
                                Behavior on color { ColorAnimation { duration: 250 } }
                            }
                            MouseArea {
                                id: wsPillMouse
                                hoverEnabled: true
                                anchors.fill: parent
                                onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh " + wsName])
                            }
                        }
                    }
                }
            }            

            // Media Player 
            Rectangle {
                id: mediaBox
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: barWindow.s(14); border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                Layout.preferredHeight: parent.moduleHeight
                clip: true 
                
                property real targetWidth: barWindow.isMediaActive ? mediaLayoutContainer.width + barWindow.s(24) : 0
                Layout.maximumWidth: targetWidth
                Layout.preferredWidth: targetWidth
                
                visible: targetWidth > 0 || opacity > 0
                opacity: barWindow.isMediaActive ? 1.0 : 0.0

                Behavior on targetWidth { NumberAnimation { duration: 700; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 400 } }
                
                Item {
                    id: mediaLayoutContainer
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: barWindow.s(12)
                    height: parent.height
                    width: innerMediaLayout.width
                    
                    opacity: barWindow.isMediaActive ? 1.0 : 0.0
                    transform: Translate { 
                        x: barWindow.isMediaActive ? 0 : barWindow.s(-20) 
                        Behavior on x { NumberAnimation { duration: 700; easing.type: Easing.OutQuint } }
                    }
                    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                    Row {
                        id: innerMediaLayout
                        anchors.verticalCenter: parent.verticalCenter
                        // Dynamically reduce spacing between song info and controls on smaller screens
                        spacing: barWindow.width < 1920 ? barWindow.s(8) : barWindow.s(16)
                        
                        MouseArea {
                            id: mediaInfoMouse
                            width: infoLayout.width
                            height: innerMediaLayout.height
                            hoverEnabled: true
                            onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle music"])
                            
                            Row {
                                id: infoLayout
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: barWindow.s(10)
                                
                                scale: mediaInfoMouse.containsMouse ? 1.02 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                                Rectangle {
                                    width: barWindow.s(32); height: barWindow.s(32); radius: barWindow.s(8); color: mocha.surface1
                                    border.width: barWindow.musicData.status === "Playing" ? 1 : 0
                                    border.color: mocha.mauve
                                    clip: true
                                    Image { 
                                        anchors.fill: parent; 
                                        source: barWindow.musicData.artUrl || ""; 
                                        fillMode: Image.PreserveAspectCrop 
                                    }
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.2)
                                    }
                                }
                                Column {
                                    spacing: -2
                                    anchors.verticalCenter: parent.verticalCenter
                                    // Make column explicitly sized to enforce elide truncating on text
                                    property real maxColWidth: barWindow.width < 1920 ? barWindow.s(120) : barWindow.s(180)
                                    width: maxColWidth 
                                    
                                    Text { 
                                        text: barWindow.musicData.title; 
                                        font.family: "JetBrains Mono"; 
                                        font.weight: Font.Black; 
                                        font.pixelSize: barWindow.s(13); 
                                        color: mocha.text;
                                        width: parent.width
                                        elide: Text.ElideRight; 
                                    }
                                    Text { 
                                        text: barWindow.musicData.timeStr; 
                                        font.family: "JetBrains Mono"; 
                                        font.weight: Font.Black; 
                                        font.pixelSize: barWindow.s(10); 
                                        color: mocha.subtext0;
                                        width: parent.width
                                        elide: Text.ElideRight;
                                    }
                                }
                            }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: barWindow.width < 1920 ? barWindow.s(4) : barWindow.s(8)
                            Item { 
                                width: barWindow.s(24); height: barWindow.s(24); 
                                Text { 
                                    anchors.centerIn: parent; text: "󰒮"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26); 
                                    color: prevMouse.containsMouse ? mocha.text : mocha.overlay2; 
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    scale: prevMouse.containsMouse ? 1.1 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }
                                MouseArea { id: prevMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Quickshell.execDetached(["playerctl", "previous"]); musicForceRefresh.running = true; } } 
                            }
                            Item { 
                                width: barWindow.s(28); height: barWindow.s(28); 
                                Text { 
                                    anchors.centerIn: parent; text: barWindow.musicData.status === "Playing" ? "󰏤" : "󰐊"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(30); 
                                    color: playMouse.containsMouse ? mocha.green : mocha.text; 
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    scale: playMouse.containsMouse ? 1.15 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }
                                MouseArea { id: playMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Quickshell.execDetached(["playerctl", "play-pause"]); musicForceRefresh.running = true; } } 
                            }
                            Item { 
                                width: barWindow.s(24); height: barWindow.s(24); 
                                Text { 
                                    anchors.centerIn: parent; text: "󰒭"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26); 
                                    color: nextMouse.containsMouse ? mocha.text : mocha.overlay2; 
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    scale: nextMouse.containsMouse ? 1.1 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }
                                MouseArea { id: nextMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Quickshell.execDetached(["playerctl", "next"]); musicForceRefresh.running = true; } } 
                            }
                        }
                    }
                }
            }
            
            // DYNAMIC SPACER: Pushes everything tightly to the left side
            Item { Layout.fillWidth: true } 
        }

        // ---------------- RIGHT ----------------
        RowLayout {
            id: rightLayout
            anchors.right: parent.right
            anchors.left: centerBox.right // Hard boundary to prevent overlaps
            anchors.leftMargin: barWindow.s(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: barWindow.s(4)

            // Staggered Right Transition
            property bool showLayout: false
            opacity: showLayout ? 1 : 0
            transform: Translate {
                x: rightLayout.showLayout ? 0 : barWindow.s(30)
                Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
            }
            
            Timer {
                running: barWindow.isStartupReady && barWindow.isDataReady
                interval: 250
                onTriggered: rightLayout.showLayout = true
            }

            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

            // Dynamic Spacer to gently push the tray and system pills completely to the right edge
            Item { Layout.fillWidth: true } 

            // Dedicated System Tray Pill
            Rectangle {
                Layout.preferredHeight: barWindow.barHeight // THE FIX: Replaced basic "height"
                radius: barWindow.s(14)
                border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08)
                border.width: 1
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                
                property real targetWidth: trayRepeater.count > 0 ? trayLayout.width + barWindow.s(24) : 0
                Layout.preferredWidth: targetWidth
                Behavior on targetWidth { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                
                visible: targetWidth > 0
                opacity: targetWidth > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }

                Row {
                    id: trayLayout
                    anchors.centerIn: parent
                    spacing: barWindow.s(10)

                    Repeater {
                        id: trayRepeater
                        model: SystemTray.items
                        delegate: Image {
                            id: trayIcon
                            source: modelData.icon || ""
                            fillMode: Image.PreserveAspectFit
                            
                            sourceSize: Qt.size(barWindow.s(18), barWindow.s(18))
                            width: barWindow.s(18)
                            height: barWindow.s(18)
                            anchors.verticalCenter: parent.verticalCenter
                            
                            property bool isHovered: trayMouse.containsMouse
                            property bool initAnimTrigger: false
                            opacity: initAnimTrigger ? (isHovered ? 1.0 : 0.8) : 0.0
                            scale: initAnimTrigger ? (isHovered ? 1.15 : 1.0) : 0.0

                            Component.onCompleted: {
                                if (!barWindow.startupCascadeFinished) {
                                    trayAnimTimer.interval = index * 50;
                                    trayAnimTimer.start();
                                } else {
                                    initAnimTrigger = true;
                                }
                            }
                            Timer {
                                id: trayAnimTimer
                                running: false
                                repeat: false
                                onTriggered: trayIcon.initAnimTrigger = true
                            }

                            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                            QsMenuAnchor {
                                id: menuAnchor
                                anchor.window: barWindow
                                anchor.item: trayIcon
                                menu: modelData.menu
                            }

                            MouseArea {
                                id: trayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton) {
                                        modelData.activate();
                                    } else if (mouse.button === Qt.MiddleButton) {
                                        modelData.secondaryActivate();
                                    } else if (mouse.button === Qt.RightButton) {
                                        if (modelData.menu) {
                                            menuAnchor.open();
                                        } else if (typeof modelData.contextMenu === "function") {
                                            modelData.contextMenu(mouse.x, mouse.y);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // System Elements Pill
            Rectangle {
                Layout.preferredHeight: barWindow.barHeight // THE FIX: Replaced basic "height"
                radius: barWindow.s(14)
                border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08)
                border.width: 1
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                clip: true
                
                property real targetWidth: sysLayout.width + barWindow.s(20)
                Layout.preferredWidth: targetWidth
                Layout.maximumWidth: targetWidth

                Row {
                    id: sysLayout
                    anchors.centerIn: parent
                    spacing: barWindow.s(8) 

                    property int pillHeight: barWindow.s(34)

                    // KB
                    Rectangle {
                        property bool isHovered: kbMouse.containsMouse
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                        radius: barWindow.s(10); height: sysLayout.pillHeight;
                        clip: true
                        
                        property real targetWidth: kbLayoutRow.width + barWindow.s(24)
                        width: targetWidth
                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                        
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        property bool initAnimTrigger: false
                        Timer { running: rightLayout.showLayout && !parent.initAnimTrigger; interval: 0; onTriggered: parent.initAnimTrigger = true }
                        opacity: initAnimTrigger ? 1 : 0
                        transform: Translate { y: parent.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                        Row { 
                            id: kbLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: parent.parent.isHovered ? mocha.text : mocha.overlay2 }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.kbLayout; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; color: mocha.text }
                        }
                        MouseArea { id: kbMouse; anchors.fill: parent; hoverEnabled: true }
                    }

                    // WiFi 
                    Rectangle {
                        id: wifiPill
                        property bool isHovered: wifiMouse.containsMouse
                        radius: barWindow.s(10); height: sysLayout.pillHeight; 
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                        clip: true
                        
                        Rectangle {
                            anchors.fill: parent
                            radius: barWindow.s(10)
                            opacity: barWindow.isWifiOn ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: mocha.blue }
                                GradientStop { position: 1.0; color: Qt.lighter(mocha.blue, 1.3) }
                            }
                        }

                        property real targetWidth: wifiLayoutRow.width + barWindow.s(24)
                        width: targetWidth
                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                        
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        property bool initAnimTrigger: false
                        Timer { running: rightLayout.showLayout && !parent.initAnimTrigger; interval: 50; onTriggered: parent.initAnimTrigger = true }
                        opacity: initAnimTrigger ? 1 : 0
                        transform: Translate { y: parent.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                        Row { 
                            id: wifiLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                            Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.wifiIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: barWindow.isWifiOn ? mocha.base : mocha.subtext0 }
                            Text { 
                                id: wifiText
                                anchors.verticalCenter: parent.verticalCenter
                                text: barWindow.sysPollerLoaded ? (barWindow.isWifiOn ? (barWindow.wifiSsid !== "" ? barWindow.wifiSsid : "On") : "Off") : ""
                                visible: text !== ""
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; 
                                color: barWindow.isWifiOn ? mocha.base : mocha.text; 
                                width: Math.min(implicitWidth, barWindow.s(100)); elide: Text.ElideRight 
                            }
                        }
                        MouseArea { id: wifiMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle network wifi"]) }
                    }

                    // Bluetooth 
                    Rectangle {
                        id: btPill
                        property bool isHovered: btMouse.containsMouse
                        radius: barWindow.s(10); height: sysLayout.pillHeight
                        clip: true
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                        
                        Rectangle {
                            anchors.fill: parent
                            radius: barWindow.s(10)
                            opacity: barWindow.isBtOn ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: mocha.mauve }
                                GradientStop { position: 1.0; color: Qt.lighter(mocha.mauve, 1.3) }
                            }
                        }

                        property real targetWidth: btLayoutRow.width + barWindow.s(24)
                        width: targetWidth
                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        property bool initAnimTrigger: false
                        Timer { running: rightLayout.showLayout && !parent.initAnimTrigger; interval: 100; onTriggered: parent.initAnimTrigger = true }
                        opacity: initAnimTrigger ? 1 : 0
                        transform: Translate { y: parent.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                        Row { 
                            id: btLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                            Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.btIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: barWindow.isBtOn ? mocha.base : mocha.subtext0 }
                            Text { 
                                id: btText
                                anchors.verticalCenter: parent.verticalCenter
                                text: barWindow.sysPollerLoaded ? barWindow.btDevice : ""
                                visible: text !== ""; 
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; 
                                color: barWindow.isBtOn ? mocha.base : mocha.text; 
                                width: Math.min(implicitWidth, barWindow.s(100)); elide: Text.ElideRight 
                            }
                        }
                        MouseArea { id: btMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle network bt"]) }
                    }

                    // Volume
                    Rectangle {
                        property bool isHovered: volMouse.containsMouse
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                        radius: barWindow.s(10); height: sysLayout.pillHeight;
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            radius: barWindow.s(10)
                            opacity: barWindow.isSoundActive ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: mocha.peach }
                                GradientStop { position: 1.0; color: Qt.lighter(mocha.peach, 1.3) }
                            }
                        }
                        
                        property real targetWidth: volLayoutRow.width + barWindow.s(24)
                        width: targetWidth
                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                        
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        property bool initAnimTrigger: false
                        Timer { running: rightLayout.showLayout && !parent.initAnimTrigger; interval: 150; onTriggered: parent.initAnimTrigger = true }
                        opacity: initAnimTrigger ? 1 : 0
                        transform: Translate { y: parent.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                        Row { 
                            id: volLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                            Text { 
                                anchors.verticalCenter: parent.verticalCenter
                                text: barWindow.volIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); 
                                color: barWindow.isSoundActive ? mocha.base : mocha.subtext0 
                            }
                            Text { 
                                anchors.verticalCenter: parent.verticalCenter
                                text: barWindow.volPercent; 
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; 
                                color: barWindow.isSoundActive ? mocha.base : mocha.text; 
                            }
                        }
                        MouseArea { id: volMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle volume"]) }
                    }

                    // Battery
                    Rectangle {
                        property bool isHovered: batMouse.containsMouse
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4); 
                        radius: barWindow.s(10); height: sysLayout.pillHeight;
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            radius: barWindow.s(10)
                            opacity: (barWindow.isCharging || barWindow.batCap <= 20) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: barWindow.batDynamicColor; Behavior on color { ColorAnimation { duration: 300 } } }
                                GradientStop { position: 1.0; color: Qt.lighter(barWindow.batDynamicColor, 1.3); Behavior on color { ColorAnimation { duration: 300 } } }
                            }
                        }
                        
                        property real targetWidth: batLayoutRow.width + barWindow.s(24)
                        width: targetWidth
                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                        
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        property bool initAnimTrigger: false
                        Timer { running: rightLayout.showLayout && !parent.initAnimTrigger; interval: 200; onTriggered: parent.initAnimTrigger = true }
                        opacity: initAnimTrigger ? 1 : 0
                        transform: Translate { y: parent.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                        Row { 
                            id: batLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                            Text { 
                                anchors.verticalCenter: parent.verticalCenter
                                text: barWindow.batIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); 
                                color: (barWindow.isCharging || barWindow.batCap <= 20) ? mocha.base : barWindow.batDynamicColor
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            Text { 
                                anchors.verticalCenter: parent.verticalCenter
                                text: barWindow.batPercent; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; 
                                color: (barWindow.isCharging || barWindow.batCap <= 20) ? mocha.base : barWindow.batDynamicColor
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                        }
                        MouseArea { id: batMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle battery"]) }
                    }
                }
            }
        }
    }
}
