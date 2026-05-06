//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Item {
    id: root

    // =========================================================
    // --- MODULE CAPABILITIES EXPORT
    // =========================================================
    property int requestedLayoutTemplate: 1
    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true
    property string iconFont: "Font Awesome 6 Free Solid" 
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    // =========================================================
    // --- SCALING & DIMENSIONS
    // =========================================================
    function s(val) {
        return typeof scaleFunc === "function" ? scaleFunc(val) : val;
    }

    // baseW sets the inward extension. baseL sets the span along the edge.
    property real baseW: s(400) 
    property real baseL: s(340)

    property real preferredWidth: safeActiveEdge === "bottom" ? baseL + 50 : baseW
    property real preferredExtraLength: safeActiveEdge === "bottom" ? baseW : baseL

    property real counterRotation: {
        if (safeActiveEdge === "right") return 180;
        if (safeActiveEdge === "bottom") return 90;
        return 0; 
    }

    // =========================================================
    // --- MATUGEN THEMING & STYLING (MINIMALIST)
    // =========================================================
    property color cBase: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.base : "#1e1e2e"
    property color cMantle: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.mantle : "#181825"
    property color cSurface0: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface0 : "#313244"
    property color cSurface1: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.surface1 : "#45475a"
    property color cText: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.text : "#cdd6f4"
    property color cSubtext0: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.subtext0 : "#a6adc8"
    property color cMauve: typeof mochaColors !== "undefined" && mochaColors ? mochaColors.mauve : "#cba6f7"

    function alpha(color, a) { return Qt.rgba(color.r, color.g, color.b, a); }

    // =========================================================
    // --- SAFE STATE CACHE
    // =========================================================
    QtObject {
        id: stateCache
        
        property int activeMode: 0 // 0: Timer, 1: Stopwatch, 2: Pomodoro
        
        // Timer State
        property real timerTargetEpoch: 0 
        property int timerRemainingMs: 5 * 60 * 1000 
        property int timerPresetMs: 5 * 60 * 1000
        
        // Stopwatch State
        property real swStartEpoch: 0
        property int swAccumulatedMs: 0
        
        // Pomodoro State
        property int pomoState: 0 // 0: Work, 1: Short Break, 2: Long Break
        property real pomoTargetEpoch: 0 
        property int pomoRemainingMs: 25 * 60 * 1000 
        
        property int pomoWorkLimit: 25
        property int pomoShortBreakLimit: 5
        property int pomoLongBreakLimit: 15
        property int pomoTargetSessions: 4
        property int pomoSessionsCount: 0
    }

    property var swLapData: []

    // =========================================================
    // --- GLOBAL SHORTCUTS
    // =========================================================
    function toggleActiveTabState() {
        if (!root.isActiveTab) return;
        let now = Date.now();
        
        if (stateCache.activeMode === 0) { // Timer
            if (stateCache.timerTargetEpoch > 0) {
                stateCache.timerTargetEpoch = 0; // Pause
            } else {
                if (stateCache.timerRemainingMs <= 0) stateCache.timerRemainingMs = stateCache.timerPresetMs;
                stateCache.timerTargetEpoch = now + stateCache.timerRemainingMs;
            }
        } else if (stateCache.activeMode === 1) { // Stopwatch
            if (stateCache.swStartEpoch > 0) {
                stateCache.swAccumulatedMs += (now - stateCache.swStartEpoch);
                stateCache.swStartEpoch = 0;
            } else {
                stateCache.swStartEpoch = now;
            }
        } else if (stateCache.activeMode === 2) { // Pomodoro
            if (stateCache.pomoTargetEpoch > 0) stateCache.pomoTargetEpoch = 0;
            else stateCache.pomoTargetEpoch = now + stateCache.pomoRemainingMs;
        }
    }

    property bool isTimerRunning: stateCache.timerTargetEpoch > 0
    property bool isTimerIdle: !isTimerRunning && stateCache.timerRemainingMs === stateCache.timerPresetMs

    // Visibility gate — `parent` is the Loader from Floating.qml whose `visible`
    // is bound to `index === activeIndex && expandProgress > 0.01`. Falling back
    // to true keeps the module functional if loaded outside that Loader.
    property bool widgetVisible: parent !== null && parent.visible !== undefined ? parent.visible : true
    property bool anyTimerActive: stateCache.timerTargetEpoch > 0 || stateCache.swStartEpoch > 0 || stateCache.pomoTargetEpoch > 0

    property var interceptedShortcuts: {
        let arr = ["Return", "Enter"];
        if (stateCache.activeMode === 0 && isTimerIdle) {
            arr.push("Left", "Right", "Up", "Down");
        }
        return arr;
    }

    Shortcut { enabled: root.isActiveTab; sequence: "Return"; onActivated: root.toggleActiveTabState() }
    Shortcut { enabled: root.isActiveTab; sequence: "Enter"; onActivated: root.toggleActiveTabState() }

    // =========================================================
    // --- TIME FORMATTING HELPERS
    // =========================================================
    function formatTime(ms, includeMs) {
        if (ms < 0) ms = 0;
        let totalSeconds = Math.floor(ms / 1000);
        let hours = Math.floor(totalSeconds / 3600);
        let minutes = Math.floor((totalSeconds % 3600) / 60);
        let seconds = totalSeconds % 60;
        
        let out = "";
        if (hours > 0) out += hours.toString().padStart(2, '0') + ":";
        out += minutes.toString().padStart(2, '0') + ":" + seconds.toString().padStart(2, '0');
        
        if (includeMs) {
            let millis = Math.floor((ms % 1000) / 10);
            out += "." + millis.toString().padStart(2, '0');
        }
        return out;
    }

    // =========================================================
    // --- MASTER ORIENTATION CONTAINER
    // =========================================================
    Item {
        id: orientedRoot
        anchors.centerIn: parent
        width: (root.counterRotation % 180 !== 0) ? parent.height : parent.width
        height: (root.counterRotation % 180 !== 0) ? parent.width : parent.height
        rotation: root.counterRotation
        clip: true

        Rectangle {
            anchors.fill: parent
            color: root.cMantle
            radius: root.s(10)
            z: -1
        }

        // --- GLOBAL TICKER ---
        Timer {
            id: globalTicker
            interval: 32
            repeat: true
            running: root.widgetVisible && root.anyTimerActive
            onTriggered: {
                let now = Date.now();
                
                // Timer
                if (stateCache.timerTargetEpoch > 0) {
                    let rem = stateCache.timerTargetEpoch - now;
                    if (rem <= 0) {
                        stateCache.timerRemainingMs = 0;
                        stateCache.timerTargetEpoch = 0;
                    } else {
                        stateCache.timerRemainingMs = rem;
                    }
                }
                
                // Stopwatch
                if (stateCache.swStartEpoch > 0) {
                    stopwatchView.currentDisplayMs = stateCache.swAccumulatedMs + (now - stateCache.swStartEpoch);
                } else {
                    stopwatchView.currentDisplayMs = stateCache.swAccumulatedMs;
                }

                // Pomodoro
                if (stateCache.pomoTargetEpoch > 0) {
                    let rem = stateCache.pomoTargetEpoch - now;
                    if (rem <= 0) {
                        stateCache.pomoTargetEpoch = 0;
                        stateCache.pomoRemainingMs = 0;
                        pomodoroView.handleSessionComplete();
                    } else {
                        stateCache.pomoRemainingMs = rem;
                    }
                }
            }
        }

        // =========================================================
        // --- UI HEADER: MORPHING TAB BAR
        // =========================================================
        Rectangle {
            id: tabBar
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: root.s(15)
            width: root.s(280)
            height: root.s(36)
            radius: root.s(10)
            color: root.cSurface0
            border.width: 1
            border.color: root.cSurface1
            z: 10

            Rectangle {
                id: tabActiveHighlight
                y: root.s(2)
                height: root.s(32)
                radius: root.s(8)
                color: root.cMauve
                z: 0

                property int prevIdx: 0
                property int curIdx: stateCache.activeMode

                onCurIdxChanged: {
                    if (curIdx > prevIdx) { rightAnim.duration = 200; leftAnim.duration = 350; }
                    else if (curIdx < prevIdx) { leftAnim.duration = 200; rightAnim.duration = 350; }
                    prevIdx = curIdx;
                }

                property real stepSize: (parent.width - root.s(4)) / 3
                property real targetLeft: root.s(2) + (curIdx * stepSize)
                property real targetRight: targetLeft + stepSize

                property real actualLeft: targetLeft
                property real actualRight: targetRight

                Behavior on actualLeft { NumberAnimation { id: leftAnim; duration: 250; easing.type: Easing.OutExpo } }
                Behavior on actualRight { NumberAnimation { id: rightAnim; duration: 250; easing.type: Easing.OutExpo } }

                x: actualLeft
                width: actualRight - actualLeft
            }

            Row {
                anchors.fill: parent
                anchors.margins: root.s(2)
                z: 1

                Repeater {
                    model: ["Timer", "Stopwatch", "Pomodoro"]
                    Item {
                        width: (tabBar.width - root.s(4)) / 3
                        height: parent.height

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.family: "JetBrains Mono"
                            font.bold: true
                            font.pixelSize: root.s(12)
                            color: stateCache.activeMode === index ? root.cMantle : root.cText
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: stateCache.activeMode = index
                        }
                    }
                }
            }
        }

        // =========================================================
        // --- VIEW CONTAINERS ---
        // =========================================================
        Item {
            anchors.top: tabBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.s(15)

            // ---------------------------------------------------------
            // 1. TIMER VIEW
            // ---------------------------------------------------------
            Item {
                id: standardTimerView
                anchors.fill: parent
                visible: stateCache.activeMode === 0
                opacity: visible ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 250 } }

                property int activeEditSegment: 1 // 0: H, 1: M, 2: S

                function adjustSegment(dir) {
                    let h = Math.floor(stateCache.timerPresetMs / 3600000);
                    let m = Math.floor((stateCache.timerPresetMs % 3600000) / 60000);
                    let sec = Math.floor((stateCache.timerPresetMs % 60000) / 1000);
                    
                    if (activeEditSegment === 0) {
                        h = Math.max(0, Math.min(99, h + dir));
                    } else if (activeEditSegment === 1) {
                        m += dir;
                        if (m > 59) { m = 0; h++; }
                        else if (m < 0) { if (h > 0) { m = 59; h--; } else { m = 0; } }
                    } else if (activeEditSegment === 2) {
                        sec += dir;
                        if (sec > 59) { 
                            sec = 0; m++; 
                            if (m > 59) { m = 0; h++; } 
                        } else if (sec < 0) { 
                            if (m > 0) { sec = 59; m--; } 
                            else if (h > 0) { sec = 59; m = 59; h--; } 
                            else { sec = 0; }
                        }
                    }
                    
                    let total = (h * 3600 + m * 60 + sec) * 1000;
                    stateCache.timerPresetMs = total;
                    stateCache.timerRemainingMs = total;
                }

                Shortcut { enabled: root.isActiveTab && stateCache.activeMode === 0 && root.isTimerIdle; sequence: "Left"; onActivated: standardTimerView.activeEditSegment = Math.max(0, standardTimerView.activeEditSegment - 1) }
                Shortcut { enabled: root.isActiveTab && stateCache.activeMode === 0 && root.isTimerIdle; sequence: "Right"; onActivated: standardTimerView.activeEditSegment = Math.min(2, standardTimerView.activeEditSegment + 1) }
                Shortcut { enabled: root.isActiveTab && stateCache.activeMode === 0 && root.isTimerIdle; sequence: "Up"; onActivated: standardTimerView.adjustSegment(1) }
                Shortcut { enabled: root.isActiveTab && stateCache.activeMode === 0 && root.isTimerIdle; sequence: "Down"; onActivated: standardTimerView.adjustSegment(-1) }

                component TimerSegment : Column {
                    property int value: 0
                    property bool isSelected: false
                    signal upClicked()
                    signal downClicked()
                    signal segmentClicked()

                    spacing: 0

                    property real upOffset: 0
                    property real downOffset: 0

                    SequentialAnimation on upOffset {
                        running: isSelected && root.isTimerIdle && root.widgetVisible
                        loops: Animation.Infinite
                        NumberAnimation { to: -root.s(4); duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutSine }
                    }
                    onIsSelectedChanged: if (!isSelected) { upOffset = 0; downOffset = 0; }

                    SequentialAnimation on downOffset {
                        running: isSelected && root.isTimerIdle && root.widgetVisible
                        loops: Animation.Infinite
                        NumberAnimation { to: root.s(4); duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutSine }
                    }

                    Item { // UP ARROW
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.s(48); height: root.s(24)
                        Text { 
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: upOffset
                            text: "\uF077"
                            font.family: root.iconFont
                            color: isSelected ? root.cMauve : root.cSubtext0
                            font.pixelSize: root.s(16)
                            opacity: isSelected ? 1.0 : 0.2
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: upClicked(); cursorShape: Qt.PointingHandCursor }
                    }

                    Item { // DIGITS
                        width: root.s(68); height: root.s(68)
                        Text {
                            anchors.centerIn: parent
                            text: value.toString().padStart(2, '0')
                            font.family: "JetBrains Mono"
                            font.weight: Font.Black
                            font.pixelSize: root.s(54)
                            color: isSelected ? root.cMauve : root.cText
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: segmentClicked()
                            cursorShape: Qt.PointingHandCursor
                        }
                    }

                    Item { // DOWN ARROW
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.s(48); height: root.s(24)
                        Text { 
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: downOffset
                            text: "\uF078"
                            font.family: root.iconFont
                            color: isSelected ? root.cMauve : root.cSubtext0
                            font.pixelSize: root.s(16)
                            opacity: isSelected ? 1.0 : 0.2
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: downClicked(); cursorShape: Qt.PointingHandCursor }
                    }
                }

                // Perfectly centers the content between the Tab Bar and the Controls
                Item {
                    anchors.top: parent.top
                    anchors.bottom: timerControlsRow.top
                    anchors.left: parent.left
                    anchors.right: parent.right

                    // Running Text Display
                    Text {
                        anchors.centerIn: parent
                        text: root.formatTime(stateCache.timerRemainingMs, false)
                        font.family: "JetBrains Mono"
                        font.weight: Font.Black
                        font.pixelSize: root.s(68)
                        color: stateCache.timerRemainingMs === 0 && !root.isTimerRunning ? root.cMauve : root.cText
                        visible: !root.isTimerIdle
                    }

                    // Floating Keyboard Editor (Visible when idle)
                    Row {
                        anchors.centerIn: parent
                        spacing: root.s(2)
                        visible: root.isTimerIdle

                        TimerSegment {
                            value: Math.floor(stateCache.timerPresetMs / 3600000)
                            isSelected: standardTimerView.activeEditSegment === 0
                            onUpClicked: { standardTimerView.activeEditSegment = 0; standardTimerView.adjustSegment(1); }
                            onDownClicked: { standardTimerView.activeEditSegment = 0; standardTimerView.adjustSegment(-1); }
                            onSegmentClicked: standardTimerView.activeEditSegment = 0
                        }

                        Text { 
                            text: ":"
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(54)
                            color: root.alpha(root.cSubtext0, 0.4)
                            anchors.verticalCenter: parent.verticalCenter 
                        }

                        TimerSegment {
                            value: Math.floor((stateCache.timerPresetMs % 3600000) / 60000)
                            isSelected: standardTimerView.activeEditSegment === 1
                            onUpClicked: { standardTimerView.activeEditSegment = 1; standardTimerView.adjustSegment(1); }
                            onDownClicked: { standardTimerView.activeEditSegment = 1; standardTimerView.adjustSegment(-1); }
                            onSegmentClicked: standardTimerView.activeEditSegment = 1
                        }

                        Text { 
                            text: ":"
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(54)
                            color: root.alpha(root.cSubtext0, 0.4)
                            anchors.verticalCenter: parent.verticalCenter 
                        }

                        TimerSegment {
                            value: Math.floor((stateCache.timerPresetMs % 60000) / 1000)
                            isSelected: standardTimerView.activeEditSegment === 2
                            onUpClicked: { standardTimerView.activeEditSegment = 2; standardTimerView.adjustSegment(1); }
                            onDownClicked: { standardTimerView.activeEditSegment = 2; standardTimerView.adjustSegment(-1); }
                            onSegmentClicked: standardTimerView.activeEditSegment = 2
                        }
                    }
                }

                RowLayout {
                    id: timerControlsRow
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.s(10)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.s(20)

                    Rectangle {
                        width: root.s(50); height: root.s(50); radius: root.s(10)
                        color: root.cSurface0; border.width: 1; border.color: root.cSurface1
                        Text { anchors.centerIn: parent; text: "\uF0E2"; font.family: root.iconFont; font.pixelSize: root.s(16); color: root.cText }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { 
                                if (!root.isTimerIdle) {
                                    // Stop and revert to preset
                                    stateCache.timerTargetEpoch = 0; 
                                    stateCache.timerRemainingMs = stateCache.timerPresetMs; 
                                } else {
                                    // Fully idle, so clear out the numbers
                                    stateCache.timerPresetMs = 0;
                                    stateCache.timerRemainingMs = 0;
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: root.s(64); height: root.s(64); radius: root.s(10)
                        color: root.cMauve
                        Text {
                            anchors.centerIn: parent
                            text: root.isTimerRunning ? "\uF04C" : "\uF04B"
                            font.family: root.iconFont; font.pixelSize: root.s(24); color: root.cMantle
                            anchors.horizontalCenterOffset: root.isTimerRunning ? 0 : root.s(2)
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleActiveTabState()
                        }
                    }
                }
            }

            // ---------------------------------------------------------
            // 2. STOPWATCH VIEW
            // ---------------------------------------------------------
            Item {
                id: stopwatchView
                anchors.fill: parent
                visible: stateCache.activeMode === 1
                opacity: visible ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 250 } }

                property bool isRunning: stateCache.swStartEpoch > 0
                property real currentDisplayMs: 0 

                // Perfectly centers the content between the Tab Bar and the Controls
                Item {
                    id: swContentArea
                    anchors.top: parent.top
                    anchors.bottom: swControlsRow.top
                    anchors.left: parent.left
                    anchors.right: parent.right

                    Column {
                        anchors.centerIn: parent
                        spacing: root.s(15)

                        Text {
                            id: swTimeText
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.formatTime(stopwatchView.currentDisplayMs, true)
                            font.family: "JetBrains Mono"
                            font.weight: Font.Black
                            font.pixelSize: root.s(52)
                            color: root.cText
                        }

                        // Lap List
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.s(280)
                            // Dynamically cap the height to prevent overflowing the container
                            height: root.swLapData.length > 0 ? Math.min(root.s(130), swContentArea.height - swTimeText.height - root.s(15)) : 0
                            visible: root.swLapData.length > 0
                            color: "transparent"
                            clip: true

                            ListView {
                                id: lapList
                                anchors.fill: parent
                                model: root.swLapData.length
                                spacing: root.s(6)
                                
                                delegate: Rectangle {
                                    width: lapList.width
                                    height: root.s(32)
                                    radius: root.s(10)
                                    color: root.cSurface0
                                    border.width: 1
                                    border.color: root.cSurface1
                                    
                                    property int trueIdx: root.swLapData.length - 1 - index
                                    property var lapItem: root.swLapData[trueIdx]

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.s(15); anchors.rightMargin: root.s(15)
                                        Text { text: "Lap " + (trueIdx + 1); color: root.cSubtext0; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); font.bold: true; Layout.fillWidth: true }
                                        Text { text: lapItem ? "+" + root.formatTime(lapItem.diff, true) : ""; color: root.cMauve; font.family: "JetBrains Mono"; font.pixelSize: root.s(12) }
                                        Text { text: lapItem ? root.formatTime(lapItem.total, true) : ""; color: root.cText; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); font.bold: true; Layout.alignment: Qt.AlignRight }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    id: swControlsRow
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.s(10)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.s(20)

                    Rectangle {
                        width: root.s(50); height: root.s(50); radius: root.s(10)
                        color: root.cSurface0; border.width: 1; border.color: root.cSurface1
                        Text { 
                            anchors.centerIn: parent
                            text: stopwatchView.isRunning ? "\uF024" : "\uF0E2" 
                            font.family: root.iconFont; font.pixelSize: root.s(16); color: root.cText 
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (stopwatchView.isRunning) {
                                    let nowMs = stopwatchView.currentDisplayMs;
                                    let lastMs = root.swLapData.length > 0 ? root.swLapData[root.swLapData.length - 1].total : 0;
                                    let temp = root.swLapData.slice();
                                    temp.push({ total: nowMs, diff: nowMs - lastMs });
                                    root.swLapData = temp;
                                } else {
                                    stateCache.swStartEpoch = 0;
                                    stateCache.swAccumulatedMs = 0;
                                    root.swLapData = [];
                                    stopwatchView.currentDisplayMs = 0;
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: root.s(64); height: root.s(64); radius: root.s(10)
                        color: root.cMauve
                        Text {
                            anchors.centerIn: parent
                            text: stopwatchView.isRunning ? "\uF04C" : "\uF04B"
                            font.family: root.iconFont; font.pixelSize: root.s(24); color: root.cMantle
                            anchors.horizontalCenterOffset: stopwatchView.isRunning ? 0 : root.s(2)
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleActiveTabState()
                        }
                    }
                }
            }

            // ---------------------------------------------------------
            // 3. POMODORO VIEW
            // ---------------------------------------------------------
            Item {
                id: pomodoroView
                anchors.fill: parent
                visible: stateCache.activeMode === 2
                opacity: visible ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 250 } }

                property bool isRunning: stateCache.pomoTargetEpoch > 0
                property bool showSettings: false

                function getPhaseColor() {
                    if (stateCache.pomoState === 0) return root.cMauve; // Work
                    if (stateCache.pomoState === 1) return Qt.rgba(166/255, 227/255, 161/255, 1.0); // Green / Short Break
                    return root.cSurface1; // Long Break
                }

                function getPhaseLabel() {
                    if (stateCache.pomoState === 0) return "FOCUS";
                    if (stateCache.pomoState === 1) return "SHORT BREAK";
                    return "LONG BREAK";
                }

                function handleSessionComplete() {
                    if (stateCache.pomoState === 0) { // Work finished
                        stateCache.pomoSessionsCount++;
                        if (stateCache.pomoSessionsCount >= stateCache.pomoTargetSessions) {
                            stateCache.pomoState = 2; // Long Break
                            stateCache.pomoSessionsCount = 0;
                            stateCache.pomoRemainingMs = stateCache.pomoLongBreakLimit * 60 * 1000;
                        } else {
                            stateCache.pomoState = 1; // Short break
                            stateCache.pomoRemainingMs = stateCache.pomoShortBreakLimit * 60 * 1000;
                        }
                    } else { // Break finished
                        stateCache.pomoState = 0; // Back to work
                        stateCache.pomoRemainingMs = stateCache.pomoWorkLimit * 60 * 1000;
                    }
                }

                // Perfectly centers the content between the Tab Bar and the Controls
                Item {
                    anchors.top: parent.top
                    anchors.bottom: pomoControlsRow.top
                    anchors.left: parent.left
                    anchors.right: parent.right

                    // Main Clock View
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: root.s(10)
                        visible: !pomodoroView.showSettings

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: pomodoroView.getPhaseLabel() + " (" + stateCache.pomoSessionsCount + "/" + stateCache.pomoTargetSessions + ")"
                            font.family: "JetBrains Mono"; font.bold: true; font.pixelSize: root.s(14)
                            color: pomodoroView.getPhaseColor()
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.formatTime(stateCache.pomoRemainingMs, false)
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(68)
                            color: root.cText
                        }
                    }

                    // Settings View
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.s(280)
                        height: root.s(160)
                        radius: root.s(10)
                        color: root.cSurface0
                        border.width: 1
                        border.color: root.cSurface1
                        visible: pomodoroView.showSettings

                        Column {
                            anchors.centerIn: parent
                            spacing: root.s(12)

                            Repeater {
                                model: [
                                    { label: "Work (m)", target: "pomoWorkLimit", step: 5, min: 5, max: 60 },
                                    { label: "Short Break (m)", target: "pomoShortBreakLimit", step: 1, min: 1, max: 15 },
                                    { label: "Long Break (m)", target: "pomoLongBreakLimit", step: 5, min: 5, max: 45 },
                                    { label: "Sessions", target: "pomoTargetSessions", step: 1, min: 1, max: 10 }
                                ]
                                RowLayout {
                                    width: root.s(240)
                                    Text { text: modelData.label; color: root.cSubtext0; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); Layout.fillWidth: true }
                                    Rectangle {
                                        width: root.s(24); height: root.s(24); radius: root.s(6); color: root.cSurface1
                                        Text { anchors.centerIn: parent; text: "-"; color: root.cText; font.family: "JetBrains Mono"; font.pixelSize: root.s(14) }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: stateCache[modelData.target] = Math.max(modelData.min, stateCache[modelData.target] - modelData.step) }
                                    }
                                    Text { text: stateCache[modelData.target]; color: root.cText; font.family: "JetBrains Mono"; font.bold: true; font.pixelSize: root.s(14); Layout.minimumWidth: root.s(24); horizontalAlignment: Text.AlignHCenter }
                                    Rectangle {
                                        width: root.s(24); height: root.s(24); radius: root.s(6); color: root.cSurface1
                                        Text { anchors.centerIn: parent; text: "+"; color: root.cText; font.family: "JetBrains Mono"; font.pixelSize: root.s(14) }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: stateCache[modelData.target] = Math.min(modelData.max, stateCache[modelData.target] + modelData.step) }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    id: pomoControlsRow
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.s(10)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.s(20)

                    Rectangle {
                        width: root.s(50); height: root.s(50); radius: root.s(10)
                        color: root.cSurface0; border.width: 1; border.color: root.cSurface1
                        Text { anchors.centerIn: parent; text: "\uF013"; font.family: root.iconFont; font.pixelSize: root.s(16); color: pomodoroView.showSettings ? root.cMauve : root.cText }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: pomodoroView.showSettings = !pomodoroView.showSettings
                        }
                    }

                    Rectangle {
                        width: root.s(64); height: root.s(64); radius: root.s(10)
                        color: pomodoroView.getPhaseColor()
                        Text {
                            anchors.centerIn: parent
                            text: pomodoroView.isRunning ? "\uF04C" : "\uF04B"
                            font.family: root.iconFont; font.pixelSize: root.s(24); color: root.cMantle
                            anchors.horizontalCenterOffset: pomodoroView.isRunning ? 0 : root.s(2)
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (pomodoroView.showSettings) pomodoroView.showSettings = false;
                                root.toggleActiveTabState();
                            }
                        }
                    }

                    Rectangle {
                        width: root.s(50); height: root.s(50); radius: root.s(10)
                        color: root.cSurface0; border.width: 1; border.color: root.cSurface1
                        Text { anchors.centerIn: parent; text: "\uF051"; font.family: root.iconFont; font.pixelSize: root.s(16); color: root.cText } // Skip
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                stateCache.pomoTargetEpoch = 0;
                                pomodoroView.handleSessionComplete();
                            }
                        }
                    }
                }
            }
        }
    }
}

