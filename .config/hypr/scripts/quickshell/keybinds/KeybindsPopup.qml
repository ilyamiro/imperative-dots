import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    focus: true

    Caching { id: paths }

    // Props passed in by Main.qml (declare to avoid warnings / enable sizing)
    property var notifModel
    property var liveNotifs
    property real layoutWidth: width
    property real layoutHeight: height

    // --- Responsive Scaling ---
    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    // -------------------------------------------------------------------------
    // KEYBOARD NAVIGATION
    // -------------------------------------------------------------------------
    Keys.onEscapePressed: { closeSequence.start(); event.accepted = true; }

    // -------------------------------------------------------------------------
    // COLORS
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color overlay0: _theme.overlay0
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color blue: _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color green: _theme.green
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red

    function clr(name) { return root[name]; }

    property real colorBlend: 0.0
    SequentialAnimation on colorBlend {
        loops: Animation.Infinite
        running: true
        NumberAnimation { to: 1.0; duration: 15000; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: 15000; easing.type: Easing.InOutSine }
    }
    property color ambientPurple: Qt.tint(root.mauve, Qt.rgba(root.pink.r, root.pink.g, root.pink.b, colorBlend))
    property color ambientBlue: Qt.tint(root.blue, Qt.rgba(root.sapphire.r, root.sapphire.g, root.sapphire.b, colorBlend))

    // -------------------------------------------------------------------------
    // KEYBIND DATA  (mirrors the defaults in hypr/default_settings.json)
    // -------------------------------------------------------------------------
    property var leftSections: [
        {
            title: "Applications", icon: "", color: "blue",
            binds: [
                { keys: ["SUPER", "RETURN"],    desc: "Terminal (kitty)" },
                { keys: ["SUPER", "F"],         desc: "Browser" },
                { keys: ["SUPER", "E"],         desc: "File manager" },
                { keys: ["SUPER", "D"],         desc: "App launcher" }
            ]
        },
        {
            title: "Window Management", icon: "", color: "mauve",
            binds: [
                { keys: ["SUPER", "Arrows"],            desc: "Move focus" },
                { keys: ["SUPER", "CTRL", "Arrows"],    desc: "Move window" },
                { keys: ["SUPER", "SHIFT", "Arrows"],   desc: "Resize window" },
                { keys: ["SUPER", "SHIFT", "F"],        desc: "Toggle floating" },
                { keys: ["SUPER", "TAB"],               desc: "Focus next monitor" },
                { keys: ["ALT", "F4"],                  desc: "Close window" }
            ]
        },
        {
            title: "Media & System", icon: "", color: "pink",
            binds: [
                { keys: ["SUPER", "L"],          desc: "Lock screen" },
                { keys: ["SUPER", "SPACE"],      desc: "Play / Pause" },
                { keys: ["SUPER", "R"],          desc: "Reload Hyprland" },
                { keys: ["PRINT"],               desc: "Screenshot (region)" },
                { keys: ["SHIFT", "PRINT"],      desc: "Screenshot + edit" },
                { keys: ["SUPER", "PRINT"],      desc: "Screenshot (fullscreen)" }
            ]
        }
    ]

    property var rightSections: [
        {
            title: "Workspaces", icon: "", color: "green",
            binds: [
                { keys: ["SUPER", "1 – 0"],            desc: "Switch workspace" },
                { keys: ["SUPER", "SHIFT", "1 – 0"],   desc: "Move window to workspace" }
            ]
        },
        {
            title: "Widgets & Panels", icon: "", color: "peach",
            binds: [
                { keys: ["SUPER", "H"],          desc: "Guide / dashboard" },
                { keys: ["SUPER", "K"],          desc: "This keybinds guide" },
                { keys: ["SUPER", "Q"],          desc: "Music" },
                { keys: ["SUPER", "S"],          desc: "Calendar" },
                { keys: ["SUPER", "C"],          desc: "Clipboard" },
                { keys: ["SUPER", "N"],          desc: "Network" },
                { keys: ["SUPER", "B"],          desc: "Battery" },
                { keys: ["SUPER", "V"],          desc: "Volume" },
                { keys: ["SUPER", "W"],          desc: "Wallpaper picker" },
                { keys: ["SUPER", "P"],          desc: "Movies" },
                { keys: ["SUPER", "SHIFT", "S"], desc: "Settings panel" },
                { keys: ["SUPER", "SHIFT", "T"], desc: "Focus timer" }
            ]
        }
    ]

    // -------------------------------------------------------------------------
    // INTRO ANIMATION
    // -------------------------------------------------------------------------
    property real introBase: 0.0
    property real introContent: 0.0

    Component.onCompleted: startupSequence.start()

    ParallelAnimation {
        id: startupSequence
        NumberAnimation { target: root; property: "introBase"; from: 0.0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: root; property: "introContent"; from: 0.0; to: 1.0; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.02 }
        }
    }

    SequentialAnimation {
        id: closeSequence
        ParallelAnimation {
            NumberAnimation { target: root; property: "introContent"; to: 0.0; duration: 140; easing.type: Easing.InExpo }
            NumberAnimation { target: root; property: "introBase"; to: 0.0; duration: 180; easing.type: Easing.InQuart }
        }
        ScriptAction { script: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]) }
    }

    // -------------------------------------------------------------------------
    // BACKGROUND AMBIENCE
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        opacity: introBase
        scale: 0.96 + (0.04 * introBase)

        Rectangle {
            anchors.fill: parent
            radius: root.s(16)
            color: root.base
            border.color: root.surface0
            border.width: 1
            clip: true

            property real t: 0
            NumberAnimation on t { from: 0; to: Math.PI * 2; duration: 20000; loops: Animation.Infinite; running: true }

            Rectangle {
                width: root.s(800); height: root.s(800); radius: root.s(400)
                x: parent.width * 0.55 + Math.cos(parent.t) * root.s(150)
                y: parent.height * 0.05 + Math.sin(parent.t * 1.5) * root.s(150)
                color: root.ambientPurple; opacity: 0.06
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blurMax: 100; blur: 1.0 }
            }
            Rectangle {
                width: root.s(900); height: root.s(900); radius: root.s(450)
                x: parent.width * 0.05 + Math.sin(parent.t * 0.8) * root.s(200)
                y: parent.height * 0.45 + Math.cos(parent.t * 1.2) * root.s(150)
                color: root.ambientBlue; opacity: 0.05
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blurMax: 110; blur: 1.0 }
            }
            Rectangle {
                width: root.s(700); height: root.s(700); radius: root.s(350)
                x: parent.width * 0.35 + Math.cos(parent.t * 1.1) * root.s(120)
                y: parent.height * 0.6 + Math.sin(parent.t * 0.9) * root.s(180)
                color: Qt.tint(root.peach, Qt.rgba(root.yellow.r, root.yellow.g, root.yellow.b, colorBlend))
                opacity: 0.04
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blurMax: 90; blur: 1.0 }
            }
        }
    }

    // -------------------------------------------------------------------------
    // REUSABLE: a single keycap
    // -------------------------------------------------------------------------
    component KeyCap: Rectangle {
        property string label: ""
        implicitWidth: capText.implicitWidth + root.s(16)
        implicitHeight: root.s(28)
        radius: root.s(7)
        color: Qt.alpha(root.surface1, 0.8)
        border.color: root.surface2
        border.width: 1
        Text {
            id: capText
            anchors.centerIn: parent
            text: parent.label
            font.family: "JetBrains Mono"
            font.weight: Font.Bold
            font.pixelSize: root.s(12)
            color: root.text
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: root.s(3) }
            height: root.s(2)
            radius: root.s(1)
            color: Qt.alpha(root.crust, 0.6)
        }
    }

    // -------------------------------------------------------------------------
    // REUSABLE: a category card
    // -------------------------------------------------------------------------
    component CategoryCard: Rectangle {
        property var section
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: cardCol.implicitHeight + root.s(32)
        radius: root.s(14)
        color: Qt.alpha(root.surface0, 0.45)
        border.color: cardMa.containsMouse ? Qt.alpha(root.clr(section.color), 0.7) : root.surface1
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 200 } }

        MouseArea { id: cardMa; anchors.fill: parent; hoverEnabled: true }

        ColumnLayout {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.s(16) }
            spacing: root.s(10)

            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(10)
                Rectangle {
                    width: root.s(30); height: root.s(30); radius: root.s(8)
                    color: Qt.alpha(root.clr(section.color), 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: section.icon
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: root.s(16)
                        color: root.clr(section.color)
                    }
                }
                Text {
                    text: section.title
                    font.family: "JetBrains Mono"
                    font.weight: Font.Black
                    font.pixelSize: root.s(15)
                    color: root.text
                    Layout.fillWidth: true
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.6) }

            Repeater {
                model: section.binds
                delegate: RowLayout {
                    id: bindRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: root.s(10)

                    Row {
                        spacing: root.s(5)
                        Repeater {
                            model: bindRow.modelData.keys
                            delegate: Row {
                                id: keyItem
                                required property var modelData
                                required property int index
                                spacing: root.s(5)
                                KeyCap { label: keyItem.modelData }
                                Text {
                                    text: "+"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(12)
                                    color: root.subtext0
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: keyItem.index < bindRow.modelData.keys.length - 1
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: modelData.desc
                        font.family: "JetBrains Mono"
                        font.pixelSize: root.s(12)
                        color: root.subtext0
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        Layout.maximumWidth: root.s(230)
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // MAIN CONTENT
    // -------------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.s(28)
        spacing: root.s(20)
        opacity: introContent
        scale: 0.98 + (0.02 * introContent)
        transform: Translate { y: root.s(15) * (1.0 - introContent) }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.s(15)

            Rectangle {
                width: root.s(46); height: root.s(46); radius: root.s(12)
                color: root.ambientPurple
                Text {
                    anchors.centerIn: parent
                    text: "󰌌"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: root.s(24)
                    color: root.base
                }
            }
            ColumnLayout {
                spacing: root.s(2)
                Text {
                    text: "Keybindings"
                    font.family: "JetBrains Mono"
                    font.weight: Font.Black
                    font.pixelSize: root.s(26)
                    color: root.text
                }
                Text {
                    text: "Hold SUPER and press a key · Esc to close"
                    font.family: "JetBrains Mono"
                    font.pixelSize: root.s(12)
                    color: root.subtext0
                }
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                width: root.s(38); height: root.s(38); radius: root.s(10)
                color: closeMa.containsMouse ? Qt.alpha(root.red, 0.12) : Qt.alpha(root.surface0, 0.5)
                border.color: closeMa.containsMouse ? root.red : root.surface1
                border.width: 1
                scale: closeMa.pressed ? 0.94 : 1.0
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: root.s(15)
                    color: closeMa.containsMouse ? root.red : root.subtext0
                }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: closeSequence.start()
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: columnsRow.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            RowLayout {
                id: columnsRow
                width: parent.width
                spacing: root.s(18)
                Layout.alignment: Qt.AlignTop

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: root.s(18)
                    Repeater {
                        model: root.leftSections
                        delegate: CategoryCard { required property var modelData; section: modelData }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: root.s(18)
                    Repeater {
                        model: root.rightSections
                        delegate: CategoryCard { required property var modelData; section: modelData }
                    }
                }
            }
        }
    }
}
