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

    Caching { id: paths }

    IpcHandler {
        target: "main"

        function forceReload(): void {
            Quickshell.reload(true)
        }

        function handleCommand(cmd: string, targetWidget: string, arg: string): void {
            cmd = cmd || "";
            targetWidget = targetWidget || "";
            arg = arg || "";

            let isClosing = (masterWindow.currentActive !== "hidden" && !masterWindow.isVisible);
            let effectivelyActive = isClosing ? "hidden" : masterWindow.currentActive;

            if (cmd === "close") {
                switchWidget("hidden", "");
            } else if (cmd === "toggle" || cmd === "open") {
                delayedClear.stop();

                if (targetWidget === effectivelyActive) {
                    let currentItem = widgetStack.currentItem;

                    if (arg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== arg) {
                        currentItem.activeMode = arg;
                    } else if (cmd === "toggle") {
                        switchWidget("hidden", "");
                    }
                } else if (getLayout(targetWidget)) {
                    switchWidget(targetWidget, arg);
                }
            } else if (getLayout(cmd)) {
                let legacyArg = targetWidget;
                delayedClear.stop();

                if (cmd === effectivelyActive) {
                    let currentItem = widgetStack.currentItem;
                    if (legacyArg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== legacyArg) {
                        currentItem.activeMode = legacyArg;
                    } else {
                        switchWidget("hidden", "");
                    }
                } else {
                    switchWidget(cmd, legacyArg);
                }
            }
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

        Behavior on anchors.leftMargin {
            enabled: masterWindow.currentActive !== "hidden"
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on anchors.rightMargin {
            enabled: masterWindow.currentActive !== "hidden"
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
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

    property var widgetCache: ({})

    function preloadWidget(name) {
        if (widgetCache[name]) return;
        let t = getLayout(name);
        if (!t || !t.comp) return;
        let obj = t.comp.createObject(preloaderContainer, {
            "notifModel": masterWindow.notifModel,
            "liveNotifs": masterWindow.liveNotifs,
            "visible": false
        });
        if (obj) widgetCache[name] = obj;
    }

    Component.onCompleted: {
        Qt.callLater(() => preloadWidget("settings"));
        preloadStaggerTimer.start();
    }

    Timer {
        id: preloadStaggerTimer
        interval: 900
        repeat: false
        onTriggered: {
            preloadWidget("search");
            preloadWidget("help");
        }
    }

    // =========================================================

    property string currentActive: "hidden"

    onCurrentActiveChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > " + paths.runDir + "/current_widget"]);
    }

    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: false

    property int morphDuration: 230
    property int morphDurationSwitch: 210
    property int exitDuration: 160

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
    ListModel { id: globalNotificationHistory }
    ListModel { id: activePopupsModel }

    property var liveNotifs: ({})
    property int _popupCounter: 0

    // --- NEW: Startup Grace Period Flag & Timer ---
    property bool isStartup: true
    Timer {
        interval: 500
        running: true
        onTriggered: masterWindow.isStartup = false
    }

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
            n.tracked = true;

            let extractedActions = [];
            if (n.actions) {
                for (let i = 0; i < n.actions.length; i++) {
                    extractedActions.push({
                        "id": n.actions[i].identifier || "",
                        "text": n.actions[i].text || n.actions[i].name || "Action"
                    });
                }
            }

            masterWindow._popupCounter++;
            let currentUid = masterWindow._popupCounter;

            // Always store the live object so the history center can interact with it
            masterWindow.liveNotifs[currentUid] = n;

            let notifData = {
                "appName":     n.appName  !== "" ? n.appName  : "System",
                "summary":     n.summary  !== "" ? n.summary  : "No Title",
                "body":        n.body     !== "" ? n.body     : "",
                "iconPath":    n.appIcon  !== "" ? n.appIcon  : "",
                "actionsJson": JSON.stringify(extractedActions),
                "uid":         currentUid,
                "notif":       n
            };

            // Always silently add to the history list
            globalNotificationHistory.insert(0, notifData);

            // --- CHANGED: Only trigger the visual popup if we are past the startup phase ---
            if (!masterWindow.isStartup) {
                activePopupsModel.append(notifData);
                osdPopups.storeNotif(currentUid, n);
            }
        }
    }

    property var notifModel: globalNotificationHistory

    Notifs.NotificationPopups {
        id: osdPopups
        popupModel: activePopupsModel
        uiScale: masterWindow.globalUiScale
        onRemoveRequested: (uid) => masterWindow.removePopup(uid)
    }
    onGlobalUiScaleChanged: { handleNativeScreenChange(); }

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

    // =========================================================
    // --- LAYOUT CACHE
    // =========================================================
    property var    _layoutCache:    ({})
    property string _layoutCacheKey: ""

    function getLayout(name) {
        let key = name + "|" + masterWindow.width + "|" + masterWindow.height + "|" + masterWindow.globalUiScale;
        if (_layoutCacheKey === key) return _layoutCache[key];
        let result = Registry.getLayout(name, 0, 0, masterWindow.width, masterWindow.height, masterWindow.globalUiScale);
        _layoutCache = {};
        _layoutCache[key] = result;
        _layoutCacheKey = key;
        return result;
    }

    Connections {
        target: masterWindow
        function onWidthChanged()  { _layoutCacheKey = ""; handleNativeScreenChange(); }
        function onHeightChanged() { _layoutCacheKey = ""; handleNativeScreenChange(); }
    }

    function handleNativeScreenChange() {
        if (masterWindow.currentActive === "hidden") return;

        let t = getLayout(masterWindow.currentActive);
        if (!t) return;

        let currentItem = widgetStack.currentItem;
        let finalW = (currentItem && currentItem.targetMasterWidth  !== undefined) ? currentItem.targetMasterWidth  : t.w;
        let finalH = (currentItem && currentItem.targetMasterHeight !== undefined) ? currentItem.targetMasterHeight : t.h;
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

    onIsVisibleChanged: {
        if (isVisible) widgetStack.forceActiveFocus();
    }

    // =========================================================
    // --- ANIMATED BOUNDING BOX
    // =========================================================
    Item {
        x: masterWindow.animX
        y: masterWindow.animY
        width:  masterWindow.animW
        height: masterWindow.animH
        clip: true

        Behavior on x {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutCubic }
        }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: masterWindow.isVisible ? Easing.OutCubic : Easing.InCubic
            }
        }

        MouseArea { anchors.fill: parent }

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
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 0.0; to: 1.0
                            duration: masterWindow.morphDurationSwitch
                            easing.type: Easing.OutQuint
                        }
                        NumberAnimation {
                            property: "scale"
                            from: 0.98; to: 1.0
                            duration: masterWindow.morphDurationSwitch
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                replaceExit: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 1.0; to: 0.0
                            duration: masterWindow.morphDurationSwitch
                            easing.type: Easing.InQuint
                        }
                        NumberAnimation {
                            property: "scale"
                            from: 1.0; to: 0.98
                            duration: masterWindow.morphDurationSwitch
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    // =========================================================
    // --- WIDGET SWITCHING
    // =========================================================
    function switchWidget(newWidget, arg) {
        delayedClear.stop();

        if (newWidget === "hidden") {
            if (currentActive !== "hidden") {
                masterWindow.morphDuration = masterWindow.exitDuration;
                masterWindow.disableMorph = false;

                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false;

                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden" || !masterWindow.isVisible) {
                masterWindow.morphDuration = 230;
                masterWindow.disableMorph = false;

                let t = getLayout(newWidget);
                masterWindow.animX = t.rx;
                masterWindow.animY = t.ry;
                masterWindow.animW = t.w;
                masterWindow.animH = t.h;
                masterWindow.targetW = t.w;
                masterWindow.targetH = t.h;
            } else {
                masterWindow.morphDuration = masterWindow.morphDurationSwitch;
                masterWindow.disableMorph = false;
            }

            Qt.callLater(() => executeSwitch(newWidget, arg, false));
        }
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

        let props = {};
        props["notifModel"]   = masterWindow.notifModel;
        props["liveNotifs"]   = masterWindow.liveNotifs;
        props["layoutWidth"]  = t.w;
        props["layoutHeight"] = t.h;
        if (newWidget === "wallpaper") props["widgetArg"] = arg;

        let cached = widgetCache[newWidget];
        if (cached) {
            if (cached.notifModel   !== undefined) cached.notifModel   = masterWindow.notifModel;
            if (cached.liveNotifs   !== undefined) cached.liveNotifs   = masterWindow.liveNotifs;
            if (cached.layoutWidth  !== undefined) cached.layoutWidth  = t.w;
            if (cached.layoutHeight !== undefined) cached.layoutHeight = t.h;
            if (newWidget === "wallpaper" && cached.widgetArg !== undefined) cached.widgetArg = arg;
            if (arg !== "" && cached.activeMode !== undefined) cached.activeMode = arg;

            cached.visible = true;
            if (immediate) {
                widgetStack.replace(cached, {}, StackView.Immediate);
            } else {
                widgetStack.replace(cached, {});
            }
        } else {
            if (immediate) {
                widgetStack.replace(t.comp, props, StackView.Immediate);
            } else {
                widgetStack.replace(t.comp, props);
            }
        }

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

    Timer {
        id: delayedClear
        interval: 200
        onTriggered: {
            masterWindow.currentActive = "hidden";
            widgetStack.clear();
            masterWindow.disableMorph = false;
        }
    }
}
