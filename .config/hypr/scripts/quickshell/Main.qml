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

    // FIXED: Bind directly to the window's actual screen boundaries rather than the global singleton.
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

        // Dynamically shrink the hole away from the active widget so it doesn't punch through it.
        // If the sidebar is open on the left, push the hole's left edge out of the way.
        anchors.leftMargin: (masterWindow.currentActive !== "hidden" && masterWindow.animX < 10) ? masterWindow.animW : 0
        
        // If a widget (like a notification center) is on the right, push the hole's right edge out of the way.
        anchors.rightMargin: (masterWindow.currentActive !== "hidden" && (masterWindow.animX + masterWindow.animW) > (parent.width - 10)) ? masterWindow.animW : 0
        
        // --- MODIFIED: Changed from OutQuart to InOutCubic for smoother, continuous masking
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
    // Hidden container to warm up the QML engine cache without displaying anything
    Item {
        id: preloaderContainer
        visible: false
    }

    Component.onCompleted: {
        // State is now strictly in memory; no need to write to /tmp on startup.

        // PRELOADING: Asynchronously initialize heavy widgets in the background.
        // This prevents the main thread from blocking (which freezes Hyprland)
        // the first time StackView tries to instantiate them.
        Qt.callLater(() => {
            let widgetsToPreload = ["settings", "search", "help"];
            for (let i = 0; i < widgetsToPreload.length; i++) {
                let t = getLayout(widgetsToPreload[i]);
                if (t && t.comp) {
                    // Qt.Asynchronous tells QML to build this incrementally over multiple frames
                    t.comp.incubateObject(preloaderContainer, {
                        "notifModel": masterWindow.notifModel
                    }, Qt.Asynchronous);
                }
            }
        });
    }

    property string currentActive: "hidden"

    onCurrentActiveChanged: {
        // Broadcast active state so TopBar knows when to morph
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > /tmp/qs_current_widget"]);
    }

    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: false 
    property int morphDuration: 550
    // --- MODIFIED: Slightly increased default exit duration for smoother fade outs
    property int exitDuration: 200 

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
    // 1. Permanent History (For the Notification Center)
    ListModel {
        id: globalNotificationHistory
    }

    // 2. Transient Popups (For the OSD)
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
                "iconPath": n.appIcon !== "" ? n.appIcon : "", // <-- ADDED: Save the -i parameter path
                "notif": n
            };

            // A. Insert into the permanent center
            globalNotificationHistory.insert(0, notifData);

            // B. Append to the on-screen popups
            masterWindow._popupCounter++;
            let popupData = Object.assign({ "uid": masterWindow._popupCounter }, notifData);
            activePopupsModel.append(popupData);
        }
    }   
    property var notifModel: globalNotificationHistory
    
    // --- INSTANTIATE THE POPUP OVERLAY ---
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

    // FIXED: Use masterWindow dimensions instead of the static Screen singleton
    function getLayout(name) {
        return Registry.getLayout(name, 0, 0, masterWindow.width, masterWindow.height, masterWindow.globalUiScale);
    }

    // FIXED: Target masterWindow directly so it catches local geometry changes.
    Connections {
        target: masterWindow
        function onWidthChanged() { handleNativeScreenChange(); }
        function onHeightChanged() { handleNativeScreenChange(); }
    }

    function handleNativeScreenChange() {
        if (masterWindow.currentActive === "hidden") return;
        
        let t = getLayout(masterWindow.currentActive);
        if (t) {
            masterWindow.animX = t.rx;
            masterWindow.animY = t.ry;
            masterWindow.animW = t.w;
            masterWindow.animH = t.h;
            masterWindow.targetW = t.w;
            masterWindow.targetH = t.h;
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

        // --- MODIFIED: Changed from OutQuart to InOutCubic for smooth, continuous bounding box movement
        Behavior on x { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on y { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on width { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on height { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: masterWindow.morphDuration === 350 ? 250 : 200; easing.type: Easing.InOutSine } }

        MouseArea {
            anchors.fill: parent
        }

        // FIXED: Replaced fixed targetW/targetH with anchors.fill: parent.
        // This forces the StackView to dynamically expand/compress with the morphing box
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

                // --- MODIFIED: Switched OutExpo/InExpo to OutQuint/InQuint and slightly bumped durations for softer content fading
                replaceEnter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.OutQuint }
                        NumberAnimation { property: "scale"; from: 0.98; to: 1.0; duration: 300; easing.type: Easing.OutQuint }
                    }
                }
                replaceExit: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: masterWindow.exitDuration; easing.type: Easing.InQuint }
                        NumberAnimation { property: "scale"; from: 1.0; to: 1.02; duration: masterWindow.exitDuration; easing.type: Easing.InQuint }
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
                // --- MODIFIED: Increased close durations
                masterWindow.morphDuration = 250; 
                masterWindow.exitDuration = 200;
                masterWindow.disableMorph = false;
                
                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false; 
                
                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden") {
                // --- MODIFIED: Increased open durations
                masterWindow.morphDuration = 300; 
                masterWindow.exitDuration = 200;
                masterWindow.disableMorph = false;
                
                let t = getLayout(newWidget);
                masterWindow.animX = t.rx;
                masterWindow.animY = t.ry;
                masterWindow.animW = 1;
                masterWindow.animH = 1;
            } else {
                // --- MODIFIED: Increased morphing durations to let the continuous ease shine
                masterWindow.morphDuration = 350; 
                masterWindow.disableMorph = false;
                masterWindow.exitDuration = (newWidget === "wallpaper") ? 150 : 200;
            }

            // Route all incoming widgets through the debounce timer to prevent StackView corruption
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

        // CRITICAL FIX: Fallback to Immediate if the StackView is already busy with an interrupted transition.
        if (immediate || widgetStack.busy) {
            widgetStack.replace(t.comp, props, StackView.Immediate);
        } else {
            widgetStack.replace(t.comp, props);
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

                    if (cmd === "close") {
                        switchWidget("hidden", "");
                    } else if (cmd === "toggle" || cmd === "open") {
                        let targetWidget = parts.length > 1 ? parts[1] : "";
                        let arg = parts.length > 2 ? parts.slice(2).join(":") : "";

                        delayedClear.stop();
                        
                        if (targetWidget === masterWindow.currentActive) {
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
                        
                        if (cmd === masterWindow.currentActive) {
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
