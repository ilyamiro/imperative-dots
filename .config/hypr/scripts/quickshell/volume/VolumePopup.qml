import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import QtCore
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        // Uses the physical screen width so the popup scales synchronously with the TopBar
        currentWidth: Screen.width
    }
    
    // Helper function scoped to the root Item for easy access in deeply nested elements and Canvases
    function s(val) { 
        return scaler.s(val); 
    }

    // -------------------------------------------------------------------------
    // SHORTCUTS & AUDIO
    // -------------------------------------------------------------------------
    Shortcut {
        sequence: "Tab"
        onActivated: {
            if (window.activeTab === "outputs") window.activeTab = "inputs";
            else if (window.activeTab === "inputs") window.activeTab = "apps";
            else window.activeTab = "outputs";
        }
    }
    // -------------------------------------------------------------------------
    // COLORS (Dynamic Matugen Palette)
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color red: _theme.red
    readonly property color maroon: _theme.maroon
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color green: _theme.green
    readonly property color teal: _theme.teal
    readonly property color sapphire: _theme.sapphire
    readonly property color blue: _theme.blue

    // -------------------------------------------------------------------------
    // STATE & CONFIG
    // -------------------------------------------------------------------------
    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/volume"
    
    property string activeTab: "outputs" // outputs, inputs, apps
    onActiveTabChanged: updateHeroData()

    readonly property color tabColor: {
        if (activeTab === "outputs") return window.blue;
        if (activeTab === "inputs") return window.mauve;
        return window.green;
    }
    
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: true
    }

    // Top Orb Active State Links
    property string activeId: ""
    property string activeName: "No Device"
    property string activeDesc: ""
    property int activeVol: 0
    property bool activeMute: false
    property string activeIcon: "󰓃"

    // Models
    ListModel { id: outputsModel }
    ListModel { id: inputsModel }
    ListModel { id: appsModel }

    property var draggingNodes: ({})
    property bool draggingMaster: false
    Timer { id: syncDelay; interval: 600; onTriggered: { window.draggingNodes = ({}); window.draggingMaster = false; } }

    // -------------------------------------------------------------------------
    // CACHING & DATA LOGIC
    // -------------------------------------------------------------------------
    Settings {
        id: cache
        property string lastAudioJson: ""
    }

    Component.onCompleted: {
        if (cache.lastAudioJson !== "") processAudioJson(cache.lastAudioJson);
    }

    function processAudioJson(textData) {
        if (!textData) return;
        try {
            let data = JSON.parse(textData);
            syncModel(outputsModel, data.outputs || []);
            syncModel(inputsModel, data.inputs || []);
            syncModel(appsModel, data.apps || []);
            updateHeroData();
        } catch(e) {}
    }

    function updateHeroData() {
        let targetModel = (window.activeTab === "inputs") ? inputsModel : outputsModel;
        
        let foundDefault = false;
        for (let i = 0; i < targetModel.count; i++) {
            let d = targetModel.get(i);
            if (d.is_default) {
                window.activeId = d.id;
                window.activeName = d.description;
                window.activeDesc = d.name;
                window.activeIcon = d.icon;
                if (!window.draggingMaster) {
                    window.activeVol = d.volume;
                    window.activeMute = d.mute;
                }
                foundDefault = true;
                break;
            }
        }
        
        // Fallback if no default is found
        if (!foundDefault && targetModel.count > 0) {
            let d = targetModel.get(0);
            window.activeId = d.id;
            window.activeName = d.description;
            window.activeDesc = d.name;
            window.activeIcon = d.icon;
            if (!window.draggingMaster) {
                window.activeVol = d.volume;
                window.activeMute = d.mute;
            }
        }
    }

    function syncModel(listModel, dataArray) {
        for (let i = listModel.count - 1; i >= 0; i--) {
            let id = listModel.get(i).id;
            let found = false;
            for (let j = 0; j < dataArray.length; j++) {
                if (id === dataArray[j].id) { found = true; break; }
            }
            if (!found) listModel.remove(i);
        }
        
        for (let i = 0; i < dataArray.length; i++) {
            let d = dataArray[i];
            let foundIdx = -1;
            for (let j = i; j < listModel.count; j++) {
                if (listModel.get(j).id === d.id) { foundIdx = j; break; }
            }
            
            let obj = {
                id: d.id, name: d.name, description: d.description,
                volume: d.volume, mute: d.mute, is_default: d.is_default, icon: d.icon
            };

            if (foundIdx === -1) {
                listModel.insert(i, obj);
            } else {
                if (foundIdx !== i) listModel.move(foundIdx, i, 1);
                for (let key in obj) { 
                    if (key === "volume" && window.draggingNodes[obj.id]) continue;
                    if (listModel.get(i)[key] !== obj[key]) {
                        listModel.setProperty(i, key, obj[key]); 
                    }
                }
            }
        }
    }

    Process {
        id: audioPoller
        command: ["python3", window.scriptsDir + "/get_audio_state.py"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cache.lastAudioJson = this.text.trim();
                processAudioJson(cache.lastAudioJson);
            }
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true;
        onTriggered: audioPoller.running = true
    }

    // -------------------------------------------------------------------------
    // ANIMATIONS
    // -------------------------------------------------------------------------
    property real introMain: 0
    property real introHeader: 0
    property real introContent: 0

    ParallelAnimation {
        running: true
        NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introHeader"; from: 0; to: 1.0; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 200 }
            NumberAnimation { target: window; property: "introContent"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        }
    }

    // -------------------------------------------------------------------------
    // UI LAYOUT
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        scale: 0.95 + (0.05 * introMain)
        opacity: introMain
        transform: Translate { y: window.s(20) * (1 - introMain) }

        Rectangle {
            anchors.fill: parent
            radius: window.s(20)
            color: window.base
            border.color: window.surface0
            border.width: 1
            clip: true

            // Rotating Background Blobs
            Rectangle {
                width: parent.width * 0.8; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(150)
                y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(100)
                opacity: 0.06
                color: window.tabColor
                Behavior on color { ColorAnimation { duration: 800 } }
            }
            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-150)
                y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-100)
                opacity: 0.04
                color: Qt.lighter(window.tabColor, 1.3)
                Behavior on color { ColorAnimation { duration: 800 } }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: window.s(25)
                spacing: window.s(20)

                // ==========================================
                // HERO ORB & MASTER SLIDER (TOP SECTION)
                // ==========================================
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(150)
                    opacity: introHeader
                    transform: Translate { y: window.s(30) * (1.0 - introHeader) }

                    RowLayout {
                        anchors.fill: parent
                        spacing: window.s(25)

                        // 1. The Orb
                        Item {
                            Layout.preferredWidth: window.s(130)
                            Layout.preferredHeight: window.s(130)
                            scale: masterOrbMa.pressed ? 0.95 : (masterOrbMa.containsMouse ? 1.05 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }

                            // Outermost border pulse ring
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + window.s(15)
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: window.activeMute ? window.red : window.tabColor
                                border.width: window.s(3)
                                z: -2

                                property real pulseOp: 0.0
                                property real pulseSc: 1.0
                                opacity: window.activeMute ? 0.0 : pulseOp
                                scale: pulseSc

                                Timer {
                                    interval: 45
                                    running: parent.opacity > 0.01 || !window.activeMute
                                    repeat: true
                                    onTriggered: {
                                        var time = Date.now() / 1000;
                                        parent.pulseOp = 0.3 + Math.sin(time * 2.5) * 0.15;
                                        parent.pulseSc = 1.02 + Math.cos(time * 3.0) * 0.02;
                                    }
                                }
                            }

                            // Solid pulsing background ring
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + window.s(40)
                                height: width
                                radius: width / 2
                                color: window.activeMute ? window.red : window.tabColor
                                opacity: window.activeMute ? 0.3 : 0.15
                                z: -1
                                Behavior on color { ColorAnimation { duration: 300 } }

                                SequentialAnimation on scale {
                                    loops: Animation.Infinite; running: true
                                    NumberAnimation { to: masterOrbMa.containsMouse ? 1.15 : 1.1; duration: masterOrbMa.containsMouse ? 800 : 2000; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: masterOrbMa.containsMouse ? 800 : 2000; easing.type: Easing.InOutSine }
                                }
                            }

                            // Core Shadow
                            MultiEffect {
                                source: centralCore
                                anchors.fill: centralCore
                                shadowEnabled: true
                                shadowColor: "#000000"
                                shadowOpacity: 0.5
                                shadowBlur: 1.2
                                shadowVerticalOffset: window.s(6)
                                z: -1
                            }

                            // Core Rectangle
                            Rectangle {
                                id: centralCore
                                anchors.fill: parent
                                radius: width / 2
                                color: window.base
                                border.color: window.activeMute ? window.red : Qt.lighter(window.tabColor, 1.1)
                                border.width: 2
                                clip: true
                                Behavior on border.color { ColorAnimation { duration: 300 } }

                                // Volume Wave Fill
                                Canvas {
                                    id: orbWave
                                    anchors.fill: parent
                                    
                                    property real wavePhase: 0.0
                                    NumberAnimation on wavePhase {
                                        running: window.activeVol > 0 && window.activeVol < 100
                                        loops: Animation.Infinite
                                        from: 0; to: Math.PI * 2; duration: 1200
                                    }
                                    onWavePhaseChanged: requestPaint()

                                    Connections {
                                        target: window
                                        function onActiveVolChanged() { orbWave.requestPaint() }
                                        function onActiveMuteChanged() { orbWave.requestPaint() }
                                        function onTabColorChanged() { orbWave.requestPaint() }
                                    }

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        if (window.activeVol <= 0) return;

                                        var fillRatio = window.activeVol / 100.0;
                                        var r = width / 2;
                                        var fillY = height * (1.0 - fillRatio);

                                        ctx.save();
                                        
                                        // 1. Establish the circular clipping mask
                                        ctx.beginPath();
                                        ctx.arc(r, r, r, 0, 2 * Math.PI);
                                        ctx.clip();
                                        
                                        // 2. Draw the actual wave filling
                                        ctx.beginPath();
                                        ctx.moveTo(0, fillY);
                                        
                                        if (fillRatio < 0.99) {
                                            var waveAmp = window.s(8) * Math.sin(fillRatio * Math.PI); 
                                            var cp1y = fillY + Math.sin(wavePhase) * waveAmp;
                                            var cp2y = fillY + Math.cos(wavePhase + Math.PI) * waveAmp;
                                            ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
                                            ctx.lineTo(width, height);
                                            ctx.lineTo(0, height);
                                        } else {
                                            ctx.lineTo(width, 0);
                                            ctx.lineTo(width, height);
                                            ctx.lineTo(0, height);
                                        }
                                        ctx.closePath();
                                        
                                        // Vibrant gradient matching the network orb
                                        var grad = ctx.createLinearGradient(0, 0, 0, height);
                                        if (window.activeMute) {
                                            grad.addColorStop(0, Qt.lighter(window.red, 1.15).toString());
                                            grad.addColorStop(1, window.red.toString());
                                        } else {
                                            grad.addColorStop(0, Qt.lighter(window.tabColor, 1.15).toString());
                                            grad.addColorStop(1, window.tabColor.toString());
                                        }
                                        ctx.fillStyle = grad;
                                        ctx.globalAlpha = 1.0;
                                        ctx.fill();
                                        ctx.restore();
                                    }
                                }

                                // Dual-Layer Text for contrast clipping
                                // 1. Base Text (Visible when empty)
                                Text {
                                    anchors.centerIn: parent
                                    font.family: "JetBrains Mono"
                                    font.weight: Font.Black
                                    font.pixelSize: window.s(32)
                                    color: window.activeMute ? window.red : window.text
                                    text: window.activeMute ? "MUTE" : window.activeVol + "%"
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                // 2. Clipped Text (Dark text that reveals over the wave fill dynamically)
                                Item {
                                    id: waveClipItem
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right

                                    // Calculate the exact wave offset at the center of the orb using the Bezier formula
                                    property real fillRatio: window.activeVol / 100.0
                                    property real waveAmp: fillRatio < 0.99 ? window.s(8) * Math.sin(fillRatio * Math.PI) : 0
                                    property real waveCenterOffset: 0.375 * waveAmp * (Math.sin(orbWave.wavePhase) - Math.cos(orbWave.wavePhase))
                                    property real baseClipHeight: parent.height * fillRatio

                                    height: Math.min(parent.height, Math.max(0, baseClipHeight - waveCenterOffset))
                                    clip: true
                                    visible: window.activeVol > 0

                                    Text {
                                        x: waveClipItem.width / 2 - width / 2
                                        y: (centralCore.height / 2) - (height / 2) - (centralCore.height - waveClipItem.height)
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Black
                                        font.pixelSize: window.s(32)
                                        color: window.crust
                                        text: window.activeMute ? "MUTE" : window.activeVol + "%"
                                    }
                                }
                            }

                            MouseArea {
                                id: masterOrbMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    let type = window.activeTab === "inputs" ? "source" : "sink";
                                    Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "toggle-mute", type, window.activeId]);
                                    audioPoller.running = true;
                                }
                            }
                        }

                        // 2. Details & Slider
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: window.s(10)

                            ColumnLayout {
                                spacing: window.s(2)
                                Text {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(20)
                                    color: window.text
                                    text: window.activeName
                                }
                                Text {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                                    color: window.subtext0
                                    text: window.activeTab === "apps" ? "Master Output Volume" : window.activeDesc
                                }
                            }

                            Item { Layout.fillHeight: true } // spacer

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: window.s(15)

                                // Slider
                                Item {
                                    Layout.fillWidth: true
                                    height: window.s(24)

                                    Timer {
                                        id: masterCmdThrottle
                                        interval: 50
                                        property int targetPct: -1
                                        onTriggered: {
                                            if (targetPct >= 0) {
                                                let type = window.activeTab === "inputs" ? "source" : "sink";
                                                if (targetPct > 0 && window.activeMute) {
                                                    Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "toggle-mute", type, window.activeId]);
                                                }
                                                Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "set-volume", type, window.activeId, targetPct]);
                                                targetPct = -1;
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent; radius: window.s(12)
                                        color: "#0dffffff"; border.color: "#1affffff"; border.width: 1
                                        clip: true

                                        Rectangle {
                                            height: parent.height
                                            width: parent.width * (Math.min(100, window.activeVol) / 100)
                                            radius: window.s(12)
                                            opacity: window.activeMute ? 0.3 : (masterSliderMa.containsMouse ? 1.0 : 0.85)
                                            Behavior on opacity { NumberAnimation { duration: 200 } }
                                            Behavior on width { enabled: !window.draggingMaster; NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: window.activeMute ? window.surface2 : window.tabColor; Behavior on color { ColorAnimation{duration: 300} } }
                                                GradientStop { position: 1.0; color: window.activeMute ? Qt.lighter(window.surface2, 1.15) : Qt.lighter(window.tabColor, 1.25); Behavior on color { ColorAnimation{duration: 300} } }
                                            }
                                        }
                                    }
                                    
                                    MouseArea {
                                        id: masterSliderMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onPressed: (mouse) => { syncDelay.stop(); window.draggingMaster = true; updateVol(mouse.x); }
                                        onPositionChanged: (mouse) => { if (pressed) updateVol(mouse.x); }
                                        onReleased: { syncDelay.restart(); audioPoller.running = true; }
                                        
                                        function updateVol(mx) {
                                            let pct = Math.max(0, Math.min(100, Math.round((mx / width) * 100)));
                                            window.activeVol = pct; // Instant visual feedback on orb

                                            masterCmdThrottle.targetPct = pct;
                                            if (!masterCmdThrottle.running) masterCmdThrottle.start();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ==========================================
                // TABS
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(54)
                    radius: window.s(14)
                    color: "#0dffffff" 
                    border.color: "#1affffff"
                    border.width: 1
                    opacity: introHeader
                    transform: Translate { y: window.s(20) * (1.0 - introHeader) }

                    Rectangle {
                        width: (parent.width - window.s(2)) / 3 
                        height: parent.height - window.s(2)
                        y: window.s(1)
                        radius: window.s(10)
                        x: {
                            if (window.activeTab === "outputs") return window.s(1);
                            if (window.activeTab === "inputs") return width + window.s(1);
                            return (width * 2) + window.s(1);
                        }
                        Behavior on x { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                        
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: window.tabColor; Behavior on color { ColorAnimation { duration: 400 } } }
                            GradientStop { position: 1.0; color: Qt.lighter(window.tabColor, 1.15); Behavior on color { ColorAnimation { duration: 400 } } }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0
                        
                        Repeater {
                            model: ListModel {
                                ListElement { tabId: "outputs"; icon: "󰓃"; label: "Outputs" } 
                                ListElement { tabId: "inputs"; icon: "󰍬"; label: "Inputs" }   
                                ListElement { tabId: "apps"; icon: "󰎆"; label: "Streams" } 
                            }
                            
                            delegate: Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: window.s(8)
                                    Text {
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                        color: window.activeTab === tabId ? window.crust : (tabMa.containsMouse ? window.text : window.subtext0)
                                        text: icon
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    Text {
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(13)
                                        color: window.activeTab === tabId ? window.crust : (tabMa.containsMouse ? window.text : window.subtext0)
                                        text: label
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                }
                                
                                MouseArea {
                                    id: tabMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        window.activeTab = tabId;
                                    }
                                }
                            }
                        }
                    }
                }

                // ==========================================
                // LIST VIEW CONTENT
                // ==========================================
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    opacity: introContent
                    transform: Translate { y: window.s(20) * (1.0 - introContent) }

                    ListView {
                        id: contentList
                        anchors.fill: parent
                        spacing: window.s(12)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        // Elegant sliding transitions when models rearrange
                        add: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutQuint }
                            NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: 400; easing.type: Easing.OutBack }
                        }
                        displaced: Transition {
                            SpringAnimation { property: "y"; spring: 3; damping: 0.2; mass: 0.2 }
                        }

                        model: {
                            if (window.activeTab === "outputs") return outputsModel;
                            if (window.activeTab === "inputs") return inputsModel;
                            return appsModel;
                        }

                        Item {
                            width: contentList.width; height: contentList.height
                            visible: contentList.count === 0
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: window.s(10)
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(32); color: window.surface2; text: "󰖁" }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.pixelSize: window.s(14); color: window.overlay0; text: "No active streams" }
                            }
                        }

                        delegate: Rectangle {
                            id: delegateRoot
                            width: contentList.width
                            
                            // Staggered Intro Animation Timer
                            property bool isLoaded: false
                            Timer {
                                running: true
                                interval: 40 + (index * 40)
                                onTriggered: delegateRoot.isLoaded = true
                            }

                            // Intro transforms
                            opacity: isLoaded ? 1.0 : 0.0
                            transform: Translate { y: isLoaded ? 0 : window.s(15) }
                            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                            Behavior on transform { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                            // Dynamic Height: The active hero element collapses its bottom slider row
                            property bool isActiveNode: model.is_default && window.activeTab !== "apps"
                            height: isActiveNode ? window.s(60) : window.s(100)
                            Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                            radius: window.s(14)
                            
                            property bool isHovered: cardMa.containsMouse && !isActiveNode

                            color: isActiveNode ? window.tabColor : (isHovered ? "#0affffff" : "#05ffffff")
                            border.color: isActiveNode ? window.tabColor : "#1affffff"
                            border.width: isActiveNode ? 2 : 1
                            Behavior on border.color { ColorAnimation { duration: 300 } }
                            Behavior on color { ColorAnimation { duration: 300 } }

                            // Full card selection listener
                            MouseArea {
                                id: cardMa
                                anchors.fill: parent
                                hoverEnabled: window.activeTab !== "apps"
                                cursorShape: window.activeTab !== "apps" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (window.activeTab !== "apps" && !model.is_default) {
                                        let type = window.activeTab === "outputs" ? "sink" : "source";
                                        Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "set-default", type, model.name]);
                                        audioPoller.running = true;
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: window.s(16)
                                anchors.rightMargin: window.s(16)
                                anchors.topMargin: window.s(12)
                                anchors.bottomMargin: isActiveNode ? window.s(12) : window.s(16) // Prevent slider crowding bottom bounds
                                spacing: window.s(12)

                                // Top row: Text info and Icon
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: window.s(12)

                                    Text {
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(22)
                                        color: isActiveNode ? window.crust : window.text
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        text: {
                                            if (window.activeTab === "inputs") return "󰍬";
                                            if (window.activeTab === "apps") return "󰎆";
                                            if (model.description.toLowerCase().indexOf("headset") !== -1 || model.description.toLowerCase().indexOf("headphones") !== -1) return "󰋎";
                                            return "󰓃";
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: window.s(2)
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(14)
                                            color: isActiveNode ? window.crust : window.text
                                            text: model.description
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                                            color: isActiveNode ? Qt.darker(window.crust, 1.5) : window.subtext0
                                            text: isActiveNode ? "Active Default" : model.name
                                        }
                                    }
                                }

                                // Bottom row: Custom Slider & Mute (Hides if it's the active node)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: window.s(15)
                                    visible: !isActiveNode
                                    opacity: isActiveNode ? 0.0 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    Rectangle {
                                        Layout.preferredWidth: window.s(32); Layout.preferredHeight: window.s(32); radius: window.s(16)
                                        color: muteMa.containsMouse ? "#1affffff" : "transparent"
                                        border.color: muteMa.containsMouse ? (model.mute ? window.overlay0 : window.tabColor) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                            color: model.mute ? window.overlay0 : window.subtext0
                                            text: model.mute || model.volume === 0 ? "󰖁" : (model.volume > 50 ? "󰕾" : "󰖀")
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                        MouseArea {
                                            id: muteMa
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                let type = "sink";
                                                if (window.activeTab === "inputs") type = "source";
                                                if (window.activeTab === "apps") type = "sink-input";
                                                Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "toggle-mute", type, model.id]);
                                                audioPoller.running = true;
                                            }
                                        }
                                    }

                                    // Local Slider
                                    Item {
                                        Layout.fillWidth: true
                                        height: window.s(14) // Slightly thinner than master slider for hierarchy
                                        
                                        Timer {
                                            id: volCmdThrottle
                                            interval: 50
                                            property int targetPct: -1
                                            onTriggered: {
                                                if (targetPct >= 0) {
                                                    let type = "sink";
                                                    if (window.activeTab === "inputs") type = "source";
                                                    if (window.activeTab === "apps") type = "sink-input";
                                                    
                                                    if (targetPct > 0 && model.mute) {
                                                        Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "toggle-mute", type, model.id]);
                                                    }
                                                    Quickshell.execDetached(["bash", window.scriptsDir + "/audio_control.sh", "set-volume", type, model.id, targetPct]);
                                                    targetPct = -1;
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent; radius: window.s(7)
                                            color: "#0dffffff"; border.color: "#1affffff"; border.width: 1
                                            clip: true

                                            Rectangle {
                                                height: parent.height
                                                width: parent.width * (Math.min(100, model.volume) / 100)
                                                radius: window.s(7)
                                                
                                                // Heavily dimmed if muted, slightly dimmed if background node
                                                opacity: model.mute ? 0.3 : (volSliderMa.containsMouse ? 0.7 : 0.4)
                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                                Behavior on width { enabled: !window.draggingNodes[model.id]; NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0.0; color: model.mute ? window.surface2 : window.tabColor; Behavior on color { ColorAnimation { duration: 300 } } }
                                                    GradientStop { position: 1.0; color: model.mute ? Qt.lighter(window.surface2, 1.15) : Qt.lighter(window.tabColor, 1.25); Behavior on color { ColorAnimation { duration: 300 } } }
                                                }
                                            }
                                        }
                                        
                                        MouseArea {
                                            id: volSliderMa
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onPressed: (mouse) => { syncDelay.stop(); window.draggingNodes[model.id] = true; updateVol(mouse.x); }
                                            onPositionChanged: (mouse) => { if (pressed) updateVol(mouse.x); }
                                            onReleased: { syncDelay.restart(); audioPoller.running = true; }
                                            
                                            function updateVol(mx) {
                                                let pct = Math.max(0, Math.min(100, Math.round((mx / width) * 100)));
                                                
                                                let targetList = window.activeTab === "outputs" ? outputsModel : (window.activeTab === "inputs" ? inputsModel : appsModel);
                                                for (let i = 0; i < targetList.count; i++) {
                                                    if (targetList.get(i).id === model.id) {
                                                        targetList.setProperty(i, "volume", pct);
                                                        break;
                                                    }
                                                }

                                                volCmdThrottle.targetPct = pct;
                                                if (!volCmdThrottle.running) volCmdThrottle.start();
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.preferredWidth: window.s(35)
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12)
                                        color: window.subtext0
                                        text: model.volume + "%"
                                        horizontalAlignment: Text.AlignRight
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
