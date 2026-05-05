import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "WindowRegistry.js" as Registry

import "notifications" as Notifs

PanelWindow {
    id: masterWindow
    color: "transparent"

    Connections {
        target: Quickshell

        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup()
        }

        function onReloadFailed(errorString) {
            Quickshell.inhibitReloadPopup()
        }
    }

    IpcHandler {
        target: "main"
    
        function forceReload() {
            Quickshell.reload(true) 
        }
    }

    WlrLayershell.namespace: "qs-master"
    WlrLayershell.layer: WlrLayer.Overlay
    
    exclusionMode: ExclusionMode.Ignore 
    focusable: true

    implicitWidth: masterWindow.screen.width
    implicitHeight: masterWindow.screen.height

    visible: isVisible

    mask: Region { item: topBarHole; intersection: Intersection.Xor }
    
    Item {
        id: topBarHole
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 48 

        anchors.leftMargin: (masterWindow.currentActive !== "hidden" && masterWindow.animX < 10 && masterWindow.animY < height) ? masterWindow.animW : 0
	anchors.rightMargin: (masterWindow.currentActive !== "hidden" && (masterWindow.animX + masterWindow.animW) > (parent.width - 10) && masterWindow.animY < height) ? masterWindow.animW : 0 

        Behavior on anchors.leftMargin { NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on anchors.rightMargin { NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: masterWindow.isVisible
        onClicked: switchWidget("hidden", "")
    }

    // =========================================================
    // --- DAEMON: PRELOADING SYSTEM
    // =========================================================
    Item {
        id: preloaderContainer
        visible: false
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            let widgetsToPreload = ["settings", "search", "help"];
            for (let i = 0; i < widgetsToPreload.length; i++) {
                let t = getLayout(widgetsToPreload[i]);
                if (t && t.comp) {
                    t.comp.incubateObject(preloaderContainer, {
                        "notifModel": masterWindow.notifModel
                    }, Qt.Asynchronous);
                }
            }
        });
    }

    property string currentActive: "hidden"

    onCurrentActiveChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > /tmp/qs_current_widget"]);
    }

    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: false 
    property int morphDuration: 250
    property int exitDuration: 170 

    property real animW: 1
    property real animH: 1
    property real animX: 0
    property real animY: 0
    
    property real targetW: 1
    property real targetH: 1

    property real globalUiScale: 1.0

    // =========================================================
    // --- DAEMON: NOTIFICATION HANDLING
    // =========================================================
    ListModel {
        id: globalNotificationHistory
    }

    ListModel {
        id: activePopupsModel
    }

    property int _popupCounter: 0

    function removePopup(uid) {
        for (let i = 0; i < activePopupsModel.count; i++) {
            if (activePopupsModel.get(i).uid === uid) {
                activePopupsModel.remove(i);
                break;
            }
        }
    }

    NotificationServer {
        id: globalNotificationServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: (n) => {
            console.log("Saving to history:", n.appName, "-", n.summary);
            
            let notifData = {
                "appName": n.appName !== "" ? n.appName : "System",
                "summary": n.summary !== "" ? n.summary : "No Title",
                "body": n.body !== "" ? n.body : "",
                "iconPath": n.appIcon !== "" ? n.appIcon : "",
                "notif": n
            };

            globalNotificationHistory.insert(0, notifData);

            masterWindow._popupCounter++;
            let popupData = Object.assign({ "uid": masterWindow._popupCounter }, notifData);
            activePopupsModel.append(popupData);
        }
    }   
    property var notifModel: globalNotificationHistory
    
    Notifs.NotificationPopups {
        id: osdPopups
        popupModel: activePopupsModel
        uiScale: masterWindow.globalUiScale
    }
    // =========================================================

    onGlobalUiScaleChanged: {
        handleNativeScreenChange();
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
                        if (parsed.uiScale !== undefined && masterWindow.globalUiScale !== parsed.uiScale) {
                            masterWindow.globalUiScale = parsed.uiScale;
                        }
                        if (parsed.uiLanguage !== undefined && Config.uiLanguage !== parsed.uiLanguage) {
                            Config.uiLanguage = parsed.uiLanguage;
                            Config.loadTranslations();
                        }
                    }
                } catch (e) {
                    console.log("Error parsing settings.json in main.qml:", e);
                }
            }
        }
    }

    Process {
        id: settingsWatcher
        command: ["bash", "-c", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                settingsReader.running = false;
                settingsReader.running = true;
                
                settingsWatcher.running = false;
                settingsWatcher.running = true;
            }
        }
    }

    function getLayout(name) {
        return Registry.getLayout(name, 0, 0, masterWindow.width, masterWindow.height, masterWindow.globalUiScale);
    }

    Connections {
        target: masterWindow
        function onWidthChanged() { handleNativeScreenChange(); }
        function onHeightChanged() { handleNativeScreenChange(); }
    }

    function handleNativeScreenChange() {
        if (masterWindow.currentActive === "hidden") return;
        
        let t = getLayout(masterWindow.currentActive);
        if (t) {
            let currentItem = widgetStack.currentItem;
            
            // Check if the current widget has dynamic dimensional overrides
            let finalW = (currentItem && currentItem.targetMasterWidth !== undefined) ? currentItem.targetMasterWidth : t.w;
            let finalH = (currentItem && currentItem.targetMasterHeight !== undefined) ? currentItem.targetMasterHeight : t.h;
            
            // Re-center X if the width dynamically changed
            let finalX = t.rx;
            if (currentItem && currentItem.targetMasterWidth !== undefined && finalW !== t.w) {
                finalX = Math.floor((masterWindow.width / 2) - (finalW / 2));
            }

            masterWindow.animX = finalX;
            masterWindow.animY = t.ry;
            masterWindow.animW = finalW;
            masterWindow.animH = finalH;
            masterWindow.targetW = finalW;
            masterWindow.targetH = finalH;
        }
    }

    onIsVisibleChanged: {
        if (isVisible) widgetStack.forceActiveFocus();
    }

    Item {
        x: masterWindow.animX
        y: masterWindow.animY
        width: masterWindow.animW
        height: masterWindow.animH
        clip: true 

        // Continuous bounding box morphing
        Behavior on x { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on y { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on width { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on height { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: masterWindow.morphDuration === 170 ? 130 : 100; easing.type: Easing.InOutCubic } }

        MouseArea {
            anchors.fill: parent
        }

        // Full anchoring so the content properly morphs with the box
        Item {
            anchors.fill: parent

            StackView {
                id: widgetStack
                anchors.fill: parent
                focus: true
                
                Keys.onEscapePressed: {
                    switchWidget("hidden", "");
                    event.accepted = true;
                }

                onCurrentItemChanged: {
                    if (currentItem) currentItem.forceActiveFocus();
                }

                replaceEnter: Transition {
                    SequentialAnimation {
                        PropertyAction { property: "z"; value: -1 }
                        // Keep new widget fully opaque. The old widget acts as a shield while this one sets up.
                        NumberAnimation { property: "opacity"; from: 1.0; to: 1.0; duration: masterWindow.morphDuration }
                    }
                }
                
                replaceExit: Transition {
                    SequentialAnimation {
                        PropertyAction { property: "z"; value: 1 }
                        ParallelAnimation {
                            SequentialAnimation {
                                // THE SHIELD: Hold old widget completely opaque for 30ms.
                                PauseAnimation { duration: 30 }
                                NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: masterWindow.morphDuration - 30; easing.type: Easing.InOutQuad }
                            }
                            NumberAnimation { property: "scale"; from: 1.0; to: 1.05; duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }

    function switchWidget(newWidget, arg) {
        prepTimer.stop();
        delayedClear.stop();
    
        if (newWidget === "hidden") {
            if (currentActive !== "hidden") {
                masterWindow.morphDuration = 170; 
                masterWindow.exitDuration = 170;
                masterWindow.disableMorph = false;
                
                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false; 
                
                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden" || !masterWindow.isVisible) {
                masterWindow.morphDuration = 250; 
                masterWindow.exitDuration = 250;
                masterWindow.disableMorph = false;
                
                let t = getLayout(newWidget);
                masterWindow.animX = t.rx;
                masterWindow.animY = t.ry;
                masterWindow.animW = t.w;
                masterWindow.animH = t.h;
                masterWindow.targetW = t.w;
                masterWindow.targetH = t.h;
            } else {
                masterWindow.morphDuration = 300; 
                masterWindow.disableMorph = false;
                masterWindow.exitDuration = (newWidget === "wallpaper") ? 125 : 300;
            }
    
        prepTimer.newWidget = newWidget;
        prepTimer.newArg = arg;
        prepTimer.start();
        }
    }

    Timer {
        id: prepTimer
        interval: 15 
        property string newWidget: ""
        property string newArg: ""
        onTriggered: executeSwitch(newWidget, newArg, false)
    }

    function executeSwitch(newWidget, arg, immediate) {
        masterWindow.currentActive = newWidget;
        masterWindow.activeArg = arg;
        
        let t = getLayout(newWidget);
        masterWindow.animX = t.rx;
        masterWindow.animY = t.ry;
        masterWindow.animW = t.w;
        masterWindow.animH = t.h;
        masterWindow.targetW = t.w;
        masterWindow.targetH = t.h;
        
        let props = newWidget === "wallpaper" ? { "widgetArg": arg } : {};
	props["notifModel"] = masterWindow.notifModel;
	props["layoutWidth"] = t.w;
	props["layoutHeight"] = t.h;

        if (immediate) {
            widgetStack.replace(t.comp, props, StackView.Immediate);
        } else {
            widgetStack.replace(t.comp, props);
        }
        
        // Ensure Main.qml respects the dynamic size of the newly loaded widget immediately
        let currentItem = widgetStack.currentItem;
        if (currentItem) {
            if (currentItem.targetMasterWidth !== undefined) {
                let dynW = currentItem.targetMasterWidth;
                masterWindow.animW = dynW;
                masterWindow.targetW = dynW;
                masterWindow.animX = Math.floor((masterWindow.width / 2) - (dynW / 2));
            }
            if (currentItem.targetMasterHeight !== undefined) {
                masterWindow.animH = currentItem.targetMasterHeight;
                masterWindow.targetH = currentItem.targetMasterHeight;
            }
        }
        
        masterWindow.isVisible = true;
    }
    // =========================================================
    // --- IPC: EVENT-DRIVEN WATCHER
    // =========================================================
    Process {
        id: ipcWatcher
        command: ["bash", "-c",
            "touch /tmp/qs_widget_state; " +
            "inotifywait -qq -e close_write /tmp/qs_widget_state 2>/dev/null; " +
            "cat /tmp/qs_widget_state"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let rawCmd = this.text.trim();

                if (rawCmd !== "") {
                    let parts = rawCmd.split(":");
                    let cmd = parts[0];

                    // Determine if the widget is currently in its closing animation
                    let isClosing = (masterWindow.currentActive !== "hidden" && !masterWindow.isVisible);
                    let effectivelyActive = isClosing ? "hidden" : masterWindow.currentActive;

                    if (cmd === "close") {
                        switchWidget("hidden", "");
                    } else if (cmd === "toggle" || cmd === "open") {
                        let targetWidget = parts.length > 1 ? parts[1] : "";
                        let arg = parts.length > 2 ? parts.slice(2).join(":") : "";

                        delayedClear.stop();
                        
                        // Use effectivelyActive so a closing widget isn't accidentally toggled off again
                        if (targetWidget === effectivelyActive) {
                            let currentItem = widgetStack.currentItem;
                            
                            if (arg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== arg) {
                                currentItem.activeMode = arg;
                            } 
                            else if (cmd === "toggle") {
                                switchWidget("hidden", "");
                            }
                            
                        } else if (getLayout(targetWidget)) {
                            switchWidget(targetWidget, arg);
                        }
                    } else if (getLayout(cmd)) { 
                        let arg = parts.length > 1 ? parts.slice(1).join(":") : "";
                        delayedClear.stop();
                        
                        if (cmd === effectivelyActive) {
                            let currentItem = widgetStack.currentItem;
                            if (arg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== arg) {
                                currentItem.activeMode = arg;
                            } else {
                                switchWidget("hidden", "");
                            }
                        } else {
                            switchWidget(cmd, arg);
                        }
                    }
                }

                ipcWatcher.running = false;
                ipcWatcher.running = true;
            }
        }
    }   
    Timer {
        id: delayedClear
        interval: masterWindow.morphDuration 
        onTriggered: {
            masterWindow.currentActive = "hidden";
            widgetStack.clear();
            masterWindow.disableMorph = false;
        }
    }
}
