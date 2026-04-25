import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: Colors.base

    // Core States
    property int currentUserIndex: 0
    property int nextUserIndexTarget: 0
    property string currentUserName: userModel.count > 0 ? userModel.data(userModel.index(currentUserIndex, 0), 257) : "User"
    
    property bool inputActive: false
    property bool loginFailed: false

    Component.onCompleted: {
        // Find the index of the last logged-in user at startup
        var idx = 0;
        if (userModel.lastUser !== "") {
            for (var i = 0; i < userModel.count; ++i) {
                if (userModel.data(userModel.index(i, 0), 257) === userModel.lastUser) {
                    idx = i;
                    break;
                }
            }
        }
        currentUserIndex = idx;
    }

    function nextUser() {
        if (userModel.count <= 1 || switchUserAnim.running) return;
        nextUserIndexTarget = (currentUserIndex + 1) % userModel.count;
        switchUserAnim.restart();
    }

    function prevUser() {
        if (userModel.count <= 1 || switchUserAnim.running) return;
        nextUserIndexTarget = (currentUserIndex - 1 + userModel.count) % userModel.count;
        switchUserAnim.restart();
    }

    onInputActiveChanged: {
        if (inputActive) {
            passwordField.forceActiveFocus()
        } else {
            root.forceActiveFocus()
            passwordField.text = ""
            loginFailed = false
            errorMessage.opacity = 0.0
        }
    }

    // Smooth transition animation for switching users
    SequentialAnimation {
        id: switchUserAnim
        ParallelAnimation {
            NumberAnimation { target: innerAuthLayout; property: "opacity"; to: 0.0; duration: 150; easing.type: Easing.InSine }
            NumberAnimation { target: innerAuthLayout; property: "scale"; to: 0.95; duration: 150; easing.type: Easing.InSine }
        }
        ScriptAction {
            script: {
                root.currentUserIndex = root.nextUserIndexTarget;
                passwordField.text = "";
                root.loginFailed = false;
                errorMessage.opacity = 0.0;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: innerAuthLayout; property: "opacity"; to: 1.0; duration: 200; easing.type: Easing.OutOutExpo }
            NumberAnimation { target: innerAuthLayout; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
        }
    }

    // Capture global key presses to activate input mode
    Item {
        anchors.fill: parent
        focus: !root.inputActive
        Keys.onPressed: (event) => {
            if (!root.inputActive) {
                root.inputActive = true
                event.accepted = true
            }
        }
    }

    // Click anywhere to activate input mode
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (!root.inputActive) {
                root.inputActive = true
            } else {
                passwordField.forceActiveFocus()
            }
        }
    }

    // SDDM Connections for error handling
    Connections {
        target: sddm
        function onLoginFailed() {
            passwordField.text = ""
            root.loginFailed = true
            errorMessage.opacity = 1.0
            shakeAnim.restart()
            errorHideTimer.restart()
        }
    }

    // 1. BACKGROUND & BLUR
    Item {
        anchors.fill: parent

        Image {
            id: bgWallpaper
            anchors.fill: parent
            source: config.background
            fillMode: Image.PreserveAspectCrop
            visible: false 
        }

        MultiEffect {
            anchors.fill: bgWallpaper
            source: bgWallpaper
            blurEnabled: true
            blurMax: 64
            blur: 1.0
        }
        
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.25 
        }
    }

    // 2. MAIN CONTENT LAYER (Cross-fading Clock & Auth)
    Item {
        anchors.fill: parent

        // --- CLOCK MODULE (Idle State) ---
        ColumnLayout {
            id: clockModule
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.inputActive ? -120 : -40
            spacing: -10
            
            opacity: root.inputActive ? 0.0 : 1.0
            scale: root.inputActive ? 0.9 : 1.0
            visible: opacity > 0.01

            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            Text {
                id: timeText
                text: Qt.formatTime(new Date(), "hh:mm")
                font.family: "JetBrains Mono"
                font.pixelSize: 140
                font.weight: Font.Bold
                color: Colors.text
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                id: dateText
                text: Qt.formatDate(new Date(), "dddd, MMMM dd")
                font.family: "JetBrains Mono"
                font.pixelSize: 22
                font.weight: Font.Bold
                color: Colors.text
                Layout.alignment: Qt.AlignHCenter
            }

            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: {
                    timeText.text = Qt.formatTime(new Date(), "hh:mm")
                    dateText.text = Qt.formatDate(new Date(), "dddd, MMMM dd")
                }
            }
        }

        // --- AUTHENTICATION MODULE (Input State) ---
        RowLayout {
            id: authModule
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.inputActive ? -40 : 40
            spacing: 24 
            
            opacity: root.inputActive ? 1.0 : 0.0
            scale: root.inputActive ? 1.0 : 0.9
            visible: opacity > 0.01

            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            // Left Arrow
            Rectangle {
                width: 48; height: 48; radius: 24
                Layout.alignment: Qt.AlignVCenter
                color: leftArrowMa.containsMouse ? Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.1) : "transparent"
                visible: userModel.count > 1
                
                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: 24
                    color: Colors.text
                }
                
                MouseArea {
                    id: leftArrowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.prevUser()
                }
            }

            // Wrapper to isolate the user swap animation from the arrows
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: innerAuthLayout.implicitWidth
                Layout.preferredHeight: innerAuthLayout.implicitHeight

                RowLayout {
                    id: innerAuthLayout
                    anchors.centerIn: parent
                    spacing: 32

                    // Avatar
                    Item {
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignTop
                        width: 150; height: 150
                    
                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            source: "/usr/share/sddm/faces/" + root.currentUserName + ".face.icon"
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                            layer.enabled: true
                            onStatusChanged: {
                                if (status == Image.Error) source = ""
                            }
                        }
                    
                        Rectangle {
                            id: avatarMask
                            anchors.fill: parent
                            radius: 75
                            visible: false
                            layer.enabled: true
                        }
                    
                        MultiEffect {
                            anchors.fill: parent
                            source: avatarImage
                            maskEnabled: true
                            maskSource: avatarMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                        }
                    
                        Rectangle {
                            anchors.fill: parent
                            radius: 75
                            color: "transparent"
                            border.color: root.loginFailed ? Colors.red : Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.5)
                            border.width: root.loginFailed ? 4 : 3
                    
                            Behavior on border.color { ColorAnimation { duration: 300 } }
                            Behavior on border.width { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                        }
                    }
                    
                    // Details & Input
                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 12

                        Text {
                            text: root.currentUserName
                            font.family: "JetBrains Mono"
                            font.pixelSize: 28
                            font.weight: Font.Bold
                            color: Colors.text
                            Layout.alignment: Qt.AlignLeft
                        }

                        Rectangle {
                            Layout.preferredWidth: 280
                            Layout.preferredHeight: 60
                            radius: 30
                            clip: true 
                            
                            color: root.loginFailed ? Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.1) : Qt.rgba(Colors.surface0.r, Colors.surface0.g, Colors.surface0.b, 0.5)
                            border.width: 2
                            border.color: {
                                if (root.loginFailed) return Colors.red;
                                if (passwordField.focus) return Colors.text;
                                return Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.08);
                            }

                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutExpo } }
                            Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutExpo } }
                            
                            transform: Translate { id: shakeTranslate; x: 0 }
                            
                            // Elegant Shake Animation on Error
                            SequentialAnimation {
                                id: shakeAnim
                                NumberAnimation { target: shakeTranslate; property: "x"; from: 0; to: -8; duration: 120; easing.type: Easing.InOutSine }
                                NumberAnimation { target: shakeTranslate; property: "x"; from: -8; to: 8; duration: 120; easing.type: Easing.InOutSine }
                                NumberAnimation { target: shakeTranslate; property: "x"; from: 8; to: 0; duration: 120; easing.type: Easing.InOutSine }
                            }

                            TextInput {
                                id: passwordField
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true 
                                echoMode: TextInput.Password
                                font.family: "JetBrains Mono"
                                font.pixelSize: 24
                                color: root.loginFailed ? Colors.red : Colors.text

                                Text {
                                    text: "Password..."
                                    color: Qt.rgba(Colors.subtext0.r, Colors.subtext0.g, Colors.subtext0.b, 0.5)
                                    font: passwordField.font
                                    visible: !passwordField.text && !passwordField.inputMethodComposing
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Keys.onEscapePressed: {
                                    root.inputActive = false
                                }

                                // Tab navigation
                                Keys.onPressed: (event) => {
                                    if (event.key === Qt.Key_Tab) {
                                        root.nextUser()
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Backtab) {
                                        root.prevUser()
                                        event.accepted = true
                                    }
                                }

                                onAccepted: {
                                    if (text !== "") {
                                        errorMessage.opacity = 0.0
                                        sddm.login(root.currentUserName, text, sessionMenu.currentIndex)
                                    }
                                }
                                
                                onTextChanged: {
                                    if (root.loginFailed) {
                                        root.loginFailed = false
                                        errorMessage.opacity = 0.0
                                    }
                                }
                            }
                        }

                        // Error Message Label
                        Text {
                            id: errorMessage
                            Layout.alignment: Qt.AlignHCenter
                            text: "Login failed. Please try again."
                            font.family: "JetBrains Mono"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: Colors.red
                            opacity: 0.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            Timer {
                                id: errorHideTimer
                                interval: 3000
                                onTriggered: errorMessage.opacity = 0.0
                            }
                        }
                    }
                }
            }

            // Right Arrow
            Rectangle {
                width: 48; height: 48; radius: 24
                Layout.alignment: Qt.AlignVCenter
                color: rightArrowMa.containsMouse ? Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.1) : "transparent"
                visible: userModel.count > 1
                
                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: 24
                    color: Colors.text
                }
                
                MouseArea {
                    id: rightArrowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.nextUser()
                }
            }
        }
    }
    
    // 3. BOTTOM CONTROLS (Session & Power)
    ColumnLayout {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 40
        spacing: 16

        // Styled Session Switcher 
        ComboBox {
            id: sessionMenu
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 192
            Layout.preferredHeight: 48
            model: sessionModel
            textRole: "name"
            currentIndex: sessionModel.lastIndex
            font.family: "JetBrains Mono"
            font.pixelSize: 14
            
            background: Rectangle {
                color: sessionMenu.hovered || sessionMenu.popup.visible ? Qt.rgba(Colors.surface0.r, Colors.surface0.g, Colors.surface0.b, 0.7) : Qt.rgba(Colors.surface0.r, Colors.surface0.g, Colors.surface0.b, 0.5)
                radius: 24
                border.width: 1
                border.color: sessionMenu.hovered || sessionMenu.popup.visible ? Colors.text : Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.1)
                
                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }
            }

            contentItem: Text {
                leftPadding: 16
                rightPadding: sessionMenu.indicator.width + 12
                text: "󰧨  " + sessionMenu.currentText
                color: sessionMenu.hovered || sessionMenu.popup.visible ? Colors.text : Colors.subtext0
                font: sessionMenu.font
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            indicator: Text {
                x: sessionMenu.width - width - 16
                y: sessionMenu.topPadding + (sessionMenu.availableHeight - height) / 2
                text: sessionMenu.popup.visible ? "" : ""
                font.family: "Iosevka Nerd Font"
                font.pixelSize: 14
                color: sessionMenu.hovered || sessionMenu.popup.visible ? Colors.text : Colors.subtext0
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            popup: Popup {
                y: -(sessionMenu.popup.height + 8)
                width: sessionMenu.width
                padding: 8
                
                background: Rectangle {
                    color: Qt.rgba(Colors.base.r, Colors.base.g, Colors.base.b, 0.95)
                    radius: 16
                    border.width: 1
                    border.color: Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.15)
                }

                contentItem: ListView {
                    clip: true
                    implicitHeight: Math.min(contentHeight, 200)
                    model: sessionMenu.popup.visible ? sessionMenu.delegateModel : null
                    ScrollIndicator.vertical: ScrollIndicator { }
                }
            }

            delegate: ItemDelegate {
                width: sessionMenu.popup.width - 16
                padding: 12
                
                contentItem: Text {
                    text: model.name
                    color: hovered ? Colors.base : Colors.text
                    font: sessionMenu.font
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                
                background: Rectangle {
                    radius: 8
                    color: hovered ? Colors.text : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }

        // Power Buttons Row
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 24

            // Suspend
            Rectangle {
                width: 48; height: 48; radius: 24
                color: suspendMa.containsMouse ? Qt.rgba(Colors.mauve.r, Colors.mauve.g, Colors.mauve.b, 0.2) : Qt.rgba(Colors.surface0.r, Colors.surface0.g, Colors.surface0.b, 0.5)
                border.color: suspendMa.containsMouse ? Colors.mauve : Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.1)
                
                scale: suspendMa.pressed ? 0.9 : (suspendMa.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰒲"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: 20
                    color: suspendMa.containsMouse ? Colors.mauve : Colors.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                MouseArea {
                    id: suspendMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sddm.suspend()
                }
            }

            // Reboot
            Rectangle {
                width: 48; height: 48; radius: 24
                color: rebootMa.containsMouse ? Qt.rgba(Colors.blue.r, Colors.blue.g, Colors.blue.b, 0.2) : Qt.rgba(Colors.surface0.r, Colors.surface0.g, Colors.surface0.b, 0.5)
                border.color: rebootMa.containsMouse ? Colors.blue : Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.1)
                
                scale: rebootMa.pressed ? 0.9 : (rebootMa.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰜉"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: 20
                    color: rebootMa.containsMouse ? Colors.blue : Colors.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                MouseArea {
                    id: rebootMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sddm.reboot()
                }
            }

            // Power Off
            Rectangle {
                width: 48; height: 48; radius: 24
                color: powerMa.containsMouse ? Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.2) : Qt.rgba(Colors.surface0.r, Colors.surface0.g, Colors.surface0.b, 0.5)
                border.color: powerMa.containsMouse ? Colors.red : Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.1)
                
                scale: powerMa.pressed ? 0.9 : (powerMa.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰐥"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: 20
                    color: powerMa.containsMouse ? Colors.red : Colors.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                MouseArea {
                    id: powerMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sddm.powerOff()
                }
            }
        }
    }
}
