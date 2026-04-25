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
    property color dimColor: Qt.alpha(_theme.crust, 0.50)
    property color selectionTint: Qt.alpha(_theme.mauve, 0.05)
    property color handleColor: _theme.text
    property color accentColor: _theme.mauve

    property bool isEditMode: Quickshell.env("QS_SCREENSHOT_EDIT") === "true"
    
    property string cachedMode: Quickshell.env("QS_CACHED_MODE") || "false"
    property bool isVideoMode: cachedMode === "true"

    onIsVideoModeChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + (root.isVideoMode ? "true" : "false") + "' > ~/.cache/qs_screenshot_mode"]);
        
        // Smart Geometry Snapping for Portal Support
        if (root.isVideoMode) {
            root.preStartX = root.startX; 
            root.preStartY = root.startY;
            root.preEndX = root.endX; 
            root.preEndY = root.endY;
            
            root.startX = 0; 
            root.startY = 0; 
            root.endX = root.width; 
            root.endY = root.height;
            root.hasSelection = true;
        } else {
            root.startX = root.preStartX; 
            root.startY = root.preStartY;
            root.endX = root.preEndX; 
            root.endY = root.preEndY;
            
            if (Math.abs(root.endX - root.startX) < 10 || Math.abs(root.endY - root.startY) < 10) {
                root.hasSelection = false;
            }
        }
    }
    
    // --- Audio State Persistence ---
    property real deskVol: Quickshell.env("QS_DESK_VOL") ? parseFloat(Quickshell.env("QS_DESK_VOL")) : 1.0
    property bool deskMute: Quickshell.env("QS_DESK_MUTE") === "true"
    property real micVol: Quickshell.env("QS_MIC_VOL") ? parseFloat(Quickshell.env("QS_MIC_VOL")) : 1.0
    property bool micMute: Quickshell.env("QS_MIC_MUTE") === "true"
    property string micDevice: Quickshell.env("QS_MIC_DEV") || ""

    function saveAudioPrefs() {
        let data = `${deskVol},${deskMute},${micVol},${micMute},${micDevice}`
        Quickshell.execDetached(["bash", "-c", `echo '${data}' > ~/.cache/qs_audio_prefs`])
    }

    // --- Dynamic Mic Loader ---
    ListModel { id: micModel }
    
    Component.onCompleted: {
        let micData = Quickshell.env("QS_MIC_LIST") || ""
        if (micData.trim() !== "") {
            let lines = micData.trim().split('\n')
            for (let line of lines) {
                let parts = line.split('|')
                if (parts.length >= 2) {
                    micModel.append({ devName: parts[0], devDesc: parts.slice(1).join('|') })
                }
            }
        }
        
        if (root.micDevice === "" && micModel.count > 0) {
            root.micDevice = micModel.get(0).devName
            saveAudioPrefs()
        }
    }

    // --- Geometry State ---
    property string cachedGeom: Quickshell.env("QS_CACHED_GEOM") || ""
    property var cachedParts: cachedGeom.trim() !== "" ? cachedGeom.trim().split(",") : []
    property bool hasValidCache: cachedParts.length === 4 && parseFloat(cachedParts[2]) > 10

    property real startX: hasValidCache ? parseFloat(cachedParts[0]) : 0
    property real startY: hasValidCache ? parseFloat(cachedParts[1]) : 0
    property real endX: hasValidCache ? (parseFloat(cachedParts[0]) + parseFloat(cachedParts[2])) : 0
    property real endY: hasValidCache ? (parseFloat(cachedParts[1]) + parseFloat(cachedParts[3])) : 0
    
    // Fluid Geometry Snapping
    Behavior on startX { enabled: !root.isSelecting; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
    Behavior on startY { enabled: !root.isSelecting; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
    Behavior on endX { enabled: !root.isSelecting; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
    Behavior on endY { enabled: !root.isSelecting; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

    property bool hasSelection: hasValidCache
    property bool isSelecting: false
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
    property real anchorX: 0; property real anchorY: 0
    property real initX: 0; property real initY: 0
    property real initW: 0; property real initH: 0

    // --- QR Scanner State ---
    property bool isScanningQr: false
    property bool showQrPopup: false
    property bool isQrSuccess: false
    ListModel { id: qrModel }

    function saveCache() {
        if (root.hasSelection && !root.isVideoMode) {
            let data = Math.round(root.selX) + "," + Math.round(root.selY) + "," + Math.round(root.selW) + "," + Math.round(root.selH);
            Quickshell.execDetached(["bash", "-c", "echo '" + data + "' > ~/.cache/qs_screenshot_geom"]);
        }
    }

    ParallelAnimation {
        id: maximizeAnim
        property real targetStartX; property real targetStartY
        property real targetEndX; property real targetEndY

        NumberAnimation { target: root; property: "startX"; to: maximizeAnim.targetStartX; duration: 250; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "startY"; to: maximizeAnim.targetStartY; duration: 250; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "endX"; to: maximizeAnim.targetEndX; duration: 250; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "endY"; to: maximizeAnim.targetEndY; duration: 250; easing.type: Easing.InOutQuad }
        onFinished: root.saveCache()
    }

    function toggleMaximize() {
        if (root.isVideoMode) return;
        if (!isMaximized) {
            preStartX = root.startX; preStartY = root.startY;
            preEndX = root.endX; preEndY = root.endY;
            maximizeAnim.targetStartX = 0; maximizeAnim.targetStartY = 0;
            maximizeAnim.targetEndX = root.width; maximizeAnim.targetEndY = root.height;
            isMaximized = true;
        } else {
            maximizeAnim.targetStartX = preStartX; maximizeAnim.targetStartY = preStartY;
            maximizeAnim.targetEndX = preEndX; maximizeAnim.targetEndY = preEndY;
            isMaximized = false;
        }
        maximizeAnim.restart();
    }

    // --- Keyboard Shortcuts ---
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
    Shortcut { sequence: "Return"; onActivated: { if (root.hasSelection) root.executeCapture(root.isEditMode && !root.isVideoMode, root.isVideoMode) } }
    Shortcut { sequence: "Tab"; onActivated: root.isVideoMode = !root.isVideoMode }
    Shortcut { sequence: "Left"; onActivated: root.isVideoMode = false }
    Shortcut { sequence: "Right"; onActivated: root.isVideoMode = true }
    Shortcut { sequence: "F11"; onActivated: root.toggleMaximize() }

    // --- Animated Revealer for Fluid Transitions ---
    component AnimWrap: Item {
        property bool isShown: false
        property real contentWidth: 0
        property real rightPadding: s(3) // Reducción de padding lateral para los íconos
        property real targetWidth: contentWidth + rightPadding
        
        width: isShown ? targetWidth : 0
        height: parent.height
        opacity: isShown ? 1.0 : 0.0
        clip: true
        
        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutQuart } }
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuart } }
        
        default property alias content: internalWrapper.children
        Item { 
            id: internalWrapper
            width: contentWidth 
            height: parent.height 
        }
    }

    // --- Global Reusable Toolbar Button (Matte Edition) ---
    component ToolbarBtn: Rectangle {
        id: tBtn
        property string iconTxt: ""
        property string label: ""
        property bool isDanger: false
        signal clicked()

        height: s(36)
        width: label !== "" ? (txt.implicitWidth + s(36)) : s(36)
        radius: s(18)
        
        // Idle is a solid base color, full matte filled-look
        color: tBtn.isDanger ? _theme.red : (maBtn.containsMouse ? _theme.surface1 : _theme.surface0)
        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            anchors.centerIn: parent; spacing: s(6)
            Text { 
                font.family: "Iosevka Nerd Font"
                text: tBtn.iconTxt
                color: tBtn.isDanger ? _theme.crust : _theme.text
                font.pixelSize: s(18) 
            }
            Text { 
                id: txt
                visible: tBtn.label !== ""
                font.family: "JetBrains Mono"
                font.weight: Font.DemiBold
                text: tBtn.label
                color: tBtn.isDanger ? _theme.crust : _theme.text
                font.pixelSize: s(13) 
            }
        }
        MouseArea { 
            id: maBtn
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tBtn.clicked() 
        }
    }

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
                text: root.isVideoMode ? "Click Record (Portal handles area selection)" : "Select region to capture"
                font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: s(24); color: _theme.text
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

    Rectangle {
        visible: root.isSelecting || root.hasSelection
        x: root.selX; y: root.selY; width: root.selW; height: root.selH
        color: (root.showQrPopup && root.isQrSuccess) ? Qt.alpha(_theme.green, 0.15) : (root.isVideoMode ? Qt.alpha(_theme.red, 0.05) : root.selectionTint)
        border.color: (root.showQrPopup && root.isQrSuccess) ? _theme.green : (root.isVideoMode ? _theme.red : root.accentColor)
        border.width: s(4)
        z: 5
    }

    Repeater {
        model: qrModel
        delegate: Rectangle {
            visible: opacity > 0
            opacity: (root.showQrPopup && model.qSuccess && model.qW > 0) ? 1.0 : 0.0
            property real pad: (root.showQrPopup && model.qSuccess) ? s(5) : 0
            x: model.qW > 0 ? (model.qX - pad) : model.qX
            y: model.qH > 0 ? (model.qY - pad) : model.qY
            width: model.qW > 0 ? (model.qW + (pad * 2)) : 0
            height: model.qH > 0 ? (model.qH + (pad * 2)) : 0
            color: Qt.alpha(_theme.green, 0.25)
            border.color: _theme.green
            border.width: s(3)
            radius: s(8)
            z: 34
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
            Behavior on pad { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
        }
    }

    component Handle: Rectangle {
        width: s(20); height: s(20); radius: s(10)
        color: root.handleColor; border.color: root.accentColor; border.width: s(4)
        visible: (root.hasSelection || root.isSelecting) && !root.isScanningQr && !root.showQrPopup && !root.isVideoMode; z: 10
    }
    Handle { x: root.selX - width / 2; y: root.selY - height / 2 } 
    Handle { x: root.selX + root.selW - width / 2; y: root.selY - height / 2 } 
    Handle { x: root.selX - width / 2; y: root.selY + root.selH - height / 2 } 
    Handle { x: root.selX + root.selW - width / 2; y: root.selY + root.selH - height / 2 } 

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 20 

        function getInteractionMode(mx, my, mods) {
            if (!root.hasSelection) return 1; 
            if (mods & Qt.ShiftModifier) return 2; 
            let margin = s(20) 
            let onLeftLine = Math.abs(mx - root.selX) <= margin; 
            let onRightLine = Math.abs(mx - (root.selX + root.selW)) <= margin
            let onTopLine = Math.abs(my - root.selY) <= margin; 
            let onBottomLine = Math.abs(my - (root.selY + root.selH)) <= margin
            let withinX = mx >= (root.selX - margin) && mx <= (root.selX + root.selW + margin);
            let withinY = my >= (root.selY - margin) && my <= (root.selY + root.selH + margin);

            if (onTopLine && onLeftLine) return 3; 
            if (onTopLine && onRightLine) return 5;
            if (onBottomLine && onLeftLine) return 8; 
            if (onBottomLine && onRightLine) return 10;
            if (onTopLine && withinX) return 4; 
            if (onBottomLine && withinX) return 9;
            if (onLeftLine && withinY) return 6; 
            if (onRightLine && withinY) return 7;
            return 1;
        }

        onPositionChanged: (mouse) => {
            if (root.isVideoMode) { cursorShape = Qt.ArrowCursor; return; }
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
            let dx = mouse.x - root.anchorX; let dy = mouse.y - root.anchorY
            let clamp = (val, min, max) => Math.max(min, Math.min(max, val))

            if (root.interactionMode === 1) { 
                root.endX = clamp(mouse.x, 0, root.width); root.endY = clamp(mouse.y, 0, root.height)
            } else if (root.interactionMode === 2) { 
                let targetX = clamp(root.initX + dx, 0, root.width - root.initW); let targetY = clamp(root.initY + dy, 0, root.height - root.initH)
                root.startX = targetX; root.startY = targetY; root.endX = targetX + root.initW; root.endY = targetY + root.initH;
            } else { 
                let nx = root.initX, ny = root.initY, nw = root.initW, nh = root.initH
                if ([3, 6, 8].includes(root.interactionMode)) { nx = clamp(root.initX + dx, 0, root.initX + root.initW - 10); nw = root.initW + (root.initX - nx) }
                if ([5, 7, 10].includes(root.interactionMode)) { nw = clamp(root.initW + dx, 10, root.width - root.initX) }
                if ([3, 4, 5].includes(root.interactionMode)) { ny = clamp(root.initY + dy, 0, root.initY + root.initH - 10); nh = root.initH + (root.initY - ny) }
                if ([8, 9, 10].includes(root.interactionMode)) { nh = clamp(root.initH + dy, 10, root.height - root.initY) }
                root.startX = nx; root.startY = ny; root.endX = nx + nw; root.endY = ny + nh;
            }
        }

        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) { Qt.quit(); return; }
            if (root.isVideoMode) return; 

            root.isScanningQr = false;
            root.showQrPopup = false;
            qrWaitTimer.stop();

            maximizeAnim.stop() 
            root.interactionMode = getInteractionMode(mouse.x, mouse.y, mouse.modifiers)
            root.isSelecting = true
            if (root.interactionMode !== 1) root.isMaximized = false;
            root.anchorX = mouse.x; root.anchorY = mouse.y
            root.initX = root.selX; root.initY = root.selY; root.initW = root.selW; root.initH = root.selH;

            if (root.interactionMode === 1) {
                let clamp = (val, min, max) => Math.max(min, Math.min(max, val))
                let clampedX = clamp(mouse.x, 0, root.width); let clampedY = clamp(mouse.y, 0, root.height)
                root.startX = clampedX; root.startY = clampedY; root.endX = clampedX; root.endY = clampedY;
                root.hasSelection = false; root.isMaximized = false
            }
        }

        onReleased: {
            if (root.isSelecting) {
                root.isSelecting = false
                if (root.selW > 10 && root.selH > 10) {
                    root.hasSelection = true; root.saveCache()
                } else { root.hasSelection = false }
            }
        }
    }

    // --- Main Bottom Toolbar (Smooth Matte Rounded Rect) ---
    Item {
        id: toolbar
        z: 30 
        
        // Fully expanded total height
        property real totalHeight: s(120)
        property bool fitsOutsideBottom: (root.selY + root.selH + totalHeight + s(15)) <= root.height

        visible: root.hasSelection && !root.isSelecting && !root.isScanningQr && !root.showQrPopup
        
        width: Math.max(toolbarRow.width + s(64), s(340))
        height: totalHeight 

        x: Math.max(s(10), Math.min(parent.width - width - s(10), root.selX + (root.selW / 2) - (width / 2)))
        y: fitsOutsideBottom ? (root.selY + root.selH + s(15)) : 
           ((root.selY - height - s(15)) >= 0 ? (root.selY - height - s(15)) : (root.height - height - s(15)))

        // The Smooth Translucent Matte Background
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(_theme.base.r, _theme.base.g, _theme.base.b, 0.85)
            border.color: Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.08)
            border.width: s(1)
            radius: s(24)
        }

        component AudioControl: RowLayout {
            property string iconOn: ""
            property string iconOff: ""
            property real volumeValue: 1.0
            property bool mutedValue: false
            property bool hasDropdown: false
            
            signal volumeUpdate(real newVol)
            signal muteUpdate(bool newMute)
            signal dropdownClicked()

            spacing: s(4)

            Rectangle {
                width: s(30); height: s(30); radius: s(15)
                // Filled, solid matte-look on idle
                color: maIcon.containsMouse ? _theme.surface2 : _theme.surface0
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    font.family: "Iosevka Nerd Font"
                    text: parent.parent.mutedValue ? parent.parent.iconOff : parent.parent.iconOn
                    color: parent.parent.mutedValue ? _theme.red : _theme.text
                    font.pixelSize: s(16)
                }
                MouseArea {
                    id: maIcon; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: parent.parent.muteUpdate(!parent.parent.mutedValue)
                }
            }

            Slider {
                Layout.preferredWidth: s(60)
                from: 0.0; to: 1.0; value: parent.volumeValue
                onValueChanged: parent.volumeUpdate(value)

                background: Rectangle {
                    x: parent.leftPadding; y: parent.topPadding + parent.availableHeight / 2 - height / 2
                    implicitWidth: s(60); implicitHeight: s(4)
                    width: parent.availableWidth; height: implicitHeight
                    radius: s(2)
                    color: _theme.surface2
                    Rectangle { width: parent.parent.visualPosition * parent.width; height: parent.height; color: parent.parent.parent.mutedValue ? _theme.subtext0 : _theme.mauve; radius: s(2) }
                }
                handle: Rectangle {
                    x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                    y: parent.topPadding + parent.availableHeight / 2 - height / 2
                    implicitWidth: s(12); implicitHeight: s(12); radius: s(6)
                    color: parent.parent.parent.mutedValue ? _theme.subtext0 : _theme.mauve
                }
            }

            Rectangle {
                visible: parent.hasDropdown
                width: s(20); height: s(30); color: "transparent"
                Text {
                    anchors.centerIn: parent
                    font.family: "Iosevka Nerd Font"
                    // Correcting dropdown icon orientation base on position relative to fitsOutsideBottom
                    text: toolbar.fitsOutsideBottom ? "󰅃" : "󰅀" 
                    color: _theme.text
                    font.pixelSize: s(16)
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.parent.dropdownClicked() }
            }
        }

        Rectangle {
            id: micDropdown
            visible: false
            width: s(280)
            height: micModel.count === 0 ? s(40) : Math.min(s(180), micModel.count * s(36))
            x: -s(140) 
            // Correcting dropdown positioning
            y: toolbar.fitsOutsideBottom ? (toolbar.height + s(8)) : (-height - s(8))
            color: Qt.rgba(_theme.base.r, _theme.base.g, _theme.base.b, 0.95)
            border.color: Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.08)
            border.width: s(1)
            radius: s(12)
            z: 50

            Text {
                visible: micModel.count === 0
                anchors.centerIn: parent
                text: "No Microphones (Install pulseaudio)"
                color: _theme.subtext0
                font.pixelSize: s(12)
            }

            ListView {
                visible: micModel.count > 0
                anchors.fill: parent; anchors.margins: s(4)
                model: micModel
                clip: true
                delegate: Rectangle {
                    width: ListView.view.width; height: s(32); radius: s(6)
                    color: maList.containsMouse ? _theme.surface0 : "transparent"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: s(6)
                        Text { text: model.devDesc; color: root.micDevice === model.devName ? _theme.mauve : _theme.text; font.pixelSize: s(12); elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    MouseArea { 
                        id: maList; anchors.fill: parent; hoverEnabled: true; 
                        onClicked: { root.micDevice = model.devName; root.saveAudioPrefs(); micDropdown.visible = false } 
                    }
                }
            }
        }

        // Top Content: The Action Tools
        Row {
            id: toolbarRow
            anchors.top: parent.top
            anchors.topMargin: s(12)
            anchors.horizontalCenter: parent.horizontalCenter
            height: root.s(36)
            spacing: 0

            // Tab Switcher with Morphing Animation (Stretchy Mauve Pill)
            Item {
                // Width is slightly bigger to handle reducced icon padding on right
                width: s(110) + s(3); height: parent.height
                
                Rectangle {
                    width: s(110); height: s(36); radius: s(18) 
                    color: _theme.surface0
                    
                    Rectangle {
                        id: activeHighlight
                        y: s(2)
                        height: parent.height - s(4)
                        radius: s(16) 
                        color: _theme.mauve
                        z: 0

                        property bool curVideoMode: root.isVideoMode
                        onCurVideoModeChanged: {
                            // Morph duration/easing when going right vs left
                            if (curVideoMode) { // Moving right
                                rightAnim.duration = 200; leftAnim.duration = 350;
                            } else { // Moving left
                                leftAnim.duration = 200; rightAnim.duration = 350;
                            }
                        }

                        property real targetLeft: curVideoMode ? (parent.width / 2) : s(2)
                        property real targetRight: targetLeft + (parent.width / 2) - s(2)

                        property real actualLeft: targetLeft
                        property real actualRight: targetRight

                        Behavior on actualLeft { NumberAnimation { id: leftAnim; duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on actualRight { NumberAnimation { id: rightAnim; duration: 250; easing.type: Easing.OutExpo } }

                        x: actualLeft
                        width: actualRight - actualLeft
                    }
                    
                    Row {
                        anchors.fill: parent
                        z: 1
                        Item {
                            width: parent.width / 2; height: parent.height
                            Text { anchors.centerIn: parent; font.family: "Iosevka Nerd Font"; text: "󰄄"; color: !root.isVideoMode ? _theme.crust : _theme.text; font.pixelSize: s(16) }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.isVideoMode = false }
                        }
                        Item {
                            width: parent.width / 2; height: parent.height
                            Text { anchors.centerIn: parent; font.family: "Iosevka Nerd Font"; text: ""; color: root.isVideoMode ? _theme.crust : _theme.text; font.pixelSize: s(16) }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.isVideoMode = true }
                        }
                    }
                }
            }

            // Video Controls
            AnimWrap {
                isShown: root.isVideoMode; contentWidth: s(2)
                Rectangle { width: s(2); height: s(16); anchors.verticalCenter: parent.verticalCenter; color: _theme.surface0; radius: s(1) }
            }

            AnimWrap {
                isShown: root.isVideoMode; contentWidth: s(94)
                AudioControl { 
                    id: deskAudio; width: parent.width; height: parent.height
                    iconOn: "󰓃"; iconOff: "󰓄" 
                    volumeValue: root.deskVol; mutedValue: root.deskMute
                    onVolumeUpdate: (v) => { root.deskVol = v; root.saveAudioPrefs() }
                    onMuteUpdate: (m) => { root.deskMute = m; root.saveAudioPrefs() }
                }
            }
            
            AnimWrap {
                isShown: root.isVideoMode; contentWidth: s(118)
                AudioControl { 
                    id: micAudio; width: parent.width; height: parent.height
                    iconOn: "󰍬"; iconOff: "󰍭"; hasDropdown: true
                    volumeValue: root.micVol; mutedValue: root.micMute
                    onVolumeUpdate: (v) => { root.micVol = v; root.saveAudioPrefs() }
                    onMuteUpdate: (m) => { root.micMute = m; root.saveAudioPrefs() }
                    onDropdownClicked: { micDropdown.visible = !micDropdown.visible; micDropdown.x = mapToItem(toolbar, 0, 0).x - s(120) }
                }
            }

            // Image Controls
            AnimWrap {
                isShown: !root.isVideoMode; contentWidth: s(2)
                Rectangle { width: s(2); height: s(16); anchors.verticalCenter: parent.verticalCenter; color: _theme.surface0; radius: s(1) }
            }

            AnimWrap {
                isShown: !root.isVideoMode; contentWidth: s(36)
                ToolbarBtn { iconTxt: "󰏫"; onClicked: root.executeCapture(true, false) }
            }

            AnimWrap {
                isShown: !root.isVideoMode; contentWidth: s(36)
                ToolbarBtn { iconTxt: "⿻"; onClicked: root.performQrScan() }
            }

            AnimWrap {
                isShown: !root.isVideoMode; contentWidth: s(2)
                Rectangle { width: s(2); height: s(16); anchors.verticalCenter: parent.verticalCenter; color: _theme.surface0; radius: s(1) }
            }
            
            AnimWrap {
                isShown: !root.isVideoMode; contentWidth: s(36)
                ToolbarBtn { iconTxt: root.isMaximized ? "" : ""; onClicked: root.toggleMaximize() }
            }

            // Universal Close Button
            Item {
                width: s(2) + s(3) + s(36); height: parent.height // Widened width for reducced padding on right
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    spacing: s(3) // Reducción de padding lateral para los íconos en top part
                    Rectangle { width: s(2); height: s(16); anchors.verticalCenter: parent.verticalCenter; color: _theme.surface0; radius: s(1);}
                    ToolbarBtn { 
                        anchors.verticalCenter: parent.verticalCenter
                        iconTxt: "󰅖"; isDanger: true; onClicked: Qt.quit() 
                    }
                }
            }
        }

        // Bottom Content: Center Capture Layout with Dynamic Gradient Lines
        Item {
            id: captureSection
            anchors.bottom: parent.bottom
            anchors.bottomMargin: s(12)
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: s(56) // Aumento ligero de altura para el capture circle más grande
            z: 10

            // Smooth Left Line + Hover Wave
            Rectangle {
                id: leftLineBase
                height: s(4) // Líneas horizontales más gruesas
                radius: s(2) // Radio escalado
                color: Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.1) // Subtle structural line
                anchors.left: parent.left
                anchors.leftMargin: s(24)
                anchors.right: actionBtnContainer.left
                anchors.rightMargin: s(16)
                anchors.verticalCenter: parent.verticalCenter
                clip: true

                // Stretchy gradient 'wave'
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    // Stretches left when hovered
                    width: actionArea.containsMouse ? parent.width : 0
                    radius: s(2)
                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.InOutExpo } }
                    
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: root.isVideoMode ? _theme.red : root.accentColor }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
            }

            // Central Capture Circle (Slightly Bigger)
            Item {
                id: actionBtnContainer
                width: s(56) // Círculo 'capture' un poco más grande
                height: width
                anchors.centerIn: parent
                z: 20
                
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: root.isVideoMode ? Qt.alpha(_theme.red, 0.4) : Qt.alpha(_theme.surface1, 0.8)
                    border.width: s(2)
                    Behavior on border.color { ColorAnimation { duration: 250 } }
                }

                Rectangle {
                    // Círculo interno escalado
                    width: actionArea.pressed ? s(32) : (actionArea.containsMouse ? s(40) : s(36))
                    height: width
                    radius: width / 2
                    anchors.centerIn: parent
                    color: root.isVideoMode ? _theme.red : root.accentColor
                    Behavior on color { ColorAnimation { duration: 250 } }
                    Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                }

                MouseArea {
                    id: actionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.executeCapture(false, root.isVideoMode)
                }
            }

            // Smooth Right Line + Hover Wave
            Rectangle {
                id: rightLineBase
                height: s(4) // Líneas horizontales más gruesas
                radius: s(2) // Radio escalado
                color: Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.1)
                anchors.right: parent.right
                anchors.rightMargin: s(24)
                anchors.left: actionBtnContainer.right
                anchors.leftMargin: s(16)
                anchors.verticalCenter: parent.verticalCenter
                clip: true

                // Stretchy gradient 'wave'
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    // Stretches right when hovered
                    width: actionArea.containsMouse ? parent.width : 0
                    radius: s(2)
                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.InOutExpo } }
                    
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: root.isVideoMode ? _theme.red : root.accentColor }
                    }
                }
            }
        }
    }

    // --- QR Popup and Backend Hooks ---
    Repeater {
        model: qrModel
        delegate: Rectangle {
            id: qrPopupItem
            visible: opacity > 0
            opacity: (root.showQrPopup && !root.isSelecting) ? 1.0 : 0.0
            
            x: model.qTargetX
            y: model.qTargetY + (model.fitsTop ? (1.0 - opacity) * s(15) : -(1.0 - opacity) * s(15))
            
            width: qrPopupLayout.implicitWidth + s(32)
            height: s(52)
            radius: s(26)
            color: _theme.base
            border.color: model.qSuccess ? _theme.green : _theme.red
            border.width: s(2)

            property bool isHovered: maHover.containsMouse
            scale: isHovered ? 1.0 : model.qBaseScale
            z: isHovered ? 100 : (40 - index)
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

            MouseArea { id: maHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

            RowLayout {
                id: qrPopupLayout
                anchors.centerIn: parent
                spacing: s(8)

                Text {
                    text: model.qText
                    color: model.qSuccess ? _theme.text : _theme.red
                    font.family: "JetBrains Mono"
                    font.pixelSize: s(13)
                    font.weight: Font.DemiBold
                    Layout.maximumWidth: s(400)
                    Layout.leftMargin: s(8)
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Rectangle { visible: model.qSuccess; width: s(2); Layout.fillHeight: true; Layout.topMargin: s(10); Layout.bottomMargin: s(10); color: _theme.surface0; radius: s(1) }

                ToolbarBtn {
                    visible: model.qSuccess
                    iconTxt: "󰆏"
                    onClicked: {
                        Quickshell.execDetached(["bash", "-c", `echo -n '${model.qText.replace(/'/g, "'\\''")}' | wl-copy`]);
                        root.showQrPopup = false;
                    }
                }

                ToolbarBtn {
                    visible: model.qSuccess && (model.qText.startsWith("http://") || model.qText.startsWith("https://"))
                    iconTxt: "󰌹"
                    onClicked: {
                        Quickshell.execDetached(["xdg-open", model.qText]);
                        Qt.quit();
                    }
                }

                Rectangle { width: s(2); Layout.fillHeight: true; Layout.topMargin: s(10); Layout.bottomMargin: s(10); color: _theme.surface0; radius: s(1) }
                ToolbarBtn { iconTxt: "󰅖"; isDanger: true; onClicked: root.showQrPopup = false }
            }
        }
    }

    Process {
        id: qrReaderProcess
        property string accumulated: ""
        command: ["cat", "/tmp/qs_qr_result"]
        stdout: SplitParser { splitMarker: ""; onRead: data => qrReaderProcess.accumulated += data }
        
        onExited: (exitCode) => {
            let res = qrReaderProcess.accumulated.trim()
            qrReaderProcess.accumulated = ""
            root.isScanningQr = false
            qrModel.clear()
    
            if (exitCode !== 0 || res === "") {
                qrModel.append({ 
                    qX: root.selX + (root.selW / 2), qY: root.selY + (root.selH / 2), qW: 0, qH: 0, 
                    qText: "Scan timed out or failed.", qSuccess: false,
                    qTargetX: root.selX + (root.selW / 2) - s(100), qTargetY: root.selY + (root.selH / 2),
                    qBaseScale: 1.0, fitsTop: false 
                })
                root.isQrSuccess = false
                root.showQrPopup = true
                return
            }

            let lines = res.split('\n');
            let anySuccess = false;
            let qrs = [];

            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line === "") continue;
                let delimiterIdx = line.indexOf('|||');
                if (delimiterIdx === -1) continue;

                let coordStr = line.substring(0, delimiterIdx);
                let actualText = line.substring(delimiterIdx + 3).replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
                let coords = coordStr.split(',');

                if (coords.length === 4 && !isNaN(parseInt(coords[0]))) {
                    let x = parseInt(coords[0]); let y = parseInt(coords[1]); let w = parseInt(coords[2]); let h = parseInt(coords[3]);
                    
                    let successState = !(actualText === "NOT_FOUND" || actualText.startsWith("ERROR:"));
                    if (successState) anySuccess = true;
                    let cleanText = successState ? actualText.replace(/^QR-Code:/, "") : (actualText === "NOT_FOUND" ? "No QR code found." : actualText);
                    
                    let estTextWidth = Math.min(s(400), cleanText.length * s(8.5));
                    let pw = estTextWidth + (successState ? s(140) : s(40)); 
                    let ph = s(52);
                    let absX = root.selX + x; let absY = root.selY + y;
                    let cx = absX + (w / 2);
                    let fitsTop = (absY - ph - s(15)) >= root.selY;
                    let idealX = cx - (pw / 2);
                    let targetX = Math.max(s(10), Math.min(root.width - pw - s(10), idealX));
                    let targetY = fitsTop ? (absY - ph - s(15)) : (absY + h + s(15));

                    qrs.push({ qX: absX, qY: absY, qW: w, qH: h, qText: cleanText, qSuccess: successState, pw: pw, ph: ph, targetX: targetX, targetY: targetY, cx: targetX + (pw / 2), cy: targetY + (ph / 2), scale: 1.0, fitsTop: fitsTop });
                }
            }

            for (let pass = 0; pass < 5; pass++) {
                for (let i = 0; i < qrs.length; i++) {
                    for (let j = i + 1; j < qrs.length; j++) {
                        let A = qrs[i]; let B = qrs[j];
                        let dx = Math.abs(A.cx - B.cx); let dy = Math.abs(A.cy - B.cy);
                        let req_x = (A.pw * A.scale + B.pw * B.scale) / 2 + s(10);
                        let req_y = (A.ph * A.scale + B.ph * B.scale) / 2 + s(10);
                        
                        if (dx < req_x && dy < req_y) {
                            let factorX = dx > 0 ? (dx - s(10)) * 2 / (A.pw + B.pw) : 0;
                            let factorY = dy > 0 ? (dy - s(10)) * 2 / (A.ph + B.ph) : 0;
                            let maxFactor = Math.max(factorX, factorY);
                            maxFactor = Math.max(0.35, maxFactor); 
                            A.scale = Math.min(A.scale, maxFactor); B.scale = Math.min(B.scale, maxFactor);
                        }
                    }
                }
            }

            if (qrs.length === 0) {
                qrModel.append({ 
                    qX: root.selX + (root.selW / 2), qY: root.selY + (root.selH / 2), qW: 0, qH: 0, 
                    qText: "No QR code found.", qSuccess: false,
                    qTargetX: root.selX + (root.selW / 2) - s(100), qTargetY: root.selY + (root.selH / 2),
                    qBaseScale: 1.0, fitsTop: false 
                });
            } else {
                for (let i = 0; i < qrs.length; i++) {
                    qrModel.append({ qX: qrs[i].qX, qY: qrs[i].qY, qW: qrs[i].qW, qH: qrs[i].qH, qText: qrs[i].qText, qSuccess: qrs[i].qSuccess, qTargetX: qrs[i].targetX, qTargetY: qrs[i].targetY, qBaseScale: qrs[i].scale, fitsTop: qrs[i].fitsTop });
                }
            }

            root.isQrSuccess = anySuccess;
            root.showQrPopup = true
            Quickshell.execDetached(["bash", "-c", "rm -f /tmp/qs_qr_result"])
        }
    }
    
    Timer {
        id: qrWaitTimer
        interval: 1200  
        repeat: false
        onTriggered: qrReaderProcess.running = true
    }
    
    function performQrScan() {
        Quickshell.execDetached(["bash", "-c", "rm -f /tmp/qs_qr_result"])
        root.isScanningQr = true; root.showQrPopup = false; qrModel.clear()
        let cmd = `bash ~/.config/hypr/scripts/screenshot.sh --geometry "${root.geometryString}" --scan-qr`
        Quickshell.execDetached(["bash", "-c", cmd])
        qrWaitTimer.start()
    }   
    
    Timer {
        id: captureTimer
        property string pendingCmd: ""
        interval: 80
        repeat: false
        onTriggered: {
            Quickshell.execDetached(["bash", "-c", pendingCmd])
            Qt.quit()
        }
    }
    
    function executeCapture(openEditor, isRecord) {
        let cmd = `bash ~/.config/hypr/scripts/screenshot.sh --geometry "${root.geometryString}"`
        if (isRecord) {
            cmd += " --record"
            cmd += ` --desk-vol ${root.deskVol} --desk-mute ${root.deskMute}`
            cmd += ` --mic-vol ${root.micVol} --mic-mute ${root.micMute}`
            if (root.micDevice !== "") cmd += ` --mic-dev "${root.micDevice}"`
        }
        if (openEditor) cmd += " --edit"
    
        root.visible = false
        captureTimer.pendingCmd = cmd
        captureTimer.start()
    }
}
