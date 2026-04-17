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
    property string commitMessage: "Fetching changelog..."

    Keys.onEscapePressed: {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }

    Process {
        command: ["bash", "-c", "source ~/.local/state/imperative-dots-version 2>/dev/null && echo $LOCAL_VERSION || echo 'Unknown'"]
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
                if (out !== "") window.commitMessage = out;
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
            spacing: window.s(15)

            // --- MINIMAL HEADER ---
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "New version available"
                font.family: "JetBrains Mono"
                font.weight: Font.Medium
                font.pixelSize: window.s(13)
                color: window.subtext0
            }

            // --- VERSION NUMBERS ---
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: window.s(15)

                Text { 
                    text: window.localVersion
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(16)
                    color: window.text 
                }
                
                Text { 
                    text: ""
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: window.s(16)
                    color: window.subtext0 
                }
                
                Text { 
                    text: window.remoteVersion
                    font.family: "JetBrains Mono"
                    font.weight: Font.Black
                    font.pixelSize: window.s(28)
                    color: window.green 
                }
            }

            // --- CENTERED CHANGELOG FRAME ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: window.s(10)
                Layout.bottomMargin: window.s(10)
                radius: window.s(12)
                color: window.surface0
                border.color: window.surface1
                border.width: 1
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
                        contentItem: Rectangle { implicitWidth: window.s(4); radius: window.s(2); color: window.surface2 }
                    }
                    
                    Text {
                        width: changelogScroll.availableWidth
                        text: window.commitMessage
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(13)
                        color: window.subtext0
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // --- HOLD TO UPDATE BUTTON (SINE WAVE) ---
            Rectangle {
                id: updateBtn
                Layout.fillWidth: true
                Layout.preferredHeight: window.s(54)
                radius: window.s(12)
                color: window.surface0
                border.color: btnMa.containsMouse ? window.green : window.surface2
                border.width: btnMa.containsMouse ? window.s(2) : 1
                clip: true
                
                scale: btnMa.pressed ? 0.98 : (btnMa.containsMouse ? 1.02 : 1.0)
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
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
                        duration: 800
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
                        
                        // 1. Build the dynamic wave shape
                        ctx.beginPath();
                        ctx.moveTo(0, 0);
                        
                        if (updateBtn.fillLevel < 0.99) {
                            var waveAmp = window.s(10) * Math.sin(updateBtn.fillLevel * Math.PI); 
                            if (currentW - waveAmp < 0) waveAmp = currentW;
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

                        // 2. Build the rounded rectangle bounds so the gradient respects the button's radius
                        ctx.beginPath();
                        ctx.moveTo(r, 0);
                        ctx.lineTo(width - r, 0);
                        ctx.arcTo(width, 0, width, r, r);
                        ctx.lineTo(width, height - r);
                        ctx.arcTo(width, height, width - r, height, r);
                        ctx.lineTo(r, height);
                        ctx.arcTo(0, height, 0, height - r, r);
                        ctx.lineTo(0, r);
                        ctx.arcTo(0, 0, r, 0, r);
                        ctx.closePath();

                        var grad = ctx.createLinearGradient(0, 0, currentW, 0);
                        grad.addColorStop(0, Qt.lighter(window.green, 1.15).toString());
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
                    duration: 1500 * updateBtn.fillLevel
                    easing.type: Easing.OutQuad
                }
            }
        }
    }
}
