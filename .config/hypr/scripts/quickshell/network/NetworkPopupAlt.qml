import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window
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
        currentWidth: Screen.width
    }
    
    function s(val) { 
        return scaler.s(val); 
    }

    Settings {
        id: cache
        category: "QS_DesktopNetworkWidget"
        property string lastEthJson: ""
    }

    Component.onCompleted: {
        if (cache.lastEthJson !== "") processEthJson(cache.lastEthJson);
        introState = 1.0;
    }

    function playSfx(filename) {
        try {
            let rawUrl = Qt.resolvedUrl("sounds/" + filename).toString();
            let cleanPath = rawUrl;
            if (cleanPath.indexOf("file://") === 0) cleanPath = cleanPath.substring(7); 
            let cmd = "pw-play '" + cleanPath + "' 2>/dev/null || paplay '" + cleanPath + "' 2>/dev/null";
            Quickshell.execDetached(["sh", "-c", cmd]);
        } catch(e) {}
    }

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
    readonly property color sapphire: _theme.sapphire
    readonly property color blue: _theme.blue
    readonly property color red: _theme.red
    readonly property color maroon: _theme.maroon
    readonly property color peach: _theme.peach

    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/network"
    
    readonly property color ethAccent: Qt.lighter(window.sapphire, 1.15) 
    readonly property color activeColor: window.ethAccent
    readonly property color activeGradientSecondary: Qt.darker(window.activeColor, 1.25)

    // Simplified connection logic
    property string ethDeviceName: "" // Stores interface name (e.g. enp5s0)
    property bool ethPowerPending: false
    property string expectedEthPower: ""
    property string ethPower: "off"
    property var ethConnected: null
    readonly property bool isEthConn: !!window.ethConnected

    readonly property bool currentPower: window.ethPower === "on"
    readonly property bool currentPowerPending: window.ethPowerPending
    readonly property bool currentConn: window.isEthConn
    
    // Core synchronization 
    property var currentCore: window.ethConnected
    property real activeCoreCount: currentConn ? 1 : 0
    property real smoothedActiveCoreCount: activeCoreCount
    Behavior on smoothedActiveCoreCount { NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo } }

    Timer { id: ethPendingReset; interval: 8000; onTriggered: { window.ethPowerPending = false; window.expectedEthPower = ""; } }

    onCurrentConnChanged: updateInfoNodes()

    ListModel { id: infoListModel }

    function syncModel(listModel, dataArray) {
        for (let i = listModel.count - 1; i >= 0; i--) {
            let id = listModel.get(i).id;
            let found = false;
            for (let j = 0; j < dataArray.length; j++) {
                if (id === dataArray[j].id) { found = true; break; }
            }
            if (!found) listModel.remove(i);
        }
        
        for (let i = 0; i < dataArray.length && i < 30; i++) {
            let d = dataArray[i];
            let foundIdx = -1;
            for (let j = i; j < listModel.count; j++) {
                if (listModel.get(j).id === d.id) { foundIdx = j; break; }
            }
            
            let obj = {
                id: d.id || "", name: d.name || "", icon: d.icon || "", action: d.action || "",
                isInfoNode: d.isInfoNode || false, isActionable: d.isActionable || false, 
                cmdStr: d.cmdStr || "", parentIndex: 0
            };

            if (foundIdx === -1) {
                listModel.insert(i, obj);
            } else {
                if (foundIdx !== i) { listModel.move(foundIdx, i, 1); }
                for (let key in obj) { 
                    if (listModel.get(i)[key] !== obj[key]) {
                        listModel.setProperty(i, key, obj[key]); 
                    }
                }
            }
        }
    }

    function updateInfoNodes() {
        let nodes = [];
        let obj = window.currentCore;
        
        if (window.currentConn && obj) {
            nodes.push({ id: "ip", name: obj.ip || "No IP", icon: "󰩟", action: "IP Address", isInfoNode: true });
            nodes.push({ id: "spd", name: obj.speed || "Unknown", icon: "󰓅", action: "Link Speed", isInfoNode: true });
            nodes.push({ id: "mac", name: obj.mac || "Unknown", icon: "󰒋", action: "MAC Address", isInfoNode: true });
        }
        window.syncModel(infoListModel, nodes);
    }

    function processEthJson(textData) {
        if (textData === "") return;
        try {
            let data = JSON.parse(textData);
            
            let fetchedDevice = data.device || "";
            if (fetchedDevice !== "") window.ethDeviceName = fetchedDevice;

            let fetchedPower = data.power || "off";
            
            if (window.ethPowerPending) {
                window.ethPower = window.expectedEthPower; 
                if (fetchedPower === window.expectedEthPower) {
                    window.ethPowerPending = false; 
                    ethPendingReset.stop();
                }
            } else {
                window.ethPower = fetchedPower;
                window.expectedEthPower = "";
            }

            let newConnected = data.connected;
            if (JSON.stringify(window.ethConnected) !== JSON.stringify(newConnected)) {
                if (!window.isEthConn && newConnected) window.playSfx("connect.wav");
                window.ethConnected = newConnected;
                updateInfoNodes();
            }
        } catch(e) {}
    }

    Process {
        id: ethPoller
        command: ["bash", window.scriptsDir + "/eth_panel_logic.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cache.lastEthJson = this.text.trim();
                processEthJson(cache.lastEthJson);
            }
        }
    }
    
    Timer {
        interval: 3000
        running: true; repeat: true
        onTriggered: { 
            if (!ethPoller.running) ethPoller.running = true; 
        }
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 200000; loops: Animation.Infinite; running: true
    }

    property real introState: 0.0
    Behavior on introState { NumberAnimation { duration: 1500; easing.type: Easing.OutCubic } }

    Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            radius: window.s(20)
            color: window.base
            border.color: window.surface0
            border.width: 1
            clip: true

            Rectangle {
                width: parent.width * 0.8; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(150)
                y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(100)
                opacity: window.currentPower ? 0.08 : 0.02
                color: window.currentConn ? window.activeColor : window.surface2
                Behavior on color { ColorAnimation { duration: 1000 } }
                Behavior on opacity { NumberAnimation { duration: 1000 } }
            }
            
            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-150)
                y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-100)
                opacity: window.currentPower ? 0.06 : 0.01
                color: window.currentConn ? window.activeGradientSecondary : window.surface1
                Behavior on color { ColorAnimation { duration: 1000 } }
                Behavior on opacity { NumberAnimation { duration: 1000 } }
            }

            Item {
                id: radarItem
                anchors.fill: parent
                anchors.bottomMargin: window.s(40) 
                opacity: window.currentPower ? 1.0 : 0.0
                scale: window.currentPower ? 1.0 : 1.05
                Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
                Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                
                Repeater {
                    model: 3
                    Rectangle {
                        anchors.centerIn: parent
                        width: window.s(280) + (index * window.s(170))
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: window.activeColor
                        border.width: 1
                        
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        opacity: window.currentConn ? 0.08 - (index * 0.02) : 0.03
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }

            Canvas {
                id: nodeLinesCanvas
                anchors.fill: parent
                anchors.bottomMargin: window.s(40)
                z: 0 
                opacity: (window.currentConn && window.currentPower) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 500 } }
                
                property real scaleTrigger: window.s(1)
                onScaleTriggerChanged: requestPaint()

                Timer {
                    interval: 45
                    running: nodeLinesCanvas.opacity > 0.01 && window.currentPower 
                    repeat: true
                    onTriggered: nodeLinesCanvas.requestPaint()
                }

                Connections {
                    target: window
                    function onGlobalOrbitAngleChanged() { 
                        if (window.currentConn && window.currentPower) nodeLinesCanvas.requestPaint() 
                    }
                }
                
                onPaint: {
                    var ctx = getContext("2d");
                    var s = window.s;
                    ctx.clearRect(0, 0, width, height);
                    if (!window.currentConn || !window.currentPower) return;
                    
                    var time = Date.now() / 1000;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";

                    var tWave1 = time * 2.5;
                    var tWave2 = time * -1.5;

                    for (var i = 0; i < orbitRepeater.count; i++) {
                        var item = orbitRepeater.itemAt(i);
                        if (!item || !item.isLoaded) continue;

                        var targetX = item.x + item.width / 2;
                        var targetY = item.y + item.height / 2;

                        function drawStrands(startX, startY, parentFade, parentWidth) {
                            var dx = targetX - startX;
                            var dy = targetY - startY;
                            var fullDist = Math.sqrt(dx * dx + dy * dy);
                            
                            if (fullDist < s(10)) return;

                            var alpha = Math.atan2(dy, dx);
                            var cosA = Math.cos(alpha);
                            var sinA = Math.sin(alpha);
                            
                            var coreVisualRadius = parentWidth / 2;
                            var startOffset = coreVisualRadius + s(5); 
                            var endOffset = s(35); 
                            
                            var drawDist = fullDist - startOffset - endOffset;
                            if (drawDist <= 0) return;
                            
                            var steps = 8;
                            var perpX = -sinA;
                            var perpY = cosA;

                            var sX = startX + cosA * startOffset;
                            var sY = startY + sinA * startOffset;

                            var distanceFactor = Math.max(0, 1.0 - (fullDist / 400.0));
                            var dynamicLineWidthCore = s(1.0) + (distanceFactor * s(2.0));
                            var dynamicLineWidthGlow = s(4.0) + (distanceFactor * s(4.0));
                            var dynamicAlpha = (0.2 + (distanceFactor * 0.7)) * parentFade;

                            ctx.beginPath();
                            ctx.moveTo(sX, sY);
                            for (var j = 1; j <= steps; j++) {
                                var t = j / steps;
                                var currentDist = drawDist * t;
                                var envelope = Math.sin(t * Math.PI);
                                var offset = Math.sin(tWave1 + t * 6) * s(6) * envelope + ((Math.random() - 0.5) * s(5.0) * distanceFactor);
                                ctx.lineTo(sX + cosA * currentDist + perpX * offset, sY + sinA * currentDist + perpY * offset);
                            }
                            ctx.lineWidth = dynamicLineWidthGlow;
                            ctx.strokeStyle = window.activeColor;
                            ctx.globalAlpha = dynamicAlpha * 0.15;
                            ctx.stroke();

                            ctx.lineWidth = dynamicLineWidthCore;
                            ctx.strokeStyle = "#ffffff";
                            ctx.globalAlpha = dynamicAlpha;
                            ctx.stroke();

                            ctx.beginPath();
                            ctx.moveTo(sX, sY);
                            for (var k = 1; k <= steps; k++) {
                                var tk = k / steps;
                                var currentDistK = drawDist * tk;
                                var envelopeK = Math.sin(tk * Math.PI);
                                var offsetK = Math.cos(tWave2 + tk * 8) * s(12) * envelopeK + ((Math.random() - 0.5) * s(3.0) * distanceFactor);
                                ctx.lineTo(sX + cosA * currentDistK + perpX * offsetK, sY + sinA * currentDistK + perpY * offsetK);
                            }
                            ctx.lineWidth = dynamicLineWidthCore * 1.5;
                            ctx.strokeStyle = window.activeColor;
                            ctx.globalAlpha = dynamicAlpha * 0.3;
                            ctx.stroke();
                        }

                        if (coreContainer.activeTransition > 0.01) {
                            drawStrands(coreContainer.x + coreContainer.width/2, coreContainer.y + coreContainer.height/2, coreContainer.activeTransition, coreContainer.width);
                        }
                    }
                }
            }

            Item {
                id: orbitContainer
                anchors.fill: parent
                anchors.bottomMargin: window.s(40) 
                z: 1

                // =========================================================
                // 1. SINGLE CENTRAL CORE (Desktop Focus)
                // =========================================================
                Item {
                    id: coreContainer
                    
                    property bool hasDevice: window.currentCore !== null
                    property real activeTransition: window.introState 

                    width: window.currentPower ? window.s(200) : window.s(160)
                    height: width
                    
                    anchors.centerIn: parent
                    
                    opacity: activeTransition
                    scale: centralCore.bumpScale * (0.8 + 0.2 * activeTransition)

                    MultiEffect {
                        source: centralCore
                        anchors.fill: centralCore
                        shadowEnabled: true
                        shadowColor: "#000000"
                        shadowOpacity: window.currentPower ? 0.5 : 0.0
                        shadowBlur: 1.2
                        shadowVerticalOffset: window.s(6)
                        z: -1
                        Behavior on shadowOpacity { NumberAnimation { duration: 600 } }
                    }

                    Rectangle {
                        id: centralCore
                        anchors.fill: parent
                        radius: width / 2
                        
                        property real disconnectFill: 0.0
                        property bool disconnectTriggered: false
                        property real flashOpacity: 0.0
                        property real bumpScale: 1.0
                        property bool isDangerState: coreMa.containsMouse || disconnectFill > 0
                        
                        scale: bumpScale

                        SequentialAnimation on bumpScale {
                            id: coreBumpAnim
                            running: false
                            NumberAnimation { to: 1.15; duration: 200; easing.type: Easing.OutBack }
                            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.OutQuint }
                        }

                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop {
                                position: 0.0
                                color: {
                                    if (!window.currentPower) return window.mantle;
                                    if (centralCore.isDangerState && window.currentConn) return Qt.lighter(window.red, 1.15);
                                    return window.currentConn ? Qt.lighter(window.activeColor, 1.15) : window.surface0;
                                }
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            GradientStop {
                                position: 1.0
                                color: {
                                    if (!window.currentPower) return window.crust;
                                    if (centralCore.isDangerState && window.currentConn) return window.red;
                                    return window.currentConn ? window.activeColor : window.base;
                                }
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                        }

                        border.color: {
                            if (!window.currentPower) return window.crust;
                            if (centralCore.isDangerState && window.currentConn) return window.maroon;
                            return window.currentConn ? Qt.lighter(window.activeColor, 1.1) : window.surface1;
                        }
                        border.width: window.s(2)
                        Behavior on border.color { ColorAnimation { duration: 300 } }
                        
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "#ffffff"
                            opacity: centralCore.flashOpacity
                            PropertyAnimation on opacity { id: coreFlashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                        }

                        Canvas {
                            id: coreWave
                            anchors.fill: parent
                            visible: centralCore.disconnectFill > 0
                            opacity: 0.95

                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()

                            property real wavePhase: 0.0
                            NumberAnimation on wavePhase {
                                running: centralCore.disconnectFill > 0.0 && centralCore.disconnectFill < 1.0
                                loops: Animation.Infinite
                                from: 0; to: Math.PI * 2; duration: 800
                            }
                            onWavePhaseChanged: requestPaint()
                            Connections { target: centralCore; function onDisconnectFillChanged() { coreWave.requestPaint() } }

                            onPaint: {
                                var ctx = getContext("2d");
                                var s = window.s;
                                ctx.clearRect(0, 0, width, height);
                                if (centralCore.disconnectFill <= 0.001) return;

                                var r = width / 2;
                                var fillY = height * (1.0 - centralCore.disconnectFill);

                                ctx.save();
                                ctx.beginPath();
                                ctx.arc(r, r, r, 0, 2 * Math.PI);
                                ctx.clip(); 

                                ctx.beginPath();
                                ctx.moveTo(0, fillY);
                                if (centralCore.disconnectFill < 0.99) {
                                    var waveAmp = s(10) * Math.sin(centralCore.disconnectFill * Math.PI);
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
                                
                                var grad = ctx.createLinearGradient(0, 0, 0, height);
                                grad.addColorStop(0, window.surface1.toString()); 
                                grad.addColorStop(1, window.crust.toString());
                                ctx.fillStyle = grad;
                                ctx.fill();
                                ctx.restore();
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + window.s(40)
                            height: width
                            radius: width / 2
                            color: centralCore.isDangerState && window.currentConn ? window.red : window.activeColor
                            opacity: window.currentConn ? (centralCore.isDangerState ? 0.3 : 0.15) : 0.0
                            z: -1
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            
                            SequentialAnimation on scale {
                                loops: Animation.Infinite; running: window.currentConn
                                NumberAnimation { to: coreMa.containsMouse ? 1.15 : 1.1; duration: coreMa.containsMouse ? 800 : 2000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: coreMa.containsMouse ? 800 : 2000; easing.type: Easing.InOutSine }
                            }
                        }
                        
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + window.s(15)
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.color: centralCore.isDangerState ? window.red : window.activeColor
                            border.width: window.s(3)
                            z: -2
                            
                            property real pulseOp: 0.0
                            property real pulseSc: 1.0
                            opacity: (window.currentConn && window.currentPower) ? pulseOp : 0.0
                            scale: pulseSc
                            
                            Timer {
                                interval: 45
                                running: parent.opacity > 0.01
                                repeat: true
                                onTriggered: {
                                    var time = Date.now() / 1000;
                                    parent.pulseOp = 0.3 + Math.sin(time * 2.5) * 0.15;
                                    parent.pulseSc = 1.02 + Math.cos(time * 3.0) * 0.02;
                                }
                            }
                        }

                        // OFFLINE TEXT
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: window.s(10)
                            visible: !window.currentConn || !window.currentPower
                            opacity: visible ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: window.s(48)
                                color: window.currentPower ? window.overlay0 : window.surface2
                                text: "󰈂"
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                font.family: "JetBrains Mono"; font.weight: Font.Bold
                                font.pixelSize: window.s(14)
                                color: window.overlay0
                                text: window.currentPowerPending 
                                    ? (window.expectedEthPower === "on" ? "Powering On..." : "Powering Off...") 
                                    : (!window.currentPower ? "Device Offline" : "Disconnected")
                            }
                        }

                        // ONLINE TEXT
                        Item {
                            anchors.fill: parent
                            visible: window.currentConn && window.currentPower
                            opacity: visible ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }

                            ColumnLayout {
                                id: baseCoreText
                                anchors.centerIn: parent
                                spacing: window.s(4)

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: window.s(48)
                                    color: window.crust
                                    text: coreMa.containsMouse ? "󰈂" : (window.currentCore ? window.currentCore.icon : "")
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: window.s(150)
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: "JetBrains Mono"; font.weight: Font.Black
                                    font.pixelSize: window.s(16)
                                    color: window.crust
                                    text: window.currentCore ? window.currentCore.name : ""
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11)
                                    color: coreMa.containsMouse ? window.crust : "#99000000"
                                    text: centralCore.disconnectFill > 0.01 ? "Hold..." : "Connected"
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }

                            // Clipped overlay during disconnect drain animation
                            Item {
                                id: waveClipItem
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: Math.min(parent.height, Math.max(0, parent.height * centralCore.disconnectFill + window.s(8)))
                                clip: true
                                visible: centralCore.disconnectFill > 0

                                ColumnLayout {
                                    spacing: window.s(4)
                                    x: waveClipItem.width / 2 - width / 2
                                    y: (centralCore.height / 2) - (height / 2) - (centralCore.height - waveClipItem.height)

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(48)
                                        color: window.text
                                        text: coreMa.containsMouse ? "󰈂" : (window.currentCore ? window.currentCore.icon : "")
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.maximumWidth: window.s(150)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: "JetBrains Mono"; font.weight: Font.Black
                                        font.pixelSize: window.s(16)
                                        color: window.text
                                        text: window.currentCore ? window.currentCore.name : ""
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11)
                                        color: window.text
                                        text: centralCore.disconnectFill > 0.01 ? "Hold..." : "Connected"
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: coreMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: window.currentConn ? Qt.PointingHandCursor : Qt.ArrowCursor
                            
                            onPressed: {
                                if (window.currentConn && !centralCore.disconnectTriggered) {
                                    coreDrainAnim.stop();
                                    coreFillAnim.start();
                                }
                            }
                            onReleased: {
                                if (!centralCore.disconnectTriggered) {
                                    coreFillAnim.stop();
                                    coreDrainAnim.start();
                                }
                            }
                        }

                        NumberAnimation {
                            id: coreFillAnim
                            target: centralCore
                            property: "disconnectFill"
                            to: 1.0
                            duration: 700 * (1.0 - centralCore.disconnectFill) 
                            easing.type: Easing.InSine
                            onFinished: {
                                centralCore.disconnectTriggered = true;
                                centralCore.flashOpacity = 0.6;
                                coreFlashAnim.start();
                                coreBumpAnim.start();
                                
                                window.playSfx("disconnect.wav");
                                
                                let cmd = "nmcli device disconnect '" + window.currentCore.id + "'";
                                Quickshell.execDetached(["sh", "-c", cmd])
                                
                                centralCore.disconnectFill = 0.0;
                                centralCore.disconnectTriggered = false;
                                
                                ethPoller.running = true;
                            }
                        }
                        
                        NumberAnimation {
                            id: coreDrainAnim
                            target: centralCore
                            property: "disconnectFill"
                            to: 0.0
                            duration: 1000 * centralCore.disconnectFill 
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                // =========================================================
                // 2. THE SWARM (Orbiting Info Nodes Only)
                // =========================================================
                Item {
                    anchors.fill: parent
                    opacity: window.currentPower ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

                    Repeater {
                        id: orbitRepeater
                        model: infoListModel
                        
                        delegate: Item {
                            id: floatCardDelegateContainer
                            width: window.s(170); height: window.s(60)

                            property bool isLoaded: false
                            opacity: isLoaded ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                            property real entryAnim: isLoaded ? 1.0 : 0.0
                            Behavior on entryAnim { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }

                            Timer {
                                running: true
                                interval: 600 + (index * 80) 
                                onTriggered: floatCardDelegateContainer.isLoaded = true
                            }

                            property real targetSingleBaseAngle: (index / Math.max(1, orbitRepeater.count)) * Math.PI * 2
                            property real singleBaseAngle: targetSingleBaseAngle
                            Behavior on singleBaseAngle { NumberAnimation { duration: 800; easing.type: Easing.OutExpo } }

                            property real currentAngle: (window.globalOrbitAngle * 1.5) + singleBaseAngle
                            
                            property real currentRadX: window.s(280)
                            property real currentRadY: window.s(180)
                            
                            property real pwrDrift: window.currentPower ? 0 : window.s(40)
                            Behavior on pwrDrift { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

                            property real animRadX: (currentRadX + pwrDrift) * (0.25 + 0.75 * entryAnim)
                            property real animRadY: (currentRadY + pwrDrift) * (0.25 + 0.75 * entryAnim)

                            x: (orbitContainer.width / 2) - (width / 2) + Math.cos(currentAngle) * animRadX
                            y: (orbitContainer.height / 2) - (height / 2) + Math.sin(currentAngle) * animRadY + Math.sin(window.globalOrbitAngle * 6) * window.s(12)

                            scale: !isLoaded ? 0.0 : (floatMa.containsMouse ? 1.08 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
                            z: floatMa.containsMouse ? 10 : index

                            MultiEffect {
                                source: floatCard
                                anchors.fill: floatCard
                                shadowEnabled: window.currentPower && floatCardDelegateContainer.opacity > 0.05
                                shadowColor: "#000000"
                                shadowOpacity: 0.3
                                shadowBlur: 0.8
                                shadowVerticalOffset: window.s(4)
                                z: -1
                            }

                            Rectangle {
                                id: floatCard
                                anchors.fill: parent
                                radius: window.s(14)
                                color: floatMa.containsMouse ? "#2affffff" : "#0effffff"
                                Behavior on color { ColorAnimation { duration: 200 } }
                                
                                property string itemName: name
                                property real nameImplicitWidth: baseNameText.implicitWidth
                                property real nameContainerWidth: nameContainerBase.width
                                property bool doMarquee: floatMa.containsMouse && nameImplicitWidth > nameContainerWidth
                                property real textOffset: 0

                                SequentialAnimation on textOffset {
                                    running: floatCard.doMarquee
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: 600 } 
                                    NumberAnimation {
                                        from: 0; to: -(floatCard.nameImplicitWidth + window.s(30))
                                        duration: (floatCard.nameImplicitWidth + window.s(30)) * 35
                                    }
                                }
                                onDoMarqueeChanged: if (!doMarquee) textOffset = 0;

                                Rectangle {
                                    anchors.fill: parent
                                    radius: window.s(14)
                                    color: "transparent"
                                    border.width: 1
                                    border.color: window.surface2
                                    visible: !floatMa.containsMouse
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: window.s(14)
                                    opacity: floatMa.containsMouse ? 1.0 : 0.0
                                    color: "transparent"
                                    border.width: window.s(2)
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: window.s(2)
                                        radius: window.s(12)
                                        color: window.base
                                        opacity: 0.9
                                    }

                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Qt.lighter(window.activeColor, 1.15) }
                                        GradientStop { position: 1.0; color: window.activeColor }
                                    }
                                    z: -1
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: window.s(12)
                                    spacing: window.s(10)
                                    
                                    Text {
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(20)
                                        color: window.activeColor
                                        text: icon
                                    }
                                    
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: window.s(2)
                                        
                                        Item {
                                            id: nameContainerBase
                                            Layout.fillWidth: true
                                            height: window.s(18)
                                            clip: true

                                            Text {
                                                id: baseNameText
                                                anchors.left: parent.left
                                                anchors.leftMargin: floatCard.textOffset
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: floatCard.itemName
                                                font.family: "JetBrains Mono"
                                                font.weight: Font.Bold
                                                font.pixelSize: window.s(13)
                                                color: window.text
                                            }
                                            Text {
                                                anchors.left: baseNameText.right
                                                anchors.leftMargin: window.s(30)
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: floatCard.doMarquee
                                                text: floatCard.itemName
                                                font.family: "JetBrains Mono"
                                                font.weight: Font.Bold
                                                font.pixelSize: window.s(13)
                                                color: window.text
                                            }
                                        }
                                        
                                        Text {
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(10)
                                            color: window.overlay0
                                            text: action
                                        }
                                    }
                                }

                                MouseArea {
                                    id: floatMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.ArrowCursor
                                }
                            }
                        }
                    }
                }
            }

            // Power Toggle 
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: window.s(30)
                width: window.s(48); height: window.s(48); radius: window.s(24)
                
                color: "transparent"
                border.color: window.currentPowerPending ? window.activeColor : (window.currentPower ? "transparent" : window.surface2)
                border.width: window.s(2)
                Behavior on border.color { ColorAnimation { duration: 300 } }

                Rectangle {
                    anchors.fill: parent
                    radius: window.s(24)
                    opacity: window.currentPower ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.lighter(window.activeColor, 1.15); Behavior on color { ColorAnimation {duration: 300} } }
                        GradientStop { position: 1.0; color: window.activeColor; Behavior on color { ColorAnimation {duration: 300} } }
                    }
                }
                
                scale: pwrMa.pressed ? 0.9 : (pwrMa.containsMouse ? 1.1 : 1.0)
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                Text {
                    id: pwrIcon
                    anchors.centerIn: parent
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: window.s(22)
                    color: window.currentPower ? window.crust : window.text
                    text: window.currentPowerPending ? "󰑮" : "" 
                    Behavior on color { ColorAnimation { duration: 300 } }

                    RotationAnimation {
                        target: pwrIcon
                        property: "rotation"
                        from: 0; to: 360
                        duration: 800
                        loops: Animation.Infinite
                        running: window.currentPowerPending
                        onRunningChanged: {
                            if (!running) pwrIcon.rotation = 0;
                        }
                    }
                }

                MouseArea {
                    id: pwrMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (window.ethPowerPending) return;
                        window.expectedEthPower = window.ethPower === "on" ? "off" : "on";
                        window.ethPowerPending = true;
                        
                        if (window.expectedEthPower === "on") window.playSfx("power_on.wav"); else window.playSfx("power_off.wav");
                        
                        ethPendingReset.restart();
                        window.ethPower = window.expectedEthPower; 
                        
                        // We use the cached device name, or fallback to the currentCore's id
                        let targetDev = window.ethDeviceName !== "" ? window.ethDeviceName : (window.currentCore ? window.currentCore.id : "");
                        
                        if (targetDev !== "") {
                            if (window.expectedEthPower === "on") {
                                Quickshell.execDetached(["nmcli", "device", "connect", targetDev]);
                            } else {
                                Quickshell.execDetached(["nmcli", "device", "disconnect", targetDev]);
                            }
                        }
                        
                        ethPoller.running = true;
                    }
                }
            }
        }
    }
}
