import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: root
    color: "transparent"

    WlrLayershell.namespace: "qs-screenshot-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    
    exclusionMode: ExclusionMode.Ignore 
    focusable: true
    screen: Quickshell.cursorScreen
    width: screen.width
    height: screen.height

    Scaler { id: scaler; currentWidth: width }
    function s(val) { return scaler.s(val); }
    
    MatugenColors { id: _theme }
    property color dimColor: Qt.alpha(_theme.crust, 0.75)
    property color selectionTint: Qt.alpha(_theme.mauve, 0.15)
    property color handleColor: _theme.base
    property color accentColor: _theme.mauve

    property bool isEditMode: Quickshell.env("QS_SCREENSHOT_EDIT") === "true"
    
    // Remember the video mode state
    property string cachedMode: {
        let val = Quickshell.env("QS_CACHED_MODE");
        return val ? val : "false";
    }
    property bool isVideoMode: cachedMode === "true"

    // Save mode instantly when toggled
    onIsVideoModeChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + (root.isVideoMode ? "true" : "false") + "' > ~/.cache/qs_screenshot_mode"]);
    }
    
    // Synchronous Cache Loading
    property string cachedGeom: {
        let val = Quickshell.env("QS_CACHED_GEOM");
        return val ? val : "";
    }
    property var cachedParts: cachedGeom.trim() !== "" ? cachedGeom.trim().split(",") : []
    property bool hasValidCache: cachedParts.length === 4 && parseFloat(cachedParts[2]) > 10

    // Core geometry state 
    property real startX: hasValidCache ? parseFloat(cachedParts[0]) : 0
    property real startY: hasValidCache ? parseFloat(cachedParts[1]) : 0
    property real endX: hasValidCache ? (parseFloat(cachedParts[0]) + parseFloat(cachedParts[2])) : 0
    property real endY: hasValidCache ? (parseFloat(cachedParts[1]) + parseFloat(cachedParts[3])) : 0
    
    property bool hasSelection: hasValidCache
    property bool isSelecting: false

    // Maximization State Tracking
    property bool isMaximized: false
    property real preStartX: 0
    property real preStartY: 0
    property real preEndX: 0
    property real preEndY: 0

    property real selX: Math.min(startX, endX)
    property real selY: Math.min(startY, endY)
    property real selW: Math.abs(endX - startX)
    property real selH: Math.abs(endY - startY)
    
    property string geometryString: `${Math.round(selX)},${Math.round(selY)} ${Math.round(selW)}x${Math.round(selH)}`

    property int interactionMode: 0
    property real anchorX: 0
    property real anchorY: 0
    property real initX: 0
    property real initY: 0
    property real initW: 0
    property real initH: 0

    function saveCache() {
        if (root.hasSelection) {
            let data = Math.round(root.selX) + "," + Math.round(root.selY) + "," + Math.round(root.selW) + "," + Math.round(root.selH);
            Quickshell.execDetached(["bash", "-c", "echo '" + data + "' > ~/.cache/qs_screenshot_geom"]);
        }
    }

    // Smooth Maximize Animation
    ParallelAnimation {
        id: maximizeAnim
        property real targetStartX
        property real targetStartY
        property real targetEndX
        property real targetEndY

        NumberAnimation { target: root; property: "startX"; to: maximizeAnim.targetStartX; duration: 250; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "startY"; to: maximizeAnim.targetStartY; duration: 250; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "endX"; to: maximizeAnim.targetEndX; duration: 250; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "endY"; to: maximizeAnim.targetEndY; duration: 250; easing.type: Easing.InOutQuad }
        
        onFinished: {
            root.saveCache()
        }
    }

    function toggleMaximize() {
        if (!isMaximized) {
            preStartX = root.startX; preStartY = root.startY;
            preEndX = root.endX; preEndY = root.endY;
            
            maximizeAnim.targetStartX = 0; 
            maximizeAnim.targetStartY = 0;
            maximizeAnim.targetEndX = root.width; 
            maximizeAnim.targetEndY = root.height;
            isMaximized = true;
        } else {
            maximizeAnim.targetStartX = preStartX; 
            maximizeAnim.targetStartY = preStartY;
            maximizeAnim.targetEndX = preEndX; 
            maximizeAnim.targetEndY = preEndY;
            isMaximized = false;
        }
        maximizeAnim.restart();
    }

    // Keyboard Shortcuts
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
    Shortcut { 
        sequence: "Return"
        onActivated: {
            if (root.hasSelection) root.executeCapture(root.isEditMode && !root.isVideoMode, root.isVideoMode)
        }
    }

    // --- The Dimming Mask ---
    Item {
        anchors.fill: parent
        z: 1
        
        Rectangle {
            anchors.fill: parent
            color: root.dimColor
            opacity: (!root.isSelecting && !root.hasSelection) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            
            Text {
                anchors.centerIn: parent
                text: root.isVideoMode ? "Select region to record" : "Select region to capture"
                font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: s(24)
                color: _theme.text
            }
        }

        Item {
            anchors.fill: parent
            opacity: (root.isSelecting || root.hasSelection) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Rectangle { x: 0; y: 0; width: parent.width; height: root.selY; color: root.dimColor } 
            Rectangle { x: 0; y: root.selY + root.selH; width: parent.width; height: parent.height - (root.selY + root.selH); color: root.dimColor }
            Rectangle { x: 0; y: root.selY; width: root.selX; height: root.selH; color: root.dimColor } 
            Rectangle { x: root.selX + root.selW; y: root.selY; width: parent.width - (root.selX + root.selW); height: root.selH; color: root.dimColor } 
        }
    }

    // --- Edge Outlines (Z: 5) ---
    Rectangle {
        visible: root.isSelecting || root.hasSelection
        x: root.selX; y: root.selY; width: root.selW; height: root.selH
        color: root.isVideoMode ? Qt.alpha(_theme.red, 0.15) : root.selectionTint
        border.color: root.isVideoMode ? _theme.red : root.accentColor
        border.width: s(4)
        z: 5
    }

    // --- Visual Resize Handles (Z: 10) ---
    component Handle: Rectangle {
        width: s(20); height: s(20); radius: s(10)
        color: root.handleColor
        border.color: root.isVideoMode ? _theme.red : root.accentColor
        border.width: s(4)
        visible: root.hasSelection || root.isSelecting
        z: 10
    }

    // Centered exactly on the selection corners
    Handle { x: root.selX - width / 2; y: root.selY - height / 2 } 
    Handle { x: root.selX + root.selW - width / 2; y: root.selY - height / 2 } 
    Handle { x: root.selX - width / 2; y: root.selY + root.selH - height / 2 } 
    Handle { x: root.selX + root.selW - width / 2; y: root.selY + root.selH - height / 2 } 

    // --- Master Interaction Area ---
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 20 

        function getInteractionMode(mx, my, mods) {
            if (!root.hasSelection) return 1; 
            if (mods & Qt.ShiftModifier) return 2; 

            let margin = s(20) 
            let inBox = mx >= root.selX && mx <= root.selX + root.selW && my >= root.selY && my <= root.selY + root.selH
            
            let onLeft = Math.abs(mx - root.selX) <= margin
            let onRight = Math.abs(mx - (root.selX + root.selW)) <= margin
            let onTop = Math.abs(my - root.selY) <= margin
            let onBottom = Math.abs(my - (root.selY + root.selH)) <= margin

            if (onTop && onLeft) return 3;
            if (onTop && onRight) return 5;
            if (onBottom && onLeft) return 8;
            if (onBottom && onRight) return 10;
            if (onTop) return 4;
            if (onBottom) return 9;
            if (onLeft) return 6;
            if (onRight) return 7;

            if (inBox) return 2;
            return 1;
        }

        onPositionChanged: (mouse) => {
            let mode = root.isSelecting ? root.interactionMode : getInteractionMode(mouse.x, mouse.y, mouse.modifiers)
            
            switch(mode) {
                case 2: cursorShape = Qt.ClosedHandCursor; break;
                case 3: case 10: cursorShape = Qt.SizeFDiagCursor; break;
                case 5: case 8: cursorShape = Qt.SizeBDiagCursor; break;
                case 4: case 9: cursorShape = Qt.SizeVerCursor; break;
                case 6: case 7: cursorShape = Qt.SizeHorCursor; break;
                default: cursorShape = Qt.CrossCursor; break;
            }

            if (!root.isSelecting) return;

            let dx = mouse.x - root.anchorX
            let dy = mouse.y - root.anchorY
            let clamp = (val, min, max) => Math.max(min, Math.min(max, val))

            if (root.interactionMode === 1) { 
                root.endX = clamp(mouse.x, 0, root.width)
                root.endY = clamp(mouse.y, 0, root.height)
            } else if (root.interactionMode === 2) { 
                let targetX = clamp(root.initX + dx, 0, root.width - root.initW)
                let targetY = clamp(root.initY + dy, 0, root.height - root.initH)
                root.startX = targetX; root.startY = targetY;
                root.endX = targetX + root.initW; root.endY = targetY + root.initH;
            } else { 
                let nx = root.initX, ny = root.initY, nw = root.initW, nh = root.initH

                if ([3, 6, 8].includes(root.interactionMode)) {
                    nx = clamp(root.initX + dx, 0, root.initX + root.initW - 10)
                    nw = root.initW + (root.initX - nx)
                }
                if ([5, 7, 10].includes(root.interactionMode)) { nw = clamp(root.initW + dx, 10, root.width - root.initX) }
                if ([3, 4, 5].includes(root.interactionMode)) {
                    ny = clamp(root.initY + dy, 0, root.initY + root.initH - 10)
                    nh = root.initH + (root.initY - ny)
                }
                if ([8, 9, 10].includes(root.interactionMode)) { nh = clamp(root.initH + dy, 10, root.height - root.initY) }

                root.startX = nx; root.startY = ny; 
                root.endX = nx + nw; root.endY = ny + nh;
            }
        }

        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) { Qt.quit(); return; }
            
            maximizeAnim.stop() // Halt expansion explicitly if clicking mid-animation
            
            root.interactionMode = getInteractionMode(mouse.x, mouse.y, mouse.modifiers)
            root.isSelecting = true
            
            // Breaking maximization state if user interacts manually
            if (root.interactionMode !== 1) root.isMaximized = false;
            
            root.anchorX = mouse.x; root.anchorY = mouse.y
            root.initX = root.selX; root.initY = root.selY; root.initW = root.selW; root.initH = root.selH;

            if (root.interactionMode === 1) {
                let clamp = (val, min, max) => Math.max(min, Math.min(max, val))
                let clampedX = clamp(mouse.x, 0, root.width)
                let clampedY = clamp(mouse.y, 0, root.height)
                
                root.startX = clampedX; root.startY = clampedY; 
                root.endX = clampedX; root.endY = clampedY;
                root.hasSelection = false
                root.isMaximized = false
            }
        }

        onReleased: {
            if (root.isSelecting) {
                root.isSelecting = false
                if (root.selW > 10 && root.selH > 10) {
                    root.hasSelection = true
                    root.saveCache()
                    
                    if (root.isEditMode && !root.isVideoMode && root.interactionMode === 1) {
                        root.executeCapture(true, false)
                    }
                } else {
                    root.hasSelection = false
                }
            }
        }
    }

    // --- GNOME-Style Mode Toolbar (Z: 30) ---
    Rectangle {
        id: toolbar
        z: 30 
        
        // Smart Position Math
        property bool fitsOutsideBottom: (root.selY + root.selH + height + s(15)) <= root.height
        property bool fitsOutsideTop: (root.selY - height - s(15)) >= 0
        property bool fitsInside: root.selH >= (height + s(30)) && root.selW >= (width + s(20))

        // Only visible if it mathematically fits somewhere (otherwise disappears)
        visible: root.hasSelection && !root.isSelecting && (fitsOutsideBottom || fitsOutsideTop || fitsInside)

        // Center horizontally bounded by screen edges
        x: Math.max(s(10), Math.min(parent.width - width - s(10), root.selX + (root.selW / 2) - (width / 2)))
        
        // Waterfall logic: Outside Bottom -> Outside Top -> Inside Bottom
        y: fitsOutsideBottom ? (root.selY + root.selH + s(15)) : 
          (fitsOutsideTop ? (root.selY - height - s(15)) : 
          (root.selY + root.selH - height - s(15)))

        width: toolbarLayout.width + s(16)
        height: s(52)
        radius: s(26)
        
        color: _theme.base
        border.color: _theme.surface1
        border.width: s(2)

        RowLayout {
            id: toolbarLayout
            anchors.centerIn: parent
            spacing: s(8)

            // --- Photo / Video Switcher ---
            Rectangle {
                width: s(80); height: s(36); radius: s(18)
                color: _theme.surface0
                
                RowLayout {
                    anchors.fill: parent; anchors.margins: s(4); spacing: 0
                    
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: s(14)
                        color: !root.isVideoMode ? _theme.surface2 : "transparent"
                        Behavior on color { ColorAnimation { duration: 200 } }
                        
                        Text { anchors.centerIn: parent; font.family: "Iosevka Nerd Font"; text: "󰄄"; color: !root.isVideoMode ? _theme.text : _theme.subtext0; font.pixelSize: s(16) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.isVideoMode = false }
                    }
                    
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: s(14)
                        color: root.isVideoMode ? _theme.surface2 : "transparent"
                        Behavior on color { ColorAnimation { duration: 200 } }
                        
                        Text { anchors.centerIn: parent; font.family: "Iosevka Nerd Font"; text: ""; color: root.isVideoMode ? _theme.text : _theme.subtext0; font.pixelSize: s(16) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.isVideoMode = true }
                    }
                }
            }

            Rectangle { width: s(2); Layout.fillHeight: true; Layout.topMargin: s(10); Layout.bottomMargin: s(10); color: _theme.surface0; radius: s(1) }

            component ToolbarBtn: Rectangle {
                property string iconTxt: ""
                property string label: ""
                property bool isDanger: false
                signal clicked()

                Layout.preferredHeight: s(36)
                Layout.preferredWidth: label !== "" ? (txt.implicitWidth + s(36)) : s(36)
                radius: s(18)
                color: ma.containsMouse ? (isDanger ? Qt.alpha(_theme.red, 0.2) : _theme.surface0) : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: s(6)
                    Text { font.family: "Iosevka Nerd Font"; text: parent.parent.iconTxt; color: parent.parent.isDanger ? _theme.red : _theme.text; font.pixelSize: s(18) }
                    Text { id: txt; visible: parent.parent.label !== ""; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; text: parent.parent.label; color: parent.parent.isDanger ? _theme.red : _theme.text; font.pixelSize: s(13) }
                }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
            }

            // Controls
            ToolbarBtn { visible: !root.isVideoMode; iconTxt: "󰄄"; label: "Capture"; onClicked: root.executeCapture(false, false) }
            ToolbarBtn { visible: !root.isVideoMode; iconTxt: "󰏫"; label: "Edit"; onClicked: root.executeCapture(true, false) }
            ToolbarBtn { visible: root.isVideoMode; iconTxt: "󰑊"; label: "Record"; isDanger: true; onClicked: root.executeCapture(false, true) }

            Rectangle { width: s(2); Layout.fillHeight: true; Layout.topMargin: s(10); Layout.bottomMargin: s(10); color: _theme.surface0; radius: s(1) }
            
            // Fullscreen / Window Toggle
            ToolbarBtn { iconTxt: root.isMaximized ? "" : ""; onClicked: root.toggleMaximize() }
            ToolbarBtn { iconTxt: "󰅖"; isDanger: true; onClicked: Qt.quit() }
        }
    }

    function executeCapture(openEditor, isRecord) {
        let cmd = `bash ~/.config/hypr/scripts/screenshot.sh --geometry "${root.geometryString}"`
        if (isRecord) cmd += " --record"
        if (openEditor) cmd += " --edit"
        Quickshell.execDetached(["bash", "-c", cmd])
        Qt.quit() 
    }
}
