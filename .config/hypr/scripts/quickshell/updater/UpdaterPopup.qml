import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
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
    // COLORS (Dynamic Matugen Palette)
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    
    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color green: _theme.green

    // -------------------------------------------------------------------------
    // STATE & POLLING
    // -------------------------------------------------------------------------
    property string localVersion: "..."
    property string remoteVersion: "..."
    
    // Typing animation properties
    property string fullCommitMessage: ""
    property string displayedCommitMessage: "Fetching changelog..."
    property int typeIndex: 0

    Keys.onEscapePressed: {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }

    Process {
        command: ["bash", "-c", "source ~/.local/state/imperative-dots-version 2>/dev/null && [ -n \"$LOCAL_VERSION\" ] && echo $LOCAL_VERSION || echo '0.0.0'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out !== "") window.localVersion = out;
            }
        }
    }

    Process {
        command: ["bash", "-c", "curl -m 5 -s https://raw.githubusercontent.com/ilyamiro/imperative-dots/master/install.sh | grep '^DOTS_VERSION=' | cut -d'\"' -f2"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out !== "") window.remoteVersion = out;
            }
        }
    }

    Process {
        command: ["bash", "-c", "curl -m 5 -sL \"https://api.github.com/repos/ilyamiro/imperative-dots/commits/master\" | grep -m1 '\"message\":' | cut -d'\"' -f4 || echo 'No changelog available'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out !== "") {
                    window.fullCommitMessage = out;
                    window.displayedCommitMessage = "";
                    window.typeIndex = 0;
                    commitTypeTimer.start(); // Starts immediately as it was before
                } else {
                    window.displayedCommitMessage = "No changelog available.";
                }
            }
        }
    }

    Timer {
        id: commitTypeTimer
        interval: 12
        repeat: true
        onTriggered: {
            if (window.typeIndex < window.fullCommitMessage.length) {
                window.displayedCommitMessage += window.fullCommitMessage.charAt(window.typeIndex);
                window.typeIndex++;
            } else {
                stop();
            }
        }
    }

    // -------------------------------------------------------------------------
    // UI LAYOUT
    // -------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        radius: window.s(16)
        color: window.base
        border.color: window.surface1
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: window.s(25)
            spacing: window.s(20)

            // --- HEADER ---
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                color: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.1)
                border.color: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.2)
                border.width: 1
                radius: window.s(8)
                Layout.preferredWidth: headerTxt.implicitWidth + window.s(24)
                Layout.preferredHeight: headerTxt.implicitHeight + window.s(12)

                Text {
                    id: headerTxt
                    anchors.centerIn: parent
                    text: "NEW UPDATE AVAILABLE"
                    font.family: "JetBrains Mono"
                    font.weight: Font.Bold
                    font.pixelSize: window.s(11)
                    color: window.green
                    opacity: 0.8
                }
            }

            // --- ANIMATED CHOREOGRAPHED VERSIONS ---
            Item {
                id: versionContainer
                Layout.fillWidth: true
                Layout.preferredHeight: window.s(45)

                readonly property real finalNewX: (width - newVer.implicitWidth) / 2
                readonly property real finalArrowX: finalNewX - arrowIcon.implicitWidth - window.s(20)
                readonly property real finalOldX: finalArrowX - oldVer.implicitWidth - window.s(20)
                readonly property real initialOldX: (width - oldVer.implicitWidth) / 2

                Text { 
                    id: oldVer
                    text: window.localVersion
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(16)
                    color: window.subtext0 
                    anchors.verticalCenter: parent.verticalCenter
                    x: versionContainer.initialOldX 
                }
                
                Text { 
                    id: arrowIcon
                    text: ""
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: window.s(16)
                    color: window.surface2 
                    anchors.verticalCenter: parent.verticalCenter
                    x: versionContainer.finalOldX + oldVer.implicitWidth 
                    opacity: 0
                }
                
                Text { 
                    id: newVer
                    text: window.remoteVersion
                    font.family: "JetBrains Mono"
                    font.weight: Font.Black
                    font.pixelSize: window.s(36) 
                    color: window.green 
                    anchors.verticalCenter: parent.verticalCenter
                    x: versionContainer.finalNewX 
                    opacity: 0
                    scale: 0.9 // Less punchy scale start
                }

                MultiEffect {
                    id: newVerEffect
                    source: newVer
                    anchors.fill: newVer
                    shadowEnabled: true
                    shadowColor: window.green
                    shadowBlur: 0.0
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    opacity: newVer.opacity
                }

                SequentialAnimation {
                    id: versionAnim

                    PauseAnimation { duration: 150 }

                    // 1. Smoother, less punchy slide
                    ParallelAnimation {
                        NumberAnimation { 
                            target: oldVer; property: "x"; 
                            to: versionContainer.finalOldX
                            duration: 500; easing.type: Qt.InOutCubic 
                        }
                        NumberAnimation {
                            target: oldVer; property: "opacity";
                            to: 0.2
                            duration: 500; easing.type: Qt.InOutCubic
                        }
                    }

                    // 2. Arrow fade
                    ParallelAnimation {
                        NumberAnimation { target: arrowIcon; property: "opacity"; to: 1; duration: 300 }
                        NumberAnimation { 
                            target: arrowIcon; property: "x"; 
                            to: versionContainer.finalArrowX
                            duration: 400; easing.type: Qt.OutCubic 
                        }
                    }

                    // 3. New version fade-in
                    ParallelAnimation {
                        NumberAnimation { target: newVer; property: "opacity"; to: 1; duration: 400 }
                        NumberAnimation { target: newVer; property: "scale"; to: 1.0; duration: 500; easing.type: Qt.OutCubic }
                        ScriptAction { script: glowAnim.start() }
                    }
                }

                SequentialAnimation {
                    id: glowAnim
                    loops: Animation.Infinite
                    NumberAnimation { target: newVerEffect; property: "shadowBlur"; to: 0.8; duration: 1500; easing.type: Easing.InOutSine }
                    NumberAnimation { target: newVerEffect; property: "shadowBlur"; to: 0.2; duration: 1500; easing.type: Easing.InOutSine }
                }

                Connections {
                    target: window
                    function onRemoteVersionChanged() {
                        if (window.remoteVersion !== "..." && window.remoteVersion !== "") {
                            versionAnim.start();
                        }
                    }
                }
            }

            // --- OUTLINED COMMIT BOX ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent" // Outlined only
                border.color: Qt.rgba(window.surface2.r, window.surface2.g, window.surface2.b, 0.4)
                border.width: 1
                radius: window.s(12)
                clip: true

                ScrollView {
                    id: changelogScroll
                    anchors.fill: parent
                    anchors.margins: window.s(15)
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1.5); color: window.surface2; opacity: 0.5 }
                    }
                    
                    Text {
                        width: changelogScroll.availableWidth
                        text: window.displayedCommitMessage
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(13)
                        color: window.text
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignTop
                        lineHeight: 1.4
                    }
                }
            }

            // --- HOLD TO UPDATE BUTTON ---
            Rectangle {
                id: updateBtn
                Layout.fillWidth: true
                Layout.preferredHeight: window.s(54)
                radius: window.s(12)
                color: window.surface0
                border.color: btnMa.containsMouse ? window.green : window.surface2
                border.width: btnMa.containsMouse ? window.s(2) : 1
                clip: true
                
                scale: btnMa.pressed ? 0.98 : (btnMa.containsMouse ? 1.01 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                property real fillLevel: 0.0
                property bool triggered: false

                Canvas {
                    id: waveCanvas
                    anchors.fill: parent
                    
                    property real wavePhase: 0.0
                    NumberAnimation on wavePhase {
                        running: updateBtn.fillLevel > 0.0 && updateBtn.fillLevel < 1.0
                        loops: Animation.Infinite
                        from: 0; to: Math.PI * 2
                        duration: 1000
                    }
                    
                    onWavePhaseChanged: requestPaint()
                    Connections { target: updateBtn; function onFillLevelChanged() { waveCanvas.requestPaint() } }
                    
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        if (updateBtn.fillLevel <= 0.001) return;

                        var currentW = width * updateBtn.fillLevel;
                        var r = window.s(12);

                        ctx.save();
                        ctx.beginPath();
                        ctx.moveTo(0, 0);
                        
                        if (updateBtn.fillLevel < 0.99) {
                            var waveAmp = window.s(8) * Math.sin(updateBtn.fillLevel * Math.PI); 
                            var cp1x = currentW + Math.sin(wavePhase) * waveAmp;
                            var cp2x = currentW + Math.cos(wavePhase + Math.PI) * waveAmp;

                            ctx.lineTo(currentW, 0);
                            ctx.bezierCurveTo(cp2x, height * 0.33, cp1x, height * 0.66, currentW, height);
                            ctx.lineTo(0, height);
                        } else {
                            ctx.lineTo(width, 0);
                            ctx.lineTo(width, height);
                            ctx.lineTo(0, height);
                        }
                        ctx.closePath();
                        ctx.clip(); 

                        ctx.beginPath();
                        ctx.roundedRect(0, 0, width, height, r, r);
                        var grad = ctx.createLinearGradient(0, 0, width, 0);
                        grad.addColorStop(0, Qt.darker(window.green, 1.1).toString());
                        grad.addColorStop(1, window.green.toString());
                        ctx.fillStyle = grad;
                        ctx.fill();

                        ctx.restore();
                    }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: window.s(10)
                    
                    Text { 
                        text: "󰚰"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: window.s(18)
                        color: updateBtn.fillLevel > 0.5 ? window.crust : window.green 
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    
                    Text { 
                        text: updateBtn.fillLevel > 0 ? "HOLDING..." : "UPDATE"
                        font.family: "JetBrains Mono"
                        font.weight: Font.Black
                        font.pixelSize: window.s(14)
                        color: updateBtn.fillLevel > 0.5 ? window.crust : window.green 
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                MouseArea {
                    id: btnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: updateBtn.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor
                    
                    onPressed: {
                        if (!updateBtn.triggered) {
                            drainAnim.stop();
                            fillAnim.start();
                        }
                    }
                    
                    onReleased: {
                        if (!updateBtn.triggered && updateBtn.fillLevel < 1.0) {
                            fillAnim.stop();
                            drainAnim.start();
                        }
                    }
                }

                NumberAnimation {
                    id: fillAnim
                    target: updateBtn
                    property: "fillLevel"
                    to: 1.0
                    duration: 1200 * (1.0 - updateBtn.fillLevel)
                    easing.type: Easing.InSine
                    onFinished: {
                        updateBtn.triggered = true;
                        let cmd = "if command -v kitty >/dev/null 2>&1; then kitty --hold bash -c 'eval \"$(curl -fsSL https://raw.githubusercontent.com/ilyamiro/imperative-dots/master/install.sh)\"'; else ${TERM:-xterm} -hold -e bash -c 'eval \"$(curl -fsSL https://raw.githubusercontent.com/ilyamiro/imperative-dots/master/install.sh)\"'; fi";
                        Quickshell.execDetached(["bash", "-c", cmd]);
                        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
                    }
                }

                NumberAnimation {
                    id: drainAnim
                    target: updateBtn
                    property: "fillLevel"
                    to: 0.0
                    duration: 800 * updateBtn.fillLevel
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
