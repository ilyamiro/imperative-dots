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

    WlrLayershell.namespace: "qs-master"
    WlrLayershell.layer: WlrLayer.Overlay
    
    exclusionMode: ExclusionMode.Ignore 
    focusable: true

    width: Screen.width
    height: Screen.height

    visible: isVisible

    mask: Region { item: topBarHole; intersection: Intersection.Xor }
    
    Item {
        id: topBarHole
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 65 
    }

    MouseArea {
        anchors.fill: parent
        enabled: masterWindow.isVisible
        onClicked: switchWidget("hidden", "")
    }

    Component.onCompleted: {
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > /tmp/qs_active_widget"]);
    }

    property string currentActive: "hidden" 
    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: false 
    property int morphDuration: 500
    property int exitDuration: 300 // Controls how fast the outgoing widget disappears

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

    function getLayout(name) {
        return Registry.getLayout(name, 0, 0, Screen.width, Screen.height, masterWindow.globalUiScale);
    }

    Connections {
        target: Screen
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
        if (isVisible) masterWindow.requestActivate();
    }

    Item {
        x: masterWindow.animX
        y: masterWindow.animY
        width: masterWindow.animW
        height: masterWindow.animH
        clip: true 
        layer.enabled: true 

        // Smoother easing type: OutExpo makes animations feel snappy yet perfectly fluid
        Behavior on x { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }
        Behavior on y { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }
        Behavior on width { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }
        Behavior on height { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: masterWindow.morphDuration === 500 ? 300 : 200; easing.type: Easing.InOutSine } }

        MouseArea {
            anchors.fill: parent
        }

        Item {
            anchors.centerIn: parent
            width: masterWindow.targetW
            height: masterWindow.targetH

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
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutExpo }
                        NumberAnimation { property: "scale"; from: 0.98; to: 1.0; duration: 400; easing.type: Easing.OutBack }
                    }
                }
                replaceExit: Transition {
                    ParallelAnimation {
                        // Uses the dynamically set exitDuration
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: masterWindow.exitDuration; easing.type: Easing.InExpo }
                        NumberAnimation { property: "scale"; from: 1.0; to: 1.02; duration: masterWindow.exitDuration; easing.type: Easing.InExpo }
                    }
                }
            }
        }
    }

    function switchWidget(newWidget, arg) {
        Quickshell.execDetached(["bash", "-c", "echo '" + newWidget + "' > /tmp/qs_active_widget"]);

        prepTimer.stop();
        delayedClear.stop();

        if (newWidget === "hidden") {
            if (currentActive !== "hidden") {
                masterWindow.morphDuration = 250; 
                masterWindow.exitDuration = 250;
                masterWindow.disableMorph = false;
                
                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false; 
                
                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden") {
                masterWindow.morphDuration = 250;
                masterWindow.exitDuration = 300;
                masterWindow.disableMorph = false;
                
                let t = getLayout(newWidget);
                masterWindow.animX = t.rx;
                masterWindow.animY = t.ry;
                masterWindow.animW = 1;
                masterWindow.animH = 1;

                prepTimer.newWidget = newWidget;
                prepTimer.newArg = arg;
                prepTimer.start();
                
            } else {
                // Morphing directly between widgets (including wallpaper)
                masterWindow.morphDuration = 500;
                masterWindow.disableMorph = false;
                
                // If transitioning to wallpaper, make the previous widget disappear significantly faster
                masterWindow.exitDuration = (newWidget === "wallpaper") ? 100 : 300;
                
                executeSwitch(newWidget, arg, false);
            }
        }
    }

    Timer {
        id: prepTimer
        interval: 50
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

        if (immediate) {
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
            "inotifywait -qq -e close_write,moved_to --include 'qs_widget_state$' /tmp/ 2>/dev/null; " +
            "if [ -f /tmp/qs_widget_state ]; then cat /tmp/qs_widget_state && rm -f /tmp/qs_widget_state; fi"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let rawCmd = this.text.trim();

                if (rawCmd !== "") {
                    let parts = rawCmd.split(":");
                    let cmd   = parts[0];
                    let arg   = parts.length > 1 ? parts[1] : "";

                    if (cmd === "close") {
                        switchWidget("hidden", "");
                    } else if (getLayout(cmd)) {
                        delayedClear.stop();
                        if (cmd === masterWindow.currentActive) {
                            switchWidget("hidden", "");
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
