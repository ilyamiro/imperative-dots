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
    // COLORS (Dynamic Matugen Palette + Added Blob Colors)
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle || _theme.base
    readonly property color crust: _theme.crust
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color green: _theme.green
    
    // Added for background blobs
    readonly property color mauve: _theme.mauve || "#cba6f7"
    readonly property color blue: _theme.blue || "#89b4fa"

    // -------------------------------------------------------------------------
    // STATE & POLLING
    // -------------------------------------------------------------------------
    property string localVersion: "..."
    property string remoteVersion: "..."
    
    // Box animation properties
    property var pendingCommits: []
    property int typeIndex: 0

    ListModel {
        id: commitModel
    }

    // --- BACKGROUND ORBIT ANIMATION ---
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: true
    }

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

    // Highly robust python script to trace the commit difference via install.sh history
    property string fetchScript: `
import urllib.request, json, subprocess

repo = 'ilyamiro/imperative-dots'

try:
    local = subprocess.check_output("source ~/.local/state/imperative-dots-version 2>/dev/null && echo $LOCAL_VERSION", shell=True).decode('utf-8').strip()
except:
    local = ''

if not local:
    local = '0.0.0'

def get_latest():
    try:
        req = urllib.request.Request('https://api.github.com/repos/' + repo + '/commits/master', headers={'User-Agent': 'updater'})
        res = urllib.request.urlopen(req, timeout=5)
        print(json.loads(res.read().decode())['commit']['message'])
    except Exception: print('No changelog available')

try:
    if local in ['0.0.0', '...', '']: 
        get_latest()
    else:
        # Step 1: Find the commit SHA where install.sh contained the local version
        req_commits = urllib.request.Request('https://api.github.com/repos/' + repo + '/commits?path=install.sh&per_page=15', headers={'User-Agent': 'updater'})
        res_commits = urllib.request.urlopen(req_commits, timeout=5)
        file_commits = json.loads(res_commits.read().decode())
        
        local_sha = None
        for c in file_commits:
            sha = c['sha']
            try:
                raw_req = urllib.request.Request('https://raw.githubusercontent.com/' + repo + '/' + sha + '/install.sh', headers={'User-Agent': 'updater'})
                raw_res = urllib.request.urlopen(raw_req, timeout=5)
                content = raw_res.read().decode('utf-8')
                
                for line in content.splitlines():
                    if line.startswith('DOTS_VERSION='):
                        ver = line.split('=', 1)[1].strip().strip('"\\'')
                        if ver == local:
                            local_sha = sha
                        break
            except: pass
            
            if local_sha:
                break
                
        # Step 2: Use the exact SHA to get all commits in between
        if local_sha:
            compare_req = urllib.request.Request('https://api.github.com/repos/' + repo + '/compare/' + local_sha + '...master', headers={'User-Agent': 'updater'})
            compare_res = urllib.request.urlopen(compare_req, timeout=5)
            data = json.loads(compare_res.read().decode())
            commits = data.get('commits', [])
            
            if commits:
                for c in reversed(commits):
                    print(c['commit']['message'])
                    print('---SPLIT---')
            else:
                get_latest()
        else:
            get_latest()
except Exception as e:
    get_latest()
`

    Process {
        command: ["python3", "-c", window.fetchScript]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out !== "") {
                    let blocks = out.split("---SPLIT---");
                    let validLines = [];
                    
                    for (let i = 0; i < blocks.length; i++) {
                        let blockTrimmed = blocks[i].trim();
                        if (blockTrimmed === "") continue;
                        
                        // Parse literally every new line inside the commit into separate boxes
                        let lines = blockTrimmed.split(/\\r\\n|\\n|\r\n|\n/);
                        for (let j = 0; j < lines.length; j++) {
                            let trimmed = lines[j].trim();
                            if (trimmed.length > 0) {
                                validLines.push(trimmed);
                            }
                        }
                    }

                    commitModel.clear();
                    
                    if (validLines.length > 0) {
                        window.pendingCommits = validLines;
                        window.typeIndex = 0;
                        commitBoxTimer.start();
                    } else {
                        commitModel.append({ "lineText": "No changelog available." });
                    }
                } else {
                    commitModel.clear();
                    commitModel.append({ "lineText": "No changelog available." });
                }
            }
        }
    }

    Timer {
        id: commitBoxTimer
        interval: 100 // Slightly faster cascade for multiple commits
        repeat: true
        onTriggered: {
            if (window.typeIndex < window.pendingCommits.length) {
                commitModel.append({ "lineText": window.pendingCommits[window.typeIndex] });
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

        // --- AMBIENT BLOBS ---
        Rectangle {
            width: parent.width * 0.8; height: width; radius: width / 2
            x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(150)
            y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(100)
            opacity: 0.08
            color: window.mauve
            Behavior on color { ColorAnimation { duration: 1000 } }
        }
        
        Rectangle {
            width: parent.width * 0.9; height: width; radius: width / 2
            x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-150)
            y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-100)
            opacity: 0.06
            color: window.blue
            Behavior on color { ColorAnimation { duration: 1000 } }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: window.s(25)
            spacing: window.s(20)

            // --- ANIMATED CHOREOGRAPHED VERSIONS ---
            Item {
                id: versionContainer
                Layout.fillWidth: true
                Layout.preferredHeight: window.s(60)

                readonly property real finalNewX: (width - newVer.implicitWidth) / 2
                readonly property real finalArrowX: finalNewX - arrowIcon.implicitWidth - window.s(24)
                readonly property real finalOldX: finalArrowX - oldVer.implicitWidth - window.s(24)
                readonly property real initialOldX: (width - oldVer.implicitWidth) / 2

                Text { 
                    id: oldVer
                    text: window.localVersion
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(22)
                    color: window.subtext0 
                    anchors.verticalCenter: parent.verticalCenter
                    x: versionContainer.initialOldX 
                }
                
                Text { 
                    id: arrowIcon
                    text: ""
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: window.s(22)
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
                    font.pixelSize: window.s(48) 
                    color: window.green 
                    anchors.verticalCenter: parent.verticalCenter
                    x: versionContainer.finalNewX 
                    opacity: 0
                    scale: 0.8 // Start smaller for a satisfying pop
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

                // Smooth, fluid animation sequence
                SequentialAnimation {
                    id: versionAnim

                    PauseAnimation { duration: 150 }

                    ParallelAnimation {
                        // 1. Old version smoothly slides left and dims
                        NumberAnimation { 
                            target: oldVer; property: "x"; 
                            to: versionContainer.finalOldX
                            duration: 700; easing.type: Easing.OutExpo 
                        }
                        NumberAnimation {
                            target: oldVer; property: "opacity";
                            to: 0.3
                            duration: 600; easing.type: Easing.OutSine
                        }

                        // 2. Arrow fades in and slides into place
                        SequentialAnimation {
                            PauseAnimation { duration: 100 }
                            ParallelAnimation {
                                NumberAnimation { target: arrowIcon; property: "opacity"; to: 1; duration: 400; easing.type: Easing.OutSine }
                                NumberAnimation { 
                                    target: arrowIcon; property: "x"; 
                                    from: versionContainer.initialOldX
                                    to: versionContainer.finalArrowX
                                    duration: 600; easing.type: Easing.OutExpo 
                                }
                            }
                        }

                        // 3. New version slides in and scales up with a satisfying bounce
                        SequentialAnimation {
                            PauseAnimation { duration: 200 }
                            ParallelAnimation {
                                NumberAnimation { target: newVer; property: "opacity"; to: 1; duration: 400; easing.type: Easing.OutSine }
                                NumberAnimation { 
                                    target: newVer; property: "x"; 
                                    from: versionContainer.finalNewX + window.s(20)
                                    to: versionContainer.finalNewX
                                    duration: 600; easing.type: Easing.OutExpo 
                                }
                                NumberAnimation { 
                                    target: newVer; property: "scale"; 
                                    to: 1.0; 
                                    duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.4 
                                }
                            }
                            ScriptAction { script: glowAnim.start() }
                        }
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

            // --- CLEAN COMMIT LIST ---
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: changelogList
                    anchors.fill: parent
                    clip: true
                    model: commitModel
                    spacing: window.s(8) // Reduced spacing for a tighter look

                    ScrollBar.vertical: ScrollBar {
                        active: true
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { 
                            implicitWidth: window.s(3); 
                            radius: window.s(1.5); 
                            color: window.surface2; 
                            opacity: 0.5 
                        }
                    }

                    // Elegant pop-in transition for the separate commit boxes
                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutExpo }
                            NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 450; easing.type: Easing.OutBack }
                            NumberAnimation { property: "y"; from: y + window.s(15); duration: 450; easing.type: Easing.OutExpo }
                        }
                    }

                    delegate: Rectangle {
                        width: changelogList.width - window.s(12) 
                        height: Math.max(window.s(40), commitText.implicitHeight + window.s(20))
                        
                        color: window.surface0 
                        radius: window.s(12)
                        
                        Text {
                            id: commitText
                            anchors.fill: parent
                            anchors.margins: window.s(10)
                            anchors.leftMargin: window.s(16)
                            anchors.rightMargin: window.s(16)
                            text: model.lineText
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(13)
                            color: window.text
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                            lineHeight: 1.4
                        }
                    }
                }
            }

            // --- HOLD TO UPDATE BUTTON ---
            Rectangle {
                id: updateBtn
                Layout.alignment: Qt.AlignHCenter // Centered instead of stretched
                Layout.preferredWidth: window.s(240) // Fixed, elegant width
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
