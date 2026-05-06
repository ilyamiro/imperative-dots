import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    // =========================================================
    // --- MODULE CAPABILITIES EXPORT
    // =========================================================
    // Tells the parent Floating.qml to use a "1 Full Block" background grid
    property int requestedLayoutTemplate: 2

    // =========================================================
    // --- SCALING & DIMENSIONS
    // =========================================================
    function s(val) {
        return typeof scaleFunc !== "undefined" ? scaleFunc(val) : val;
    }

    property real baseW: s(600)
    property real baseL: s(500)

    property real preferredWidth: activeEdge === "bottom" ? baseL : baseW
    property real preferredExtraLength: activeEdge === "bottom" ? baseW : baseL

    // =========================================================
    // --- EDGE AWARENESS HELPERS
    // =========================================================
    property real counterRotation: {
        if (typeof activeEdge !== "undefined") {
            if (activeEdge === "right") return 180;
            if (activeEdge === "bottom") return 90;
        }
        return 0; 
    }

    // =========================================================
    // --- STATE & CONFIGURATION
    // =========================================================
    property string currentTool: "mouse" // "mouse", "pen", "brush", "fill", "eraser"
    property var toolKeys: ["mouse", "pen", "brush", "fill", "eraser"]
    property int currentToolIndex: Math.max(0, toolKeys.indexOf(currentTool))

    // UI Toggle States
    property bool showPenConfig: false
    property bool showColorPicker: false

    // Infinite Color Picker State
    property real pickHue: 0.74
    property real pickSat: 0.33
    property real pickVal: 0.97
    property color currentColor: Qt.hsva(pickHue, pickSat, pickVal, 1.0)
    
    // Pen Config State
    property real penSizeRatio: 0.3
    property real actualPenSize: s(2) + (penSizeRatio * s(30)) // Ranges from 2 to 32

    property var baseTextColor: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.text : "#cdd6f4"
    property var solidBgColor: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.mantle : "#181825"
    
    // Universal Panel Styling
    property color panelBgColor: typeof mochaColors !== "undefined" && mochaColors ? Qt.rgba(mochaColors.base.r, mochaColors.base.g, mochaColors.base.b, 0.85) : Qt.rgba(root.solidBgColor.r, root.solidBgColor.g, root.solidBgColor.b, 0.85)
    property color panelBorderColor: typeof mochaColors !== "undefined" && mochaColors ? Qt.rgba(mochaColors.text.r, mochaColors.text.g, mochaColors.text.b, 0.08) : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.15)


    // Zoom limits and World Size
    property real minZoom: 0.1
    property real maxZoom: 5.0
    property real worldSize: 2048 

    // =========================================================
    // --- HISTORY SYSTEM (UNDO / REDO)
    // =========================================================
    property var actionHistory: []
    property int historyStep: -1
    property int maxHistory: 50
    property var currentAction: null

    function commitAction(action) {
        var newHistory = root.actionHistory.slice(0, root.historyStep + 1);
        newHistory.push(action);
        
        if (newHistory.length > root.maxHistory) {
            newHistory.shift();
        }
        
        root.actionHistory = newHistory;
        root.historyStep = root.actionHistory.length - 1;
    }

    function undo() {
        if (root.historyStep >= 0) {
            root.historyStep--;
            triggerReplay();
        }
    }

    function redo() {
        if (root.historyStep < root.actionHistory.length - 1) {
            root.historyStep++;
            triggerReplay();
        }
    }

    function triggerReplay() {
        if (orientedRoot.children.length > 0) {
            drawCanvas._replayPending = true;
            drawCanvas.requestPaint();
        }
    }

    Shortcut { enabled: root.visible; sequence: "Ctrl+Z"; onActivated: root.undo() }
    Shortcut { enabled: root.visible; sequence: "Ctrl+Shift+Z"; onActivated: root.redo() }

    // =========================================================
    // --- MASTER ORIENTATION CONTAINER
    // =========================================================
    Item {
        id: orientedRoot
        anchors.centerIn: parent
        
        width: (root.counterRotation % 180 !== 0) ? parent.height : parent.width
        height: (root.counterRotation % 180 !== 0) ? parent.width : parent.height
        rotation: root.counterRotation
        clip: true // Fixes layout bound bleeds

        // ADDED: Solid Background to replace transparency
        Rectangle {
            anchors.fill: parent
            color: root.solidBgColor
            z: -1
        }

        // =========================================================
        // --- CAMERA RIG (Handles viewport size, rotation, gestures)
        // =========================================================
        Item {
            id: cameraRig
            anchors.fill: parent
            clip: true

            function zoomBy(factor) {
                zoomContainer.scale = Math.max(root.minZoom, Math.min(zoomContainer.scale * factor, root.maxZoom));
            }

            PinchHandler {
                target: zoomContainer
                minimumScale: root.minZoom
                maximumScale: root.maxZoom
            }

            // =========================================================
            // --- CANVAS CONTAINER (Pans and Scales)
            // =========================================================
            Item {
                id: zoomContainer
                width: root.worldSize
                height: root.worldSize
                
                x: (cameraRig.width - width) / 2
                y: (cameraRig.height - height) / 2
                
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                DragHandler {
                    target: zoomContainer
                    enabled: root.currentTool === "mouse"
                    acceptedButtons: Qt.LeftButton
                }

                Image {
                    anchors.fill: parent
                    fillMode: Image.Tile
                    
                    property real dotRadius: s(1.2)
                    property real dotSpacing: s(12)
                    property color dotC: root.baseTextColor
                    
                    source: `data:image/svg+xml;utf8,<svg width='${dotSpacing}' height='${dotSpacing}' xmlns='http://www.w3.org/2000/svg'><circle cx='${dotSpacing/2}' cy='${dotSpacing/2}' r='${dotRadius}' fill='rgb(${dotC.r*255},${dotC.g*255},${dotC.b*255})' fill-opacity='0.15'/></svg>`
                }

                // --- HIGH-PERFORMANCE SYNCHRONOUS CANVAS ---
                Canvas {
                    id: drawCanvas
                    anchors.fill: parent
                    z: 1
                    
		    renderTarget: Canvas.FramebufferObject
                    
                    property real lastX: -1
                    property real lastY: -1
                    
                    property var _queue: []
                    property bool _clearPending: false
                    property bool _replayPending: false

                    function renderBrushLine(ctx, s, isLive) {
                        var bSize = s.penSize || root.s(18);
                        var segments = isLive ? [{x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2}] : s.segments;
                        
                        var bristleCount = Math.max(6, Math.floor(bSize * 0.6));
                        
                        ctx.globalCompositeOperation = "source-over";
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        
                        var col = s.color;
                        
                        for (var b = 0; b < bristleCount; b++) {
                            var t = b / bristleCount;
                            var angle = t * Math.PI * 2;
                            var radius = (0.3 + (((b * 7 + 3) % 11) / 11) * 0.7) * (bSize / 2);
                            var offX = Math.cos(angle) * radius * 0.5;
                            var offY = Math.sin(angle) * radius * 0.5;
                            var alpha = 0.25 + (((b * 13 + 5) % 17) / 17) * 0.45;
                            var width = root.s(0.8) + (((b * 3 + 1) % 5) / 5) * root.s(1.6);
                            
                            ctx.globalAlpha = alpha;
                            ctx.lineWidth = width;
                            ctx.strokeStyle = col;
                            
                            ctx.beginPath();
                            ctx.moveTo(segments[0].x1 + offX, segments[0].y1 + offY);
                            for (var j = 0; j < segments.length; j++) {
                                ctx.lineTo(segments[j].x2 + offX, segments[j].y2 + offY);
                            }
                            ctx.stroke();
                        }
                        
                        ctx.globalAlpha = 1.0;
                    }

                    function applyToolStyle(ctx, tool, color, customSize) {
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        
                        if (tool === "eraser") {
                            ctx.globalCompositeOperation = "destination-out";
                            ctx.lineWidth = s(24);
                            ctx.strokeStyle = "rgba(0,0,0,1)"; 
                            ctx.globalAlpha = 1.0;
                            ctx.shadowBlur = 0;
                            ctx.shadowColor = "transparent";
                        } else { 
                            ctx.globalCompositeOperation = "source-over";
                            ctx.strokeStyle = color;
                            ctx.lineWidth = customSize || root.actualPenSize;
                            ctx.shadowBlur = 0;
                            ctx.shadowColor = "transparent";
                            ctx.globalAlpha = 1.0;
                        }
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        
                        if (_replayPending) {
                            ctx.clearRect(0, 0, width, height);
                            for (var h = 0; h <= root.historyStep; h++) {
                                var action = root.actionHistory[h];
                                if (!action) continue;

                                if (action.type === "clear") {
                                    ctx.clearRect(0, 0, width, height);
                                } else if (action.type === "fill_bg") {
                                    ctx.globalCompositeOperation = "destination-over";
                                    ctx.fillStyle = action.color;
                                    ctx.fillRect(0, 0, width, height);
                                    ctx.globalCompositeOperation = "source-over";
                                } else if (action.type === "stroke") {
                                    if (action.tool === "brush") {
                                        renderBrushLine(ctx, action, false);
                                    } else {
                                        ctx.beginPath();
                                        applyToolStyle(ctx, action.tool, action.color, action.penSize);
                                        
                                        if (action.segments && action.segments.length > 0) {
                                            ctx.moveTo(action.segments[0].x1, action.segments[0].y1);
                                            for (var k = 0; k < action.segments.length; k++) {
                                                ctx.lineTo(action.segments[k].x2, action.segments[k].y2);
                                            }
                                            ctx.stroke();
                                        }
                                    }
                                }
                            }
                            _replayPending = false;
                            _queue = []; 
                            return;
                        }

                        if (_clearPending) {
                            ctx.clearRect(0, 0, width, height);
                            _clearPending = false;
                        }
                        
                        for (var i = 0; i < _queue.length; i++) {
                            var q = _queue[i];
                            
                            if (q.type === "fill_bg") {
                                ctx.globalCompositeOperation = "destination-over";
                                ctx.fillStyle = q.color;
                                ctx.fillRect(0, 0, width, height);
                                ctx.globalCompositeOperation = "source-over";
                            } else if (q.tool === "brush") {
                                renderBrushLine(ctx, q, true);
                            } else {
                                ctx.beginPath();
                                applyToolStyle(ctx, q.tool, q.color, q.penSize);
                                ctx.moveTo(q.x1, q.y1);
                                ctx.lineTo(q.x2, q.y2);
                                ctx.stroke();
                            }
                        }
                        
                        _queue = []; 
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: root.currentTool === "mouse" ? Qt.NoButton : Qt.LeftButton
                        
                        onWheel: (wheel) => {
                            let deltaY = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : (wheel.pixelDelta ? wheel.pixelDelta.y : 0);
                            let deltaX = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : (wheel.pixelDelta ? wheel.pixelDelta.x : 0);
                            let delta = deltaY !== 0 ? deltaY : deltaX;
                            
                            if (delta === 0) {
                                wheel.accepted = false;
                                return;
                            }
                            
                            wheel.accepted = true;
                            let zoomFactor = delta > 0 ? 1.15 : (1.0 / 1.15);
                            cameraRig.zoomBy(zoomFactor);
                        }

                        onPressed: (mouse) => {
                            root.showPenConfig = false;
                            root.showColorPicker = false;

                            if (root.currentTool === "fill") {
                                let freezeCol = root.currentColor.toString();
                                root.commitAction({ type: "fill_bg", color: freezeCol });
                                drawCanvas._queue.push({ type: "fill_bg", color: freezeCol });
                                
                                drawCanvas.markDirty(Qt.rect(0, 0, drawCanvas.width, drawCanvas.height)); 
                                drawCanvas.requestPaint();
                                return;
                            }

                            drawCanvas.lastX = mouse.x;
                            drawCanvas.lastY = mouse.y;
                            
                            root.currentAction = { 
                                type: "stroke", 
                                tool: root.currentTool, 
                                color: root.currentColor.toString(), 
                                penSize: root.actualPenSize,
                                segments: [] 
                            };
                            var initialSegment = { x1: mouse.x, y1: mouse.y, x2: mouse.x + 0.1, y2: mouse.y };
                            root.currentAction.segments.push(initialSegment);

                            drawCanvas._queue.push({
                                type: "stroke",
                                tool: root.currentTool,
                                color: root.currentColor.toString(),
                                penSize: root.actualPenSize,
                                x1: initialSegment.x1, y1: initialSegment.y1, 
                                x2: initialSegment.x2, y2: initialSegment.y2
                            });
                            
                            var rad = s(20);
                            drawCanvas.markDirty(Qt.rect(mouse.x - rad, mouse.y - rad, rad*2, rad*2));
                            drawCanvas.requestPaint();
                        }

                        onPositionChanged: (mouse) => {
                            if (pressed && root.currentTool !== "fill" && root.currentTool !== "mouse") {
                                var segment = {
                                    x1: drawCanvas.lastX, y1: drawCanvas.lastY,
                                    x2: mouse.x, y2: mouse.y
                                };
                                
                                if (root.currentAction) {
                                    root.currentAction.segments.push(segment);
                                }

                                drawCanvas._queue.push({
                                    type: "stroke",
                                    tool: root.currentTool,
                                    color: root.currentColor.toString(),
                                    penSize: root.actualPenSize,
                                    x1: segment.x1, y1: segment.y1, 
                                    x2: segment.x2, y2: segment.y2
                                });
                                
                                var rad = s(20);
                                var minX = Math.min(drawCanvas.lastX, mouse.x) - rad;
                                var minY = Math.min(drawCanvas.lastY, mouse.y) - rad;
                                var w = Math.abs(mouse.x - drawCanvas.lastX) + rad*2;
                                var h = Math.abs(mouse.y - drawCanvas.lastY) + rad*2;
                                
                                drawCanvas.lastX = mouse.x;
                                drawCanvas.lastY = mouse.y;
                                
                                drawCanvas.markDirty(Qt.rect(minX, minY, w, h));
                                drawCanvas.requestPaint();
                            }
                        }

                        onReleased: (mouse) => {
                            if (root.currentAction) {
                                root.commitAction(root.currentAction);
                                root.currentAction = null;
                            }
                        }
                    }
                }
            }
        }

        // =========================================================
        // --- UI LAYER: TOP ACTIONS (Unified Pill Styling)
        // =========================================================
        Row {
            id: topActionsLayout
            z: 10
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: s(20)
            anchors.rightMargin: s(20)
            spacing: s(12)

            // --- ZOOM PILL ---
            Rectangle {
                width: zoomRow.width + s(24)
                height: s(44)
                radius: s(14)
                color: root.panelBgColor
                border.width: 1
                border.color: root.panelBorderColor

                Row {
                    id: zoomRow
                    anchors.centerIn: parent
                    spacing: s(6)

                    Item {
                        width: s(32); height: s(32)
                        Rectangle {
                            anchors.fill: parent; radius: s(14); z:-1
                            color: zoomMinusMouse.containsMouse ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)) : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent; text: "\uF068"; font.family: root.iconFont; font.pixelSize: s(14); color: root.baseTextColor
                        }
                        MouseArea {
                            id: zoomMinusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: cameraRig.zoomBy(1.0 / 1.25)
                        }
                    }

                    Item {
                        width: s(48); height: s(32)
                        Rectangle {
                            anchors.fill: parent; radius: s(14); z:-1
                            color: zoomResetMouse.containsMouse ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)) : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent; text: Math.round(zoomContainer.scale * 100) + "%"; font.pixelSize: s(12); color: root.baseTextColor; font.bold: true
                        }
                        MouseArea {
                            id: zoomResetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                zoomContainer.scale = 1.0;
                                zoomContainer.x = (cameraRig.width - zoomContainer.width) / 2;
                                zoomContainer.y = (cameraRig.height - zoomContainer.height) / 2;
                            }
                        }
                    }

                    Item {
                        width: s(32); height: s(32)
                        Rectangle {
                            anchors.fill: parent; radius: s(14); z:-1
                            color: zoomPlusMouse.containsMouse ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)) : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent; text: "\uF067"; font.family: root.iconFont; font.pixelSize: s(14); color: root.baseTextColor
                        }
                        MouseArea {
                            id: zoomPlusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: cameraRig.zoomBy(1.25)
                        }
                    }
                }
            }

            // --- COPY PILL ---
            Rectangle {
                width: s(44)
                height: s(44)
                radius: s(14)
                color: root.panelBgColor
                border.width: 1
                border.color: root.panelBorderColor
                
                Rectangle {
                    anchors.centerIn: parent; width: s(32); height: s(32); radius: s(14); z:-1
                    color: copyMouse.containsMouse ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)) : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: "\uF0C5" 
                    font.family: root.iconFont
                    font.pixelSize: s(14)
                    color: root.baseTextColor
                    opacity: copyMouse.pressed ? 0.5 : 1.0
                }

                MouseArea {
                    id: copyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var tempPath = "/tmp/quick_action_drawing.png";
                        drawCanvas.save(tempPath);
                        Quickshell.execDetached(["sh", "-c", "wl-copy < " + tempPath]);
                    }
                }
            }
        }

        // =========================================================
        // --- PEN CONFIGURATION POPUP
        // =========================================================
        Rectangle {
            id: penConfigPopup
            z: 20
            width: s(260)
            height: s(64)
            radius: s(14)
            color: typeof mochaColors !== "undefined" && mochaColors ? Qt.rgba(mochaColors.base.r, mochaColors.base.g, mochaColors.base.b, 0.98) : root.solidBgColor
            border.width: 1
            border.color: root.panelBorderColor
            
            anchors.bottom: toolbar.top
            anchors.bottomMargin: s(12)
            anchors.horizontalCenter: parent.horizontalCenter
            
            visible: root.showPenConfig
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutExpo } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: s(18)
                spacing: s(14)

                Text {
                    text: "\uF040" // fa-pen
                    font.family: root.iconFont
                    color: root.baseTextColor
                    font.pixelSize: s(16)
                    opacity: 0.7
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: s(6)
                    radius: s(3)
                    color: typeof mochaColors !== "undefined" && mochaColors ? Qt.rgba(mochaColors.text.r, mochaColors.text.g, mochaColors.text.b, 0.1) : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)
                    
                    Rectangle {
                        width: parent.width * root.penSizeRatio
                        height: parent.height
                        radius: parent.radius
                        color: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.mauve : "#cba6f7"
                    }

                    Rectangle {
                        width: s(18); height: s(18)
                        radius: width/2
                        color: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.mauve : "#cba6f7"
                        x: (parent.width * root.penSizeRatio) - (width/2)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -s(16) // Generous hit box
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: (mouse) => {
                            if (pressed) root.penSizeRatio = Math.max(0.0, Math.min(1.0, mouse.x / width));
                        }
                        onPressed: (mouse) => {
                            root.penSizeRatio = Math.max(0.0, Math.min(1.0, mouse.x / width));
                        }
                    }
                }

                // Dynamic Preview Circle
                Item {
                    width: s(28)
                    height: s(28)
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.actualPenSize
                        height: root.actualPenSize
                        radius: width / 2
                        color: root.currentColor
                        border.width: 1
                        border.color: Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.2)
                    }
                }
            }
        }

        // =========================================================
        // --- ADVANCED COLOR PICKER POPUP
        // =========================================================
        Rectangle {
            id: colorPickerPopup
            z: 20
            width: s(320)
            height: s(340)
            radius: s(14)
            color: typeof mochaColors !== "undefined" && mochaColors ? Qt.rgba(mochaColors.base.r, mochaColors.base.g, mochaColors.base.b, 0.98) : root.solidBgColor
            border.width: 1
            border.color: root.panelBorderColor
            
            anchors.bottom: toolbar.top
            anchors.bottomMargin: s(12)
            anchors.horizontalCenter: parent.horizontalCenter
            
            visible: root.showColorPicker
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutExpo } }

            Column {
                anchors.centerIn: parent
                spacing: s(20)

                // SV Square and Hue Slider
                Row {
                    spacing: s(16)
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Saturation / Value Square
                    Rectangle {
                        width: s(220); height: s(200)
                        radius: s(10)
                        color: Qt.hsva(root.pickHue, 1, 1, 1)
                        clip: true
                        border.width: 0

                        // Inheriting radius guarantees smooth corners on all 4 sides inside clip
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            border.width: 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "white" }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            border.width: 0
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: "black" }
                            }
                        }

                        // Target Reticle
                        Rectangle {
                            width: s(14); height: s(14)
                            radius: width / 2
                            border.width: s(2); border.color: "white"
                            color: "transparent"
                            x: (root.pickSat * parent.width) - (width/2)
                            y: ((1.0 - root.pickVal) * parent.height) - (height/2)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.CrossCursor
                            function updateSV(mouse) {
                                root.pickSat = Math.max(0, Math.min(1, mouse.x / width));
                                root.pickVal = 1.0 - Math.max(0, Math.min(1, mouse.y / height));
                            }
                            onPressed: (mouse) => updateSV(mouse)
                            onPositionChanged: (mouse) => { if (pressed) updateSV(mouse) }
                        }
                    }

                    // Hue Slider
                    Rectangle {
                        width: s(24); height: s(200)
                        radius: s(10)
                        clip: true
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: "#ff0000" }
                            GradientStop { position: 0.166; color: "#ffff00" }
                            GradientStop { position: 0.333; color: "#00ff00" }
                            GradientStop { position: 0.5; color: "#00ffff" }
                            GradientStop { position: 0.666; color: "#0000ff" }
                            GradientStop { position: 0.833; color: "#ff00ff" }
                            GradientStop { position: 1.0; color: "#ff0000" }
                        }

                        Rectangle {
                            width: parent.width; height: s(8)
                            radius: s(4)
                            border.width: 1; border.color: "black"
                            color: "white"
                            y: (root.pickHue * parent.height) - (height/2)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function updateH(mouse) {
                                root.pickHue = Math.max(0, Math.min(1, mouse.y / height));
                            }
                            onPressed: (mouse) => updateH(mouse)
                            onPositionChanged: (mouse) => { if (pressed) updateH(mouse) }
                        }
                    }
                }

                // Quick Swatches
                Grid {
                    columns: 8
                    spacing: s(12)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: [
                            typeof mochaColors !== "undefined" && mochaColors ? mochaColors.red : "#f38ba8",
                            typeof mochaColors !== "undefined" && mochaColors ? mochaColors.peach : "#fab387",
                            typeof mochaColors !== "undefined" && mochaColors ? mochaColors.yellow : "#f9e2af",
                            typeof mochaColors !== "undefined" && mochaColors ? mochaColors.green : "#a6e3a1",
                            typeof mochaColors !== "undefined" && mochaColors ? mochaColors.sapphire : "#74c7ec",
                            typeof mochaColors !== "undefined" && mochaColors ? mochaColors.blue : "#89b4fa",
                            typeof mochaColors !== "undefined" && mochaColors ? mochaColors.mauve : "#cba6f7",
                            typeof mochaColors !== "undefined" && mochaColors ? mochaColors.text : "#cdd6f4"
                        ]
                        
                        Rectangle {
                            width: s(20)
                            height: s(20)
                            radius: width / 2
                            color: modelData
                            
                            border.width: root.currentColor.toString() === color.toString() ? s(2) : 0
                            border.color: root.baseTextColor
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.currentColor = parent.color;
                                }
                            }
                        }
                    }
                }

                // Hex Input
                Row {
                    spacing: s(10)
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    Text { 
                        text: "Hex"
                        color: Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.6)
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: s(13)
                        font.bold: true
                    }
                    
                    Rectangle {
                        width: s(120)
                        height: s(28)
                        color: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.05)
                        border.width: 1
                        border.color: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface1 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)
                        radius: s(6)
                        
                        TextInput {
                            id: hexInput
                            anchors.fill: parent
                            anchors.margins: s(4)
                            color: root.baseTextColor
                            text: root.currentColor.toString()
                            font.pixelSize: s(14)
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            onEditingFinished: {
                                root.currentColor = text;
                            }
                        }
                    }
                }
            }
        }

        // =========================================================
        // --- UI LAYER: SOLID MINIMALISTIC TOOLBAR
        // =========================================================
        Rectangle {
            id: toolbar
            z: 10
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: s(20)
            
            width: toolRow.width + s(32)
            height: s(48)
            radius: s(14)
            
            color: root.panelBgColor
            border.width: 1
            border.color: root.panelBorderColor

            Row {
                id: toolRow
                anchors.centerIn: parent
                spacing: s(16)

                // --- UNDO BUTTON ---
                Item {
                    width: s(32)
                    height: s(32)

                    Rectangle {
                        anchors.fill: parent
                        radius: s(14)
                        color: undoMouse.containsMouse && root.historyStep >= 0 ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        z: -1
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "\uF0E2" 
                        font.family: root.iconFont
                        font.pixelSize: s(14)
                        color: root.baseTextColor
                        opacity: root.historyStep >= 0 ? (undoMouse.pressed ? 0.5 : 1.0) : 0.3
                    }
                    MouseArea {
                        id: undoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.historyStep >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: { if (root.historyStep >= 0) root.undo() }
                    }
                }

                // --- REDO BUTTON ---
                Item {
                    width: s(32)
                    height: s(32)

                    Rectangle {
                        anchors.fill: parent
                        radius: s(14)
                        color: redoMouse.containsMouse && root.historyStep < root.actionHistory.length - 1 ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        z: -1
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "\uF01E" 
                        font.family: root.iconFont
                        font.pixelSize: s(14)
                        color: root.baseTextColor
                        opacity: root.historyStep < root.actionHistory.length - 1 ? (redoMouse.pressed ? 0.5 : 1.0) : 0.3
                    }
                    MouseArea {
                        id: redoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.historyStep < root.actionHistory.length - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: { if (root.historyStep < root.actionHistory.length - 1) root.redo() }
                    }
                }

                // --- SEPARATOR ---
                Rectangle {
                    width: 1
                    height: s(20)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.panelBorderColor
                }

                // --- DRAWING TOOLS W/ SMOOTH WORKSPACES HIGHLIGHT MORPHING ---
                Item {
                    width: toolsListLayout.width
                    height: s(32)

                    Rectangle {
                        id: toolsActiveHighlight
                        y: 0
                        height: s(32)
                        radius: s(14)
                        color: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface1 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.15)
                        z: 0

                        property int prevIdx: 0
                        property int curIdx: root.currentToolIndex

                        onCurIdxChanged: {
                            if (curIdx > prevIdx) { rightAnim.duration = 200; leftAnim.duration = 350; }
                            else if (curIdx < prevIdx) { leftAnim.duration = 200; rightAnim.duration = 350; }
                            prevIdx = curIdx;
                        }

                        property real stepSize: s(32) + s(8)
                        property real targetLeft: toolsListLayout.x + (curIdx * stepSize)
                        property real targetRight: targetLeft + s(32)

                        property real actualLeft: targetLeft
                        property real actualRight: targetRight

                        Behavior on actualLeft { NumberAnimation { id: leftAnim; duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on actualRight { NumberAnimation { id: rightAnim; duration: 250; easing.type: Easing.OutExpo } }

                        x: actualLeft
                        width: actualRight - actualLeft
                    }

                    Row {
                        id: toolsListLayout
                        anchors.left: parent.left
                        anchors.top: parent.top
                        spacing: s(8)
                        z: 1

                        Repeater {
                            model: [
                                { id: "mouse", icon: "\uF245", xOff: 0, yOff: 0 }, 
                                { id: "pen", icon: "\uF040", xOff: 0, yOff: 0 },   
                                { id: "brush", icon: "\uF1FC", xOff: -1, yOff: 0 }, 
                                { id: "fill", icon: "\uF576", xOff: -1, yOff: 0 },  
                                { id: "eraser", icon: "\uF12D", xOff: -1, yOff: 0 } 
                            ]
                            
                            Item {
                                width: s(32)
                                height: s(32)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: s(14)
                                    color: toolMouseArea.containsMouse && root.currentTool !== modelData.id ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.08)) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    z: -1
                                }

                                Text {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: s(modelData.xOff)
                                    anchors.verticalCenterOffset: s(modelData.yOff)
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    
                                    text: modelData.icon
                                    font.family: root.iconFont
                                    font.pixelSize: s(14)
                                    color: root.currentTool === modelData.id ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.mauve : "#cba6f7") : root.baseTextColor
                                    opacity: root.currentTool === modelData.id ? 1.0 : (toolMouseArea.containsMouse ? 0.8 : 0.5)
                                    Behavior on color { ColorAnimation { duration: 250 } }
                                }

                                MouseArea {
                                    id: toolMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.id === "pen") {
                                            if (root.currentTool === "pen") {
                                                root.showPenConfig = !root.showPenConfig;
                                            } else {
                                                root.currentTool = "pen";
                                                root.showPenConfig = true;
                                            }
                                        } else {
                                            root.currentTool = modelData.id;
                                            root.showPenConfig = false;
                                        }
                                        root.showColorPicker = false;
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: s(20)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.panelBorderColor
                }

                // --- COLOR INDICATOR ---
                Item {
                    width: s(32)
                    height: s(32)

                    Rectangle {
                        anchors.fill: parent
                        radius: s(14)
                        color: colorIndicatorMouse.containsMouse ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        z: -1
                    }

                    Rectangle {
                        width: s(22)
                        height: s(22)
                        radius: s(14)
                        color: root.currentColor
                        anchors.centerIn: parent
                        
                        border.width: root.currentTool !== "eraser" ? s(2) : 0
                        border.color: root.baseTextColor
                        opacity: (root.currentTool === "eraser" || root.currentTool === "mouse") ? 0.3 : 1.0
                    }
                    
                    MouseArea {
                        id: colorIndicatorMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.showColorPicker = !root.showColorPicker;
                            root.showPenConfig = false;
                            if (root.currentTool === "eraser" || root.currentTool === "mouse") {
                                root.currentTool = "pen";
                            }
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: s(20)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.panelBorderColor
                }

                // --- CLEAR CANVAS BUTTON ---
                Item {
                    width: s(32)
                    height: s(32)

                    Rectangle {
                        anchors.fill: parent
                        radius: s(14)
                        color: clearMouse.containsMouse ? (typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : Qt.rgba(root.baseTextColor.r, root.baseTextColor.g, root.baseTextColor.b, 0.1)) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        z: -1
                    }

                    Text {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "\uF1F8" // fa-trash
                        font.family: root.iconFont
                        color: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.red : "#f38ba8"
                        font.pixelSize: s(14)
                        opacity: clearMouse.pressed ? 0.5 : (clearMouse.containsMouse ? 1.0 : 0.7)
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.commitAction({ type: "clear" });
                            drawCanvas._clearPending = true;
                            drawCanvas.requestPaint();
                            root.showColorPicker = false;
                            root.showPenConfig = false;

                            zoomContainer.scale = 1.0;
                            zoomContainer.x = (cameraRig.width - zoomContainer.width) / 2;
                            zoomContainer.y = (cameraRig.height - zoomContainer.height) / 2;
                        }
                    }
                }
            }
        }
    }
}
