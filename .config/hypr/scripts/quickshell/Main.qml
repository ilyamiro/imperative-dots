import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "WindowRegistry.js" as Registry

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
        height: 65 // Safely covers your TopBar height + margins
    }

    MouseArea {
        anchors.fill: parent
        enabled: masterWindow.isVisible
        onClicked: switchWidget("hidden", "")
    }

    property string currentActive: "hidden" 
    onCurrentActiveChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > /tmp/qs_active_widget"]);
    }

    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: false 
    property bool isWallpaperTransition: false 
    property int morphDuration: 500

    property real animW: 1
    property real animH: 1
    property real animX: 0
    property real animY: 0

    function getLayout(name) {
        return Registry.getLayout(name, 0, 0, Screen.width, Screen.height);
    }

    // --- RESTORED: SELF-HEALING GEOMETRY ---
    // Automatically recalculates position and scale if the OS resolution changes
    Connections {
        target: Screen
        function onWidthChanged() { handleNativeScreenChange(); }
        function onHeightChanged() { handleNativeScreenChange(); }
    }

    function handleNativeScreenChange() {
        if (masterWindow.currentActive === "hidden") return;
        
        let t = getLayout(masterWindow.currentActive);
        if (t) {
            // Update the animation targets. The Behaviors below will 
            // glide the widget to the new layout perfectly.
            masterWindow.animX = t.rx;
            masterWindow.animY = t.ry;
            masterWindow.animW = t.w;
            masterWindow.animH = t.h;
        }
    }
    // ---------------------------------------

    onIsVisibleChanged: {
        if (isVisible) masterWindow.requestActivate();
    }

    // --- THE WIDGET CONTAINER ---
    Item {
        x: masterWindow.animX
        y: masterWindow.animY
        width: masterWindow.animW
        height: masterWindow.animH
        clip: true 

        Behavior on x { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on y { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on width { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on height { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: masterWindow.isWallpaperTransition ? 150 : (masterWindow.morphDuration === 500 ? 300 : 200); easing.type: Easing.InOutSine } }

        Item {
            anchors.centerIn: parent
            width: masterWindow.currentActive !== "hidden" && getLayout(masterWindow.currentActive) ? getLayout(masterWindow.currentActive).w : 1
            height: masterWindow.currentActive !== "hidden" && getLayout(masterWindow.currentActive) ? getLayout(masterWindow.currentActive).h : 1

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
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 300; easing.type: Easing.InExpo }
                        NumberAnimation { property: "scale"; from: 1.0; to: 1.02; duration: 300; easing.type: Easing.InExpo }
                    }
                }
            }
        }
    }

    function switchWidget(newWidget, arg) {
        prepTimer.stop();
        teleportFadeOutTimer.stop();
        teleportFadeInTimer.stop();
        delayedClear.stop();

        let involvesWallpaper = (newWidget === "wallpaper" || currentActive === "wallpaper");
        masterWindow.isWallpaperTransition = involvesWallpaper;

        if (newWidget === "hidden") {
            if (currentActive !== "hidden") {
                masterWindow.morphDuration = 250; 
                masterWindow.disableMorph = false;
                
                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false; 
                
                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden") {
                masterWindow.morphDuration = 250;
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
                masterWindow.morphDuration = 500;
                if (involvesWallpaper) {
                    masterWindow.disableMorph = true;
                    masterWindow.isVisible = false; 
                    teleportFadeOutTimer.newWidget = newWidget;
                    teleportFadeOutTimer.newArg = arg;
                    teleportFadeOutTimer.start();
                } else {
                    masterWindow.disableMorph = false;
                    executeSwitch(newWidget, arg, false);
                }
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

    Timer {
        id: teleportFadeOutTimer
        interval: 150 
        property string newWidget: ""
        property string newArg: ""
        onTriggered: {
            let t = getLayout(newWidget);

            masterWindow.currentActive = newWidget;
            masterWindow.activeArg = newArg;

            masterWindow.animX = t.rx;
            masterWindow.animY = t.ry;
            masterWindow.animW = t.w;
            masterWindow.animH = t.h;

            let props = newWidget === "wallpaper" ? { "widgetArg": newArg } : {};
            widgetStack.replace(t.comp, props, StackView.Immediate);

            teleportFadeInTimer.newWidget = newWidget;
            teleportFadeInTimer.newArg = newArg;
            teleportFadeInTimer.start();
        }
    }

    Timer {
        id: teleportFadeInTimer
        interval: 50 
        property string newWidget: ""
        property string newArg: ""
        onTriggered: {
            masterWindow.isVisible = true; 
            if (newWidget !== "wallpaper") resetMorphTimer.start();
        }
    }

    Timer {
        id: resetMorphTimer
        interval: masterWindow.morphDuration 
        onTriggered: masterWindow.disableMorph = false
    }

    function executeSwitch(newWidget, arg, immediate) {
        masterWindow.currentActive = newWidget;
        masterWindow.activeArg = arg;
        
        let t = getLayout(newWidget);
        masterWindow.animX = t.rx;
        masterWindow.animY = t.ry;
        masterWindow.animW = t.w;
        masterWindow.animH = t.h;
        
        let props = newWidget === "wallpaper" ? { "widgetArg": arg } : {};

        if (immediate) {
            widgetStack.replace(t.comp, props, StackView.Immediate);
        } else {
            widgetStack.replace(t.comp, props);
        }
        
        masterWindow.isVisible = true;
    }

    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: { if (!ipcPoller.running) ipcPoller.running = true; }
    }

    Process {
        id: ipcPoller
        command: ["bash", "-c", "if [ -f /tmp/qs_widget_state ]; then cat /tmp/qs_widget_state; rm /tmp/qs_widget_state; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rawCmd = this.text.trim();
                if (rawCmd === "") return;

                let parts = rawCmd.split(":");
                let cmd = parts[0];
                let arg = parts.length > 1 ? parts[1] : "";

                if (cmd === "close") {
                    switchWidget("hidden", "");
                } else if (getLayout(cmd)) {
                    delayedClear.stop();
                    // Removed the redundant toggle check. 
                    // qs_manager.sh is now the absolute source of truth.
                    switchWidget(cmd, arg);
                }
            }
        }
    }
    Timer {
        id: delayedClear
        interval: masterWindow.isWallpaperTransition ? 150 : masterWindow.morphDuration 
        onTriggered: {
            masterWindow.currentActive = "hidden";
            widgetStack.clear();
            masterWindow.disableMorph = false;
        }
    }
}
