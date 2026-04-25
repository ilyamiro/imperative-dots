import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window
import QtCore
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }

    function s(val) { return scaler.s(val); }

    Shortcut {
        sequence: "Tab"
        onActivated: {
            if (window.pendingWifiId !== "") {
                window.pendingWifiId = ""; window.pendingWifiSsid = "";
                return;
            }
            window.playSfx("switch.wav");
            let modes = [];
            if (window.ethPresent) modes.push("eth");
            if (window.wifiPresent) modes.push("wifi");
            if (window.btPresent) modes.push("bt");
            if (modes.length > 1) {
                let idx = modes.indexOf(window.activeMode);
                let nextMode = modes[(idx + 1) % modes.length];
                if (window.activeMode !== nextMode) {
                    window.powerAnimAllowed = false;
                    powerAnimBlocker.restart();
                    window.activeMode = nextMode;
                }
            }
        }
    }

    Settings {
        id: cache
        category: "QS_NetworkWidgetUnified"
        property string lastWifiSsid: ""
        property string lastWifiJson: ""
        property string lastBtJson: ""
        property string lastEthJson: ""
    }

    readonly property string cacheDir: Quickshell.env("XDG_RUNTIME_DIR") ? (Quickshell.env("XDG_RUNTIME_DIR") + "/qs_network") : (Quickshell.env("HOME") + "/.cache/qs_network")
    readonly property string modeFilePath: cacheDir + "/mode"

    property bool ethPresent: false
    property bool wifiPresent: false
    property bool btPresent: false

    property bool ethFirstLoad: true
    property bool wifiFirstLoad: true
    property bool btFirstLoad: true

    property bool powerAnimAllowed: false
    Timer { id: powerAnimBlocker; interval: 250; running: true; onTriggered: window.powerAnimAllowed = true }

    // FAILSAGE TIMER: If scripts hang indefinitely, unblock validation after 1.5 seconds so the UI isn't stuck!
    Timer {
        id: firstLoadFailsafe
        interval: 1500
        running: true
        onTriggered: {
            let blocked = false;
            if (window.ethFirstLoad) { window.ethFirstLoad = false; blocked = true; }
            if (window.wifiFirstLoad) { window.wifiFirstLoad = false; blocked = true; }
            if (window.btFirstLoad) { window.btFirstLoad = false; blocked = true; }
            if (blocked) window.validateActiveMode();
        }
    }

    property bool isValidatingMode: false
    function validateActiveMode() {
        if (window.ethFirstLoad || window.wifiFirstLoad || window.btFirstLoad) return;
        if (isValidatingMode) return;
        isValidatingMode = true;

        let validModes = [];
        if (window.ethPresent) validModes.push("eth");
        if (window.wifiPresent) validModes.push("wifi");
        if (window.btPresent) validModes.push("bt");

        if (validModes.length > 0 && validModes.indexOf(window.activeMode) === -1) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.activeMode = validModes[0];
        }

        isValidatingMode = false;
    }

    property bool ignoreNextModeFileUpdate: false
    Process {
        id: modeReader
        command: ["bash", "-c", "cat '" + window.modeFilePath + "' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let mode = this.text.trim();
                if ((mode === "wifi" || mode === "bt" || mode === "eth") && window.activeMode !== mode) {
                    if ((mode === "eth" && window.ethPresent) || 
                        (mode === "wifi" && window.wifiPresent) || 
                        (mode === "bt" && window.btPresent)) {
                        window.powerAnimAllowed = false;
                        powerAnimBlocker.restart();
                        window.ignoreNextModeFileUpdate = true;
                        window.activeMode = mode;
                    }
                }
            }
        }
    }

    Timer { interval: 100; running: true; repeat: true; onTriggered: modeReader.running = true }

    Component.onCompleted: {
        window.powerAnimAllowed = false;
        powerAnimBlocker.restart();
        Quickshell.execDetached(["bash", "-c", "mkdir -p '" + window.cacheDir + "'; if [ ! -f '" + window.modeFilePath + "' ]; then echo '" + activeMode + "' > '" + window.modeFilePath + "'; fi"]);
        
        let hasCache = false;
        if (cache.lastEthJson !== "") { processEthJson(cache.lastEthJson, true); hasCache = true; }
        if (cache.lastWifiJson !== "") { processWifiJson(cache.lastWifiJson, true); hasCache = true; }
        if (cache.lastBtJson !== "") { processBtJson(cache.lastBtJson, true); hasCache = true; }
        
        // INSTANT CACHE PRE-VALIDATION
        // Evaluates the hardware 'present' states saved in settings and switches tabs 
        // instantly, bypassing the 1.5s failsafe timer.
        if (hasCache) {
            let validModes = [];
            if (window.ethPresent) validModes.push("eth");
            if (window.wifiPresent) validModes.push("wifi");
            if (window.btPresent) validModes.push("bt");

            if (validModes.length > 0 && validModes.indexOf(window.activeMode) === -1) {
                window.activeMode = validModes[0];
                window.powerAnimAllowed = false;
                powerAnimBlocker.restart();
            }
        }

        introState = 1.0;
        if (window.activeMode === "wifi") savedNetworksFetcher.running = true;
    }


    function playSfx(filename) {
        try {
            let rawUrl = Qt.resolvedUrl("sounds/" + filename).toString();
            let cleanPath = rawUrl;
            if (cleanPath.indexOf("file://") === 0) cleanPath = cleanPath.substring(7); 
            let cmd = "pw-play '" + cleanPath + "' 2>/dev/null || paplay '" + cleanPath + "' 2>/dev/null";
            Quickshell.execDetached(["sh", "-c", cmd]);
        } catch(e) {}
    }

    MatugenColors { id: _theme }

    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color sapphire: _theme.sapphire
    readonly property color blue: _theme.blue
    readonly property color red: _theme.red
    readonly property color maroon: _theme.maroon
    readonly property color peach: _theme.peach

    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/network"
    
    readonly property color sharedAccent: Qt.lighter(window.sapphire, 1.15) 
    readonly property color btAccent: window.mauve

    property string activeMode: "bt"
    readonly property color activeColor: activeMode === "bt" ? window.btAccent : window.sharedAccent
    readonly property color activeGradientSecondary: Qt.darker(window.activeColor, 1.25)

    property var busyTasks: ({})
    property var disconnectingDevices: ({})
    property string connectingId: ""
    property string failedId: ""
    
    Timer { id: busyTimeout; interval: 15000; onTriggered: { window.busyTasks = ({}); window.disconnectingDevices = ({}); window.connectingId = ""; } }
    Timer { id: failClearTimer; interval: 4000; onTriggered: window.failedId = "" }

    Timer { id: ethPendingReset; interval: 8000; onTriggered: { window.ethPowerPending = false; window.expectedEthPower = ""; } }
    Timer { id: wifiPendingReset; interval: 8000; onTriggered: { window.wifiPowerPending = false; window.expectedWifiPower = ""; } }
    Timer { id: btPendingReset; interval: 8000; onTriggered: { window.btPowerPending = false; window.expectedBtPower = ""; } }

    property bool showInfoView: false

    property string pendingWifiSsid: ""
    property string pendingWifiId: ""
    property var savedWifiNetworks: []

    Process {
        id: savedNetworksFetcher
        command: ["bash", "-c", "nmcli -t -f NAME connection show | grep -v 'lo'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let text = this.text.trim();
                window.savedWifiNetworks = text ? text.split('\n') : [];
            }
        }
    }

    Process {
        id: connectProcess
        property string targetId: ""
        property string targetSsid: ""

        onExited: {
            let code = exitCode;
            let bt = window.busyTasks;
            delete bt[targetId];
            window.busyTasks = Object.assign({}, bt);
            
            if (code !== 0) {
                window.failedId = targetId;
                failClearTimer.restart();
                window.playSfx("error.wav"); 
                
                if (window.activeMode === "wifi" && targetSsid !== "") {
                    Quickshell.execDetached(["bash", "-c", "nmcli connection delete '" + targetSsid + "' 2>/dev/null"]);
                    let newSaved = [];
                    for(let i = 0; i < window.savedWifiNetworks.length; i++) {
                        if(window.savedWifiNetworks[i] !== targetSsid) {
                            newSaved.push(window.savedWifiNetworks[i]);
                        }
                    }
                    window.savedWifiNetworks = newSaved;
                }
            }
            window.connectingId = "";
            if (window.activeMode === "eth") ethPoller.running = true;
            else if (window.activeMode === "wifi") wifiPoller.running = true; 
            else btPoller.running = true;
        }
    }

    function connectDevice(mode, id, macOrSsid, password) {
        window.connectingId = id;
        window.failedId = "";
        let bt = window.busyTasks;
        bt[id] = true;
        window.busyTasks = Object.assign({}, bt);
        busyTimeout.restart();

        connectProcess.targetId = id;
        connectProcess.targetSsid = (mode === "wifi") ? macOrSsid : ""; 
        
        if (mode === "eth") {
            connectProcess.command = ["bash", "-c", "nmcli device connect '" + macOrSsid + "'"];
        } else if (mode === "wifi") {
            if (password !== "") {
                connectProcess.command = ["bash", "-c", "nmcli device wifi connect '" + macOrSsid + "' password '" + password + "'"];
            } else {
                connectProcess.command = ["bash", "-c", "nmcli device wifi connect '" + macOrSsid + "'"];
            }
        } else {
            connectProcess.command = ["bash", "-c", window.scriptsDir + "/bluetooth_panel_logic.sh --connect '" + macOrSsid + "'"];
        }
        connectProcess.running = true;
    }

    property var currentCores: [null, null, null, null, null]
    property var coreVisualIndices: [0, 0, 0, 0, 0]
    property int activeCoreCount: 0
    property real smoothedActiveCoreCount: activeCoreCount
    Behavior on smoothedActiveCoreCount { NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo } }

    function syncCores() {
        let list = [];
        if (activeMode === "eth") {
            list = window.ethConnected ? [window.ethConnected] : [];
        } else if (activeMode === "wifi") {
            let wValid = !!window.wifiConnected && window.wifiConnected.ssid !== undefined;
            list = wValid ? [window.wifiConnected] : [];
        } else {
            list = window.btConnected;
        }

        if (!currentPower) list = [];
        else if (!Array.isArray(list)) list = [list];

        let newCores = [window.currentCores[0], window.currentCores[1], window.currentCores[2], window.currentCores[3], window.currentCores[4]];
        let found = [false, false, false, false, false];

        for (let i = 0; i < list.length && i < 5; i++) {
            let dev = list[i];
            let id = activeMode === "wifi" ? dev.ssid : (activeMode === "eth" ? dev.id : dev.mac);
            for (let c = 0; c < 5; c++) {
                if (newCores[c]) {
                    let cId = activeMode === "wifi" ? newCores[c].ssid : (activeMode === "eth" ? newCores[c].id : newCores[c].mac);
                    if (cId === id) { found[c] = true; newCores[c] = dev; break; }
                }
            }
        }

        for (let c = 0; c < 5; c++) { if (!found[c]) newCores[c] = null; }

        for (let i = 0; i < list.length && i < 5; i++) {
            let dev = list[i];
            let id = activeMode === "wifi" ? dev.ssid : (activeMode === "eth" ? dev.id : dev.mac);
            let isFound = false;
            for (let c = 0; c < 5; c++) {
                if (newCores[c]) {
                    let cId = activeMode === "wifi" ? newCores[c].ssid : (activeMode === "eth" ? newCores[c].id : newCores[c].mac);
                    if (cId === id) { isFound = true; break; }
                }
            }
            if (!isFound) {
                for (let c = 0; c < 5; c++) {
                    if (!newCores[c]) { newCores[c] = dev; break; }
                }
            }
        }

        window.currentCores = [...newCores];

        let activeCount = 0;
        let newVis = [0, 0, 0, 0, 0];
        for (let c = 0; c < 5; c++) {
            if (newCores[c]) {
                newVis[c] = activeCount;
                activeCount++;
            }
        }
        window.coreVisualIndices = newVis;
        window.activeCoreCount = activeCount;
    }

    onCurrentConnChanged: {
        showInfoView = currentConn;
        if (currentConn) updateInfoNodes();
    }

    onActiveModeChanged: {
        if (!window.ignoreNextModeFileUpdate) {
            Quickshell.execDetached(["bash", "-c", "echo '" + window.activeMode + "' > '" + window.modeFilePath + "'"]);
        }
        window.ignoreNextModeFileUpdate = false;
        
        window.pendingWifiId = ""; window.pendingWifiSsid = "";
        if (window.activeMode === "wifi") savedNetworksFetcher.running = true;

        infoListModel.clear();
        window.busyTasks = ({});
        window.disconnectingDevices = ({});
        window.currentCores = [null, null, null, null, null];
        window.coreVisualIndices = [0, 0, 0, 0, 0];
        window.activeCoreCount = 0;
        syncCores();
        window.showInfoView = window.currentConn;
        if (window.showInfoView) window.updateInfoNodes();
    }

    ListModel { id: wifiListModel }
    ListModel { id: btListModel }
    ListModel { id: infoListModel }

    function syncModel(listModel, dataArray) {
        for (let i = listModel.count - 1; i >= 0; i--) {
            let id = listModel.get(i).id;
            let found = false;
            for (let j = 0; j < dataArray.length; j++) {
                if (id === dataArray[j].id) { found = true; break; }
            }
            if (!found) { listModel.remove(i); }
        }
        
        for (let i = 0; i < dataArray.length && i < 30; i++) {
            let d = dataArray[i];
            let foundIdx = -1;
            for (let j = i; j < listModel.count; j++) {
                if (listModel.get(j).id === d.id) { foundIdx = j; break; }
            }
            
            let obj = {
                id: d.id || "", ssid: d.ssid || "", mac: d.mac || "",
                name: d.name || d.ssid || "", icon: d.icon || "", security: d.security || "", action: d.action || "",
                isInfoNode: d.isInfoNode || false, isActionable: d.isActionable !== undefined ? d.isActionable : false, 
                cmdStr: d.cmdStr || "", parentIndex: d.parentIndex !== undefined ? d.parentIndex : -1
            };

            if (foundIdx === -1) {
                listModel.insert(i, obj);
            } else {
                if (foundIdx !== i) { listModel.move(foundIdx, i, 1); }
                for (let key in obj) { 
                    if (listModel.get(i)[key] !== obj[key]) {
                        listModel.setProperty(i, key, obj[key]); 
                    }
                }
            }
        }
    }

    property int hoveredCardCount: 0
    readonly property bool isListLocked: hoveredCardCount > 0
    property var nextWifiList: null
    property var nextBtList: null
    property var nextInfoList: null

    onIsListLockedChanged: {
        if (!isListLocked) {
            if (nextWifiList !== null) { window.syncModel(wifiListModel, nextWifiList); window.wifiList = nextWifiList; nextWifiList = null; }
            if (nextBtList !== null) { window.syncModel(btListModel, nextBtList); window.btList = nextBtList; nextBtList = null; }
            if (nextInfoList !== null) { window.syncModel(infoListModel, nextInfoList); nextInfoList = null; }
        }
    }

    property string ethDeviceName: "" 
    property bool ethPowerPending: false
    property string expectedEthPower: ""
    property string ethPower: "off"
    property var ethConnected: null
    readonly property bool isEthConn: !!window.ethConnected

    onEthConnectedChanged: { syncCores(); if (window.currentConn && window.activeMode === "eth") updateInfoNodes(); }

    property bool wifiPowerPending: false
    property string expectedWifiPower: ""
    property string wifiPower: "off"
    property var wifiConnected: null
    property var wifiList: []
    property string strongestWifiSsid: ""
    readonly property bool isWifiConn: !!window.wifiConnected && window.wifiConnected.ssid !== undefined

    readonly property string targetWifiSsid: {
        let found = false;
        if (cache.lastWifiSsid !== "") {
            for (let i = 0; i < wifiList.length; i++) {
                if (wifiList[i].id === cache.lastWifiSsid) { found = true; break; }
            }
        }
        return found ? cache.lastWifiSsid : strongestWifiSsid;
    }

    onWifiConnectedChanged: {
        if (window.wifiConnected && window.wifiConnected.ssid) { cache.lastWifiSsid = window.wifiConnected.ssid; }
        syncCores();
        if (window.currentConn && window.activeMode === "wifi") updateInfoNodes();
    }

    property bool btPowerPending: false
    property string expectedBtPower: ""
    property string btPower: "off"
    property var btConnected: []
    property var btList: []
    readonly property bool isBtConn: window.btConnected.length > 0
    
    onBtConnectedChanged: { 
        syncCores();
        if (window.currentConn && window.activeMode === "bt") updateInfoNodes() 
    }

    readonly property bool currentPower: activeMode === "eth" ? window.ethPower === "on" : (activeMode === "wifi" ? window.wifiPower === "on" : window.btPower === "on")
    onCurrentPowerChanged: { syncCores(); }

    readonly property bool currentPowerPending: activeMode === "eth" ? window.ethPowerPending : (activeMode === "wifi" ? window.wifiPowerPending : window.btPowerPending)
    readonly property bool currentConn: activeMode === "eth" ? window.isEthConn : (activeMode === "wifi" ? window.isWifiConn : window.isBtConn)
    
    readonly property var currentObjList: activeMode === "eth" ? (window.isEthConn ? [window.ethConnected] : []) : (activeMode === "wifi" ? (window.isWifiConn ? [window.wifiConnected] : []) : window.btConnected)
    
    readonly property bool isLogicMultiState: window.activeMode === "bt" && window.activeCoreCount > 1
    
    property real multiTransitionState: (isLogicMultiState && window.currentPower) ? 1.0 : 0.0
    Behavior on multiTransitionState { NumberAnimation { duration: 1200; easing.type: Easing.InOutExpo } }

    function updateInfoNodes() {
        let nodes = [];
        let cList = [];
        
        if (window.activeMode === "eth") {
            cList = window.ethConnected ? [window.ethConnected] : [];
        } else if (window.activeMode === "wifi") {
            let wConn = window.wifiConnected;
            if (Array.isArray(wConn)) wConn = wConn[0]; 
            cList = (!!wConn && wConn.ssid !== undefined) ? [wConn] : [];
        } else {
            cList = window.btConnected;
        }
        
        if (window.currentConn && cList.length > 0) {
            for (let i = 0; i < cList.length; i++) {
                let obj = cList[i];
                let cIndex = 0;
                
                if (window.activeMode === "bt") {
                    for (let c = 0; c < 5; c++) {
                        if (window.currentCores[c] && window.currentCores[c].mac === obj.mac) { cIndex = c; break; }
                    }
                }

                if (window.activeMode === "eth") {
                    nodes.push({ id: "ip", name: obj.ip || "No IP", icon: "󰩟", action: "IP Address", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    nodes.push({ id: "spd", name: obj.speed || "Unknown", icon: "󰓅", action: "Link Speed", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    nodes.push({ id: "mac", name: obj.mac || "Unknown", icon: "󰒋", action: "MAC Address", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                } else if (window.activeMode === "wifi") {
                    let sigValue = obj.signal !== undefined ? obj.signal + "%" : "Calculating...";
                    nodes.push({ id: "sig_" + i, name: sigValue, icon: obj.icon || "󰤨", action: "Signal Strength", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    nodes.push({ id: "sec_" + i, name: obj.security || "Open", icon: "󰦝", action: "Security", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    if (obj.ip) nodes.push({ id: "ip_" + i, name: obj.ip, icon: "󰩟", action: "IP Address", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    if (obj.freq) nodes.push({ id: "freq_" + i, name: obj.freq, icon: "󰖧", action: "Band", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                } else {
                    nodes.push({ id: "bat_" + obj.mac, name: (obj.battery || "0") + "%", icon: "󰥉", action: "Battery", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    if (obj.profile) {
                        nodes.push({ id: "prof_" + obj.mac, name: obj.profile, icon: (obj.profile === "Hi-Fi (A2DP)" ? "󰓃" : "󰋎"), action: "Audio Profile", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                    }
                    nodes.push({ id: "mac_" + obj.mac, name: obj.mac || "Unknown", icon: "󰒋", action: "MAC Address", isInfoNode: true, isActionable: false, parentIndex: cIndex });
                }
            }
            if (window.activeMode !== "eth") {
                nodes.push({ id: "action_scan", name: "Scan Devices", icon: "󰍉", action: "Switch View", isInfoNode: true, isActionable: true, cmdStr: "TOGGLE_VIEW", parentIndex: -1 });
            }
        }
        
        if (window.isListLocked && window.activeMode !== "eth") window.nextInfoList = nodes;
        else { window.syncModel(infoListModel, nodes); window.nextInfoList = null; }
    }

    function processEthJson(textData, isCache = false) {
        if (!isCache && window.ethFirstLoad) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.ethFirstLoad = false;
        }
        if (textData === "") { if (!isCache) validateActiveMode(); return; }
        try {
            let data = JSON.parse(textData);
            window.ethPresent = data.present === true;
            let fetchedDevice = data.device || "";
            if (fetchedDevice !== "") window.ethDeviceName = fetchedDevice;
            let fetchedPower = data.power || "off";
            
            if (window.ethPowerPending) {
                window.ethPower = window.expectedEthPower; 
                if (fetchedPower === window.expectedEthPower) {
                    window.ethPowerPending = false; 
                    ethPendingReset.stop();
                }
            } else {
                window.ethPower = fetchedPower;
                window.expectedEthPower = "";
            }

            let newConnected = data.connected;
            if (JSON.stringify(window.ethConnected) !== JSON.stringify(newConnected)) {
                if (!window.isEthConn && newConnected && window.activeMode === "eth") window.playSfx("connect.wav");
                window.ethConnected = newConnected;
            }
        } catch(e) {}
        if (!isCache) validateActiveMode();
    }

    function processWifiJson(textData, isCache = false) {
        if (!isCache && window.wifiFirstLoad) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.wifiFirstLoad = false;
        }
        if (textData === "") { if (!isCache) validateActiveMode(); return; }
        try {
            let data = JSON.parse(textData);
            window.wifiPresent = data.present === true;
            let fetchedPower = data.power || "off";
            
            if (window.wifiPowerPending) {
                window.wifiPower = window.expectedWifiPower; 
                if (fetchedPower === window.expectedWifiPower) {
                    window.wifiPowerPending = false; 
                    wifiPendingReset.stop();
                }
            } else {
                window.wifiPower = fetchedPower;
                window.expectedWifiPower = "";
            }

            let wasWifiConn = !!window.wifiConnected && window.wifiConnected.ssid !== undefined;
            let newConnected = data.connected;
            let newNetworks = data.networks ? data.networks : [];

            if (newConnected && newConnected.ssid) {
                let match = newNetworks.find(n => n.id === newConnected.ssid || n.ssid === newConnected.ssid);
                if (match) {
                    newConnected.icon = match.icon || newConnected.icon;
                    newConnected.name = match.name || newConnected.name;
                    newConnected.security = match.security || newConnected.security;
                    newConnected.signal = match.signal || newConnected.signal;
                    newConnected.freq = match.freq || newConnected.freq;
                    newConnected.ip = match.ip || newConnected.ip;
                }
            }

            let isNowWifiConn = !!newConnected && newConnected.ssid !== undefined;

            if (JSON.stringify(window.wifiConnected) !== JSON.stringify(newConnected)) {
                window.wifiConnected = newConnected;
            }
            
            if (newNetworks.length > 0) {
                let maxSig = -1; let bestSsid = newNetworks[0].id;
                for (let i = 0; i < newNetworks.length; i++) {
                    let sig = parseInt(newNetworks[i].signal || 0);
                    if (sig > maxSig) { maxSig = sig; bestSsid = newNetworks[i].id; }
                }
                window.strongestWifiSsid = bestSsid;
            } else { window.strongestWifiSsid = ""; }

            newNetworks.sort((a, b) => a.id.localeCompare(b.id));

            if (isNowWifiConn && window.activeMode === "wifi") {
                newNetworks.push({ id: "action_settings", ssid: "Current Device", mac: "", name: "Current Device", icon: "󰒓", security: "", action: "View Info", isInfoNode: false, isActionable: true, cmdStr: "TOGGLE_VIEW", parentIndex: -1 });
            }

            if (JSON.stringify(window.wifiList) !== JSON.stringify(newNetworks)) {
                if (window.isListLocked) window.nextWifiList = newNetworks;
                else { window.syncModel(wifiListModel, newNetworks); window.wifiList = newNetworks; window.nextWifiList = null; }
            }

            if (window.activeMode === "wifi") {
                if (!wasWifiConn && isNowWifiConn) {
                    window.showInfoView = true;
                }
                
                let dd = window.disconnectingDevices;
                let ddChanged = false;
                for (let ssid in dd) {
                    if (!isNowWifiConn || (newConnected && newConnected.ssid !== ssid)) {
                        delete dd[ssid];
                        ddChanged = true;
                    }
                }
                if (ddChanged) {
                    window.disconnectingDevices = Object.assign({}, dd);
                    if (Object.keys(window.disconnectingDevices).length === 0 && Object.keys(window.busyTasks).length === 0) busyTimeout.stop();
                }
                
                let newlyConnected = false;
                let bt = window.busyTasks;
                if (isNowWifiConn && newConnected && bt[newConnected.ssid]) {
                    newlyConnected = true;
                    delete bt[newConnected.ssid];
                    window.connectingId = "";
                }
                if (newlyConnected) {
                    window.playSfx("connect.wav");
                    window.busyTasks = Object.assign({}, bt);
                    if (Object.keys(window.busyTasks).length === 0 && Object.keys(window.disconnectingDevices).length === 0) busyTimeout.stop();
                }

                if (isNowWifiConn || window.isBtConn || window.isEthConn) window.updateInfoNodes();
            }
        } catch(e) {}
        if (!isCache) validateActiveMode();
    }

    function processBtJson(textData, isCache = false) {
        if (!isCache && window.btFirstLoad) {
            window.powerAnimAllowed = false;
            powerAnimBlocker.restart();
            window.btFirstLoad = false;
        }
        if (textData === "") { if (!isCache) validateActiveMode(); return; }
        try {
            let data = JSON.parse(textData);
            window.btPresent = data.present === true;
            let fetchedPower = data.power || "off";
            
            if (window.btPowerPending) {
                window.btPower = window.expectedBtPower; 
                if (fetchedPower === window.expectedBtPower) {
                    window.btPowerPending = false; 
                    btPendingReset.stop();
                }
            } else {
                window.btPower = fetchedPower;
                window.expectedBtPower = "";
            }

            let oldBtLen = window.btConnected.length;
            let newBtConnected = data.connected || [];
            if (!Array.isArray(newBtConnected)) newBtConnected = [newBtConnected];
            let isNowBtConn = newBtConnected.length > 0;

            if (JSON.stringify(window.btConnected) !== JSON.stringify(newBtConnected)) {
                window.btConnected = newBtConnected;
            }

            let newDevices = data.devices ? data.devices : [];
            newDevices.sort((a, b) => a.id.localeCompare(b.id));

            if (isNowBtConn && window.activeMode === "bt") {
                newDevices.push({ id: "action_settings", ssid: "", mac: "action_settings", name: "Current Device", icon: "󰒓", action: "View Info", isInfoNode: false, isActionable: true, cmdStr: "TOGGLE_VIEW", parentIndex: -1 });
            }

            if (JSON.stringify(window.btList) !== JSON.stringify(newDevices)) {
                if (window.isListLocked) window.nextBtList = newDevices;
                else { window.syncModel(btListModel, newDevices); window.btList = newDevices; window.nextBtList = null; }
            }

            if (window.activeMode === "bt") {
                if (newBtConnected.length > oldBtLen) {
                    window.showInfoView = true;
                }

                let dd = window.disconnectingDevices;
                let ddChanged = false;
                for (let mac in dd) {
                    let stillConnected = false;
                    for (let i = 0; i < newBtConnected.length; i++) {
                        if (newBtConnected[i].mac === mac) { stillConnected = true; break; }
                    }
                    if (!stillConnected) {
                        delete dd[mac];
                        ddChanged = true;
                    }
                }
                if (ddChanged) {
                    window.disconnectingDevices = Object.assign({}, dd);
                    if (Object.keys(window.disconnectingDevices).length === 0 && Object.keys(window.busyTasks).length === 0) busyTimeout.stop();
                }
                
                let newlyConnected = false;
                let bt = window.busyTasks;
                for (let i = 0; i < newBtConnected.length; i++) {
                    let mac = newBtConnected[i].mac;
                    if (bt[mac]) {
                        newlyConnected = true;
                        delete bt[mac];
                        window.connectingId = "";
                    }
                }
                if (newlyConnected) {
                    window.playSfx("connect.wav");
                    window.busyTasks = Object.assign({}, bt);
                    if (Object.keys(window.busyTasks).length === 0 && Object.keys(window.disconnectingDevices).length === 0) busyTimeout.stop();
                }

                if (isNowBtConn || window.isWifiConn || window.isEthConn) window.updateInfoNodes();
            }
        } catch(e) {}
        if (!isCache) validateActiveMode();
    }

    Process {
        id: ethPoller
        command: ["bash", window.scriptsDir + "/eth_panel_logic.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cache.lastEthJson = this.text.trim();
                processEthJson(cache.lastEthJson);
            }
        }
    }

    Process {
        id: wifiPoller
        command: ["bash", window.scriptsDir + "/wifi_panel_logic.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cache.lastWifiJson = this.text.trim();
                processWifiJson(cache.lastWifiJson);
            }
        }
    }

    Process {
        id: btPoller
        command: ["bash", window.scriptsDir + "/bluetooth_panel_logic.sh", "--status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                cache.lastBtJson = this.text.trim();
                processBtJson(cache.lastBtJson);
            }
        }
    }
    
    Timer {
        interval: (Object.keys(window.busyTasks).length > 0 || Object.keys(window.disconnectingDevices).length > 0) ? 1000 : 3000
        running: true; repeat: true
        onTriggered: { 
            if (!ethPoller.running) ethPoller.running = true; 
            if (!wifiPoller.running) wifiPoller.running = true; 
            if (!btPoller.running) btPoller.running = true; 
        }
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 200000; loops: Animation.Infinite; running: true
    }

    property real introState: 0.0
    Behavior on introState { NumberAnimation { duration: 1500; easing.type: Easing.OutCubic } }

    component LoadingDots : Row {
        spacing: window.s(5)
        property color dotCol: window.text
        Repeater {
            model: 3
            Rectangle {
                width: window.s(6); height: window.s(6); radius: window.s(3); color: dotCol
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 100 }
                    NumberAnimation { from: 0; to: window.s(-6); duration: 250; easing.type: Easing.OutSine }
                    NumberAnimation { from: window.s(-6); to: 0; duration: 250; easing.type: Easing.InSine }
                    PauseAnimation { duration: (2 - index) * 100 }
                }
            }
        }
    }

    Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            radius: window.s(20)
            color: window.base
            border.color: window.surface0
            border.width: 1
            clip: true
            
            Rectangle {
                width: parent.width * 0.8; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(150)
                y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(100)
                opacity: window.currentPower ? 0.08 : 0.02
                color: window.currentConn ? window.activeColor : window.surface2
                Behavior on color { ColorAnimation { duration: 1000 } }
                Behavior on opacity { NumberAnimation { duration: 1000 } }
                visible: opacity > 0.01
            }
            
            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-150)
                y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-100)
                opacity: window.currentPower ? 0.06 : 0.01
                color: window.currentConn ? window.activeGradientSecondary : window.surface1
                Behavior on color { ColorAnimation { duration: 1000 } }
                Behavior on opacity { NumberAnimation { duration: 1000 } }
                visible: opacity > 0.01
            }

            Item {
                id: radarItem
                anchors.fill: parent
                anchors.bottomMargin: window.s(80) 
                opacity: window.currentPower ? 1.0 : 0.0
                scale: window.currentPower ? 1.0 : 1.05
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
                Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                
                Repeater {
                    model: 3
                    Rectangle {
                        anchors.centerIn: parent
                        width: window.s(280) + (index * window.s(170))
                        height: width
                        radius: width / 2
                        color: "transparent"
                        
                        border.color: Object.keys(window.disconnectingDevices).length > 0 ? window.red : window.activeColor
                        border.width: Object.keys(window.disconnectingDevices).length > 0 ? window.s(2) : 1
                        
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Behavior on border.width { NumberAnimation { duration: 150 } }

                        opacity: Object.keys(window.disconnectingDevices).length > 0 ? 0.2 : (window.currentConn ? 0.08 - (index * 0.02) : 0.03)
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }

            Canvas {
                id: nodeLinesCanvas
                anchors.fill: parent
                anchors.bottomMargin: window.s(80)
                z: 0 
                opacity: (window.currentConn && window.showInfoView && window.currentPower) ? 1.0 : 0.0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 500 } }
                
                property real scaleTrigger: window.s(1)
                onScaleTriggerChanged: requestPaint()

                Timer {
                    id: lightningTimer
                    interval: 45
                    running: nodeLinesCanvas.opacity > 0.01 && window.currentPower 
                    repeat: true
                    onTriggered: nodeLinesCanvas.requestPaint()
                }

                Connections {
                    target: window
                    function onGlobalOrbitAngleChanged() { 
                        if (window.currentConn && window.showInfoView && window.currentPower) nodeLinesCanvas.requestPaint() 
                    }
                }
                
                onPaint: {
                    var ctx = getContext("2d");
                    var s = window.s;
                    ctx.clearRect(0, 0, width, height);
                    if (!window.currentConn || !window.showInfoView || !window.currentPower) return;
                    
                    var time = Date.now() / 1000;
                    
                    var time = Date.now() / 1000;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";

                    var tWave1 = time * 2.5;
                    var tWave2 = time * -1.5;

                    for (var i = 0; i < orbitRepeater.count; i++) {
                        var item = orbitRepeater.itemAt(i);
                        if (!item || !item.isLoaded) continue;

                        var targetX = item.x + item.width / 2;
                        var targetY = item.y + item.height / 2;

                        function drawStrands(startX, startY, parentFade, parentWidth) {
                            var dx = targetX - startX;
                            var dy = targetY - startY;
                            var fullDist = Math.sqrt(dx * dx + dy * dy);
                            
                            if (fullDist < s(10)) return;

                            var alpha = Math.atan2(dy, dx);
                            var cosA = Math.cos(alpha);
                            var sinA = Math.sin(alpha);
                            
                            var coreVisualRadius = parentWidth / 2;
                            var startOffset = coreVisualRadius + s(5); 
                            var endOffset = s(35); 
                            
                            var drawDist = fullDist - startOffset - endOffset;
                            if (drawDist <= 0) return;
                            
                            var steps = 8;
                            var perpX = -sinA;
                            var perpY = cosA;

                            var sX = startX + cosA * startOffset;
                            var sY = startY + sinA * startOffset;

                            var distanceFactor = Math.max(0, 1.0 - (fullDist / 400.0));
                            var dynamicLineWidthCore = s(1.0) + (distanceFactor * s(2.0));
                            var dynamicLineWidthGlow = s(4.0) + (distanceFactor * s(4.0));
                            var dynamicAlpha = (0.2 + (distanceFactor * 0.7)) * parentFade;

                            ctx.beginPath();
                            ctx.moveTo(sX, sY);
                            for (var j = 1; j <= steps; j++) {
                                var t = j / steps;
                                var currentDist = drawDist * t;
                                var envelope = Math.sin(t * Math.PI);
                                var offset = Math.sin(tWave1 + t * 6) * s(6) * envelope + ((Math.random() - 0.5) * s(5.0) * distanceFactor);
                                ctx.lineTo(sX + cosA * currentDist + perpX * offset, sY + sinA * currentDist + perpY * offset);
                            }
                            ctx.lineWidth = dynamicLineWidthGlow;
                            ctx.strokeStyle = window.activeColor;
                            ctx.globalAlpha = dynamicAlpha * 0.15;
                            ctx.stroke();

                            ctx.lineWidth = dynamicLineWidthCore;
                            ctx.strokeStyle = "#ffffff";
                            ctx.globalAlpha = dynamicAlpha;
                            ctx.stroke();

                            ctx.beginPath();
                            ctx.moveTo(sX, sY);
                            for (var k = 1; k <= steps; k++) {
                                var tk = k / steps;
                                var currentDistK = drawDist * tk;
                                var envelopeK = Math.sin(tk * Math.PI);
                                var offsetK = Math.cos(tWave2 + tk * 8) * s(12) * envelopeK + ((Math.random() - 0.5) * s(3.0) * distanceFactor);
                                ctx.lineTo(sX + cosA * currentDistK + perpX * offsetK, sY + sinA * currentDistK + perpY * offsetK);
                            }
                            ctx.lineWidth = dynamicLineWidthCore * 1.5;
                            ctx.strokeStyle = window.activeColor;
                            ctx.globalAlpha = dynamicAlpha * 0.3;
                            ctx.stroke();
                        }

                        if (item.myParentIdx === -1) {
                            for (var c = 0; c < coreRepeater.count; c++) {
                                var cItem = coreRepeater.itemAt(c);
                                if (cItem && cItem.activeTransition > 0.01) {
                                    drawStrands(cItem.x + cItem.width/2, cItem.y + cItem.height/2, cItem.activeTransition, cItem.width);
                                }
                            }
                        } else {
                            var pItem = coreRepeater.itemAt(item.myParentIdx);
                            if (pItem && pItem.activeTransition > 0.01) {
                                drawStrands(pItem.x + pItem.width/2, pItem.y + pItem.height/2, pItem.activeTransition, pItem.width);
                            }
                        }
                    }
                }
            }

            Item {
                id: orbitContainer
                anchors.fill: parent
                anchors.bottomMargin: window.s(80) 
                z: 1

                Repeater {
                    id: coreRepeater
                    model: 5

                    delegate: Item {
                        id: coreContainer
                        
                        property var myDevice: window.currentCores[index]
                        
                        property bool isPrimary: index === 0
                        property bool hasDevice: myDevice !== null
                        property bool isReallyActive: window.currentPower && (hasDevice || (isPrimary && window.activeCoreCount === 0))

                        property real activeTransition: isReallyActive ? 1.0 : 0.0
                        
                        Behavior on activeTransition { 
                            enabled: window.introState >= 1.0; 
                            NumberAnimation { duration: 1400; easing.type: Easing.OutExpo } 
                        }

                        property real multiShift: window.activeMode === "wifi" || window.activeMode === "eth" ? 0.0 : window.multiTransitionState

                        width: window.currentPower ? (window.s(200) - (window.s(30) * multiShift) - (window.s(15) * Math.max(0, window.smoothedActiveCoreCount - 2))) : window.s(160)
                        height: width
                        
                        property real myBaseAngle: (window.coreVisualIndices[index] / Math.max(1, window.activeCoreCount)) * Math.PI * 2
                        property real animatedBaseAngle: myBaseAngle
                        Behavior on animatedBaseAngle { NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo } }
                        
                        property real coreOrbitAngle: window.globalOrbitAngle * 1.5 + animatedBaseAngle
                        
                        property real myOrbitRadiusX: window.s(180) + (window.activeCoreCount > 2 ? window.s(20) : 0)
                        property real myOrbitRadiusY: window.s(110) + (window.activeCoreCount > 2 ? window.s(15) : 0)

                        x: window.activeMode === "eth" ? (orbitContainer.width / 2 - width / 2) : ((orbitContainer.width / 2 - width / 2) + (Math.cos(coreOrbitAngle) * myOrbitRadiusX * multiShift * activeTransition))
                        y: window.activeMode === "eth" ? (orbitContainer.height / 2 - height / 2) : ((orbitContainer.height / 2 - height / 2) + (Math.sin(coreOrbitAngle) * myOrbitRadiusY * multiShift * activeTransition))
                        
                        opacity: activeTransition
                        scale: centralCore.bumpScale * (0.8 + 0.2 * activeTransition)
                        visible: opacity > 0.01

                        property string myId: myDevice ? (window.activeMode === "wifi" ? myDevice.ssid : (window.activeMode === "eth" ? myDevice.id : myDevice.mac)) : "unknown"
                        property bool isMyDisconnecting: !!window.disconnectingDevices[myId]

                        property bool showScanning: isPrimary && window.currentPower && !window.currentConn && window.pendingWifiId === "" && window.activeMode !== "eth"
                        property bool showConnected: window.currentConn && hasDevice && window.pendingWifiId === ""
                        property bool showPassword: isPrimary && window.pendingWifiId !== "" && window.activeMode === "wifi"
                        property bool showEthDisconnected: isPrimary && window.currentPower && !window.currentConn && window.activeMode === "eth"

                        MultiEffect {
                            source: centralCore
                            anchors.fill: centralCore
                            shadowEnabled: true
                            shadowColor: "#000000"
                            shadowOpacity: window.currentPower ? 0.5 : 0.0
                            shadowBlur: 1.2
                            shadowVerticalOffset: window.s(6)
                            z: -1
                            Behavior on shadowOpacity { NumberAnimation { duration: 600 } }
                        }

                        Rectangle {
                            id: centralCore
                            anchors.fill: parent
                            radius: width / 2
                            
                            property real disconnectFill: 0.0
                            property bool disconnectTriggered: false
                            property real flashOpacity: 0.0
                            property real bumpScale: 1.0
                            property bool isDangerState: coreMa.containsMouse || disconnectFill > 0 || isMyDisconnecting

                            SequentialAnimation on bumpScale {
                                id: coreBumpAnim
                                running: false
                                NumberAnimation { to: 1.15; duration: 200; easing.type: Easing.OutBack }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.OutQuint }
                            }

                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop {
                                    position: 0.0
                                    color: {
                                        if (!window.currentPower) return window.mantle;
                                        if (isMyDisconnecting) return window.surface0; 
                                        if (centralCore.isDangerState && window.currentConn && !showPassword) return Qt.lighter(window.red, 1.15);
                                        return window.currentConn || showPassword ? Qt.lighter(window.activeColor, 1.15) : window.surface0;
                                    }
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                                GradientStop {
                                    position: 1.0
                                    color: {
                                        if (!window.currentPower) return window.crust;
                                        if (isMyDisconnecting) return window.base; 
                                        if (centralCore.isDangerState && window.currentConn && !showPassword) return window.red;
                                        return window.currentConn || showPassword ? window.activeColor : window.base;
                                    }
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                            }

                            border.color: {
                                if (!window.currentPower) return window.crust;
                                if (isMyDisconnecting) return window.surface0;
                                if (centralCore.isDangerState && window.currentConn && !showPassword) return window.maroon;
                                return window.currentConn || showPassword ? Qt.lighter(window.activeColor, 1.1) : window.surface1;
                            }
                            border.width: window.s(2)
                            Behavior on border.color { ColorAnimation { duration: 300 } }
                            
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "#ffffff"
                                opacity: centralCore.flashOpacity
                                PropertyAnimation on opacity { id: coreFlashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                            }

                            Canvas {
                                id: coreWave
                                anchors.fill: parent
                                visible: centralCore.disconnectFill > 0
                                opacity: 0.95
                                
                                property real scaleTrigger: window.s(1)
                                onScaleTriggerChanged: requestPaint()

                                property real wavePhase: 0.0
                                NumberAnimation on wavePhase {
                                    running: centralCore.disconnectFill > 0.0 && centralCore.disconnectFill < 1.0
                                    loops: Animation.Infinite
                                    from: 0; to: Math.PI * 2; duration: 800
                                }
                                onWavePhaseChanged: requestPaint()
                                Connections { target: centralCore; function onDisconnectFillChanged() { coreWave.requestPaint() } }

                                onPaint: {
                                    var ctx = getContext("2d");
                                    var s = window.s;
                                    ctx.clearRect(0, 0, width, height);
                                    if (centralCore.disconnectFill <= 0.001) return;

                                    var r = width / 2;
                                    var fillY = height * (1.0 - centralCore.disconnectFill);

                                    ctx.save();
                                    ctx.beginPath();
                                    ctx.arc(r, r, r, 0, 2 * Math.PI);
                                    ctx.clip(); 

                                    ctx.beginPath();
                                    ctx.moveTo(0, fillY);
                                    if (centralCore.disconnectFill < 0.99) {
                                        var waveAmp = s(10) * Math.sin(centralCore.disconnectFill * Math.PI);
                                        var cp1y = fillY + Math.sin(wavePhase) * waveAmp;
                                        var cp2y = fillY + Math.cos(wavePhase + Math.PI) * waveAmp;
                                        ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
                                        ctx.lineTo(width, height);
                                        ctx.lineTo(0, height);
                                    } else {
                                        ctx.lineTo(width, 0);
                                        ctx.lineTo(width, height);
                                        ctx.lineTo(0, height);
                                    }
                                    ctx.closePath();
                                    
                                    var grad = ctx.createLinearGradient(0, 0, 0, height);
                                    grad.addColorStop(0, window.surface1.toString()); 
                                    grad.addColorStop(1, window.crust.toString());
                                    ctx.fillStyle = grad;
                                    ctx.fill();
                                    ctx.restore();
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + window.s(40)
                                height: width
                                radius: width / 2
                                color: centralCore.isDangerState && window.currentConn && !showPassword ? window.red : window.activeColor
                                opacity: (window.currentConn || showPassword) && !isMyDisconnecting ? (centralCore.isDangerState && !showPassword ? 0.3 : 0.15) : 0.0
                                z: -1
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                                
                                SequentialAnimation on scale {
                                    loops: Animation.Infinite; running: window.currentConn || showPassword
                                    NumberAnimation { to: 1.1; duration: 2000; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 2000; easing.type: Easing.InOutSine }
                                }
                            }
                            
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + window.s(15)
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: centralCore.isDangerState && !showPassword ? window.red : window.activeColor
                                border.width: window.s(3)
                                z: -2
                                
                                property real pulseOp: 0.0
                                property real pulseSc: 1.0
                                opacity: ((window.currentConn || showPassword) && window.showInfoView && window.currentPower && !isMyDisconnecting) ? pulseOp : 0.0
                                scale: pulseSc
                                
                                Timer {
                                    interval: 45
                                    running: parent.opacity > 0.01
                                    repeat: true
                                    onTriggered: {
                                        var time = Date.now() / 1000;
                                        parent.pulseOp = 0.3 + Math.sin(time * 2.5) * 0.15;
                                        parent.pulseSc = 1.02 + Math.cos(time * 3.0) * 0.02;
                                    }
                                }
                            }

                            Item {
                                anchors.fill: parent
                                opacity: showScanning ? 1.0 : 0.0
                                visible: opacity > 0.01
                                Behavior on opacity { NumberAnimation { duration: 400 } }

                                Repeater {
                                    model: 3
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.4; height: width; radius: width / 2
                                        color: "transparent"
                                        border.color: window.activeColor; border.width: window.s(2)
                                        SequentialAnimation on scale {
                                            running: showScanning; loops: Animation.Infinite
                                            PauseAnimation { duration: index * 400 }
                                            NumberAnimation { from: 1.0; to: 2.5; duration: 2000; easing.type: Easing.OutSine }
                                        }
                                        SequentialAnimation on opacity {
                                            running: showScanning; loops: Animation.Infinite
                                            PauseAnimation { duration: index * 400 }
                                            NumberAnimation { from: 0.8; to: 0.0; duration: 2000; easing.type: Easing.OutSine }
                                        }
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: window.s(48) - (window.s(16) * coreContainer.multiShift)
                                    color: window.activeColor
                                    text: window.activeMode === "wifi" ? "󰤨" : (window.activeMode === "eth" ? "󰈀" : "󰂯")
                                    SequentialAnimation on opacity {
                                        running: showScanning; loops: Animation.Infinite
                                        NumberAnimation { to: 0.5; duration: 1000; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: window.s(10)
                                visible: showEthDisconnected
                                opacity: visible ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(48); color: window.overlay0; text: "󰈂" }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(14); color: window.overlay0; text: window.currentPowerPending ? (window.expectedEthPower === "on" ? "Powering On..." : "Powering Off...") : "Disconnected" }
                            }

                            Item {
                                id: pwdLayer
                                anchors.fill: parent
                                opacity: showPassword ? 1.0 : 0.0
                                visible: opacity > 0.01
                                scale: showPassword ? 1.0 : 0.8
                                Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
                                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutSine } }
                                
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: window.s(8)
                                    
                                    Text { Layout.alignment: Qt.AlignHCenter; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(32); color: window.crust; text: "󰤨" }
                                    
                                    Text { 
                                        Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: pwdLayer.width - window.s(40)
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13)
                                        color: window.crust; text: window.pendingWifiSsid; elide: Text.ElideRight 
                                    }
                                    
                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.preferredWidth: pwdLayer.width - window.s(40); height: window.s(36)
                                        radius: window.s(18)
                                        color: window.surface0
                                        border.color: wifiPasswordField.activeFocus ? window.crust : "transparent"
                                        border.width: 1
                                        Behavior on border.color { ColorAnimation { duration: 200 } }
                                        
                                        TextInput {
                                            id: wifiPasswordField
                                            anchors.fill: parent
                                            anchors.leftMargin: window.s(15); anchors.rightMargin: window.s(15)
                                            verticalAlignment: TextInput.AlignVCenter
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(13); color: window.text
                                            echoMode: TextInput.Password; clip: true
                                            onAccepted: {
                                                if (text.trim() !== "") {
                                                    window.connectDevice(window.activeMode, window.pendingWifiId, window.pendingWifiSsid, text);
                                                    window.pendingWifiId = ""; window.pendingWifiSsid = ""; text = "";
                                                    window.forceActiveFocus();
                                                }
                                            }
                                            Keys.onEscapePressed: { window.pendingWifiId = ""; window.pendingWifiSsid = ""; text = ""; window.forceActiveFocus(); }
                                        }
                                    }
                                }
                                
                                Timer { id: deferFocusTimer; interval: 50; onTriggered: wifiPasswordField.forceActiveFocus() }
                                onVisibleChanged: { if (visible) { wifiPasswordField.text = ""; deferFocusTimer.start(); } }
                            }

                            Item {
                                anchors.fill: parent
                                opacity: showConnected ? 1.0 : 0.0
                                visible: opacity > 0.01
                                scale: showConnected ? 1.0 : 0.95
                                Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutSine } }

                                ColumnLayout {
                                    id: baseCoreText
                                    anchors.centerIn: parent
                                    spacing: window.s(4)

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(48) - (window.s(16) * coreContainer.multiShift)
                                        color: isMyDisconnecting ? window.overlay1 : window.crust
                                        text: isMyDisconnecting ? "" : (coreMa.containsMouse ? (window.activeMode === "wifi" ? "󰖪" : (window.activeMode === "eth" ? "󰈂" : "󰂲")) : (coreContainer.myDevice ? (coreContainer.myDevice.icon || (window.activeMode === "wifi" ? "󰤨" : (window.activeMode === "eth" ? "󰈀" : "󰂯"))) : ""))
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    LoadingDots { Layout.alignment: Qt.AlignHCenter; visible: isMyDisconnecting; dotCol: window.overlay1 }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.maximumWidth: window.s(150) - (window.s(50) * coreContainer.multiShift)
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: "JetBrains Mono"; font.weight: Font.Black
                                        font.pixelSize: window.s(16) - (window.s(4) * coreContainer.multiShift)
                                        color: isMyDisconnecting ? window.overlay1 : window.crust
                                        text: coreContainer.myDevice ? (window.activeMode === "wifi" ? coreContainer.myDevice.ssid : coreContainer.myDevice.name) : ""
                                        elide: Text.ElideRight
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11)
                                        color: isMyDisconnecting ? window.overlay1 : (coreMa.containsMouse ? window.crust : "#99000000")
                                        text: isMyDisconnecting ? "Disconnecting..." : (centralCore.disconnectFill > 0.01 ? "Hold..." : "Connected")
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                }

                                Item {
                                    id: waveClipItem
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: Math.min(parent.height, Math.max(0, parent.height * centralCore.disconnectFill + window.s(8)))
                                    clip: true
                                    visible: centralCore.disconnectFill > 0

                                    ColumnLayout {
                                        spacing: window.s(4)
                                        x: waveClipItem.width / 2 - width / 2
                                        y: (centralCore.height / 2) - (height / 2) - (centralCore.height - waveClipItem.height)

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(48) - (window.s(16) * coreContainer.multiShift)
                                            color: window.text
                                            text: isMyDisconnecting ? "" : (coreMa.containsMouse ? (window.activeMode === "wifi" ? "󰖪" : (window.activeMode === "eth" ? "󰈂" : "󰂲")) : (coreContainer.myDevice ? (coreContainer.myDevice.icon || (window.activeMode === "wifi" ? "󰤨" : (window.activeMode === "eth" ? "󰈀" : "󰂯"))) : ""))
                                        }
                                        LoadingDots { Layout.alignment: Qt.AlignHCenter; visible: isMyDisconnecting; dotCol: window.text }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.maximumWidth: window.s(150) - (window.s(50) * coreContainer.multiShift)
                                            horizontalAlignment: Text.AlignHCenter
                                            font.family: "JetBrains Mono"; font.weight: Font.Black
                                            font.pixelSize: window.s(16) - (window.s(4) * coreContainer.multiShift)
                                            color: window.text
                                            text: coreContainer.myDevice ? (window.activeMode === "wifi" ? coreContainer.myDevice.ssid : coreContainer.myDevice.name) : ""
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11)
                                            color: window.text
                                            text: isMyDisconnecting ? "Disconnecting..." : (centralCore.disconnectFill > 0.01 ? "Hold..." : "Connected")
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: coreMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: window.currentConn && !isMyDisconnecting && !showPassword ? Qt.PointingHandCursor : Qt.ArrowCursor
                                
                                onPressed: {
                                    if (window.currentConn && !isMyDisconnecting && !centralCore.disconnectTriggered && !showPassword) {
                                        coreDrainAnim.stop();
                                        coreFillAnim.start();
                                    }
                                }
                                onReleased: {
                                    if (!centralCore.disconnectTriggered && !isMyDisconnecting && !showPassword) {
                                        coreFillAnim.stop();
                                        coreDrainAnim.start();
                                    }
                                }
                            }

                            NumberAnimation {
                                id: coreFillAnim
                                target: centralCore
                                property: "disconnectFill"
                                to: 1.0
                                duration: 700 * (1.0 - centralCore.disconnectFill) 
                                easing.type: Easing.InSine
                                onFinished: {
                                    if (!coreMa.pressed) {
                                        centralCore.disconnectFill = 0.0;
                                        return;
                                    }

                                    centralCore.disconnectTriggered = true;
                                    centralCore.flashOpacity = 0.6;
                                    cardFlashAnim.start();
                                    coreBumpAnim.start();
                                    
                                    window.playSfx("disconnect.wav");
                                    
                                    let dd = window.disconnectingDevices;
                                    dd[coreContainer.myId] = true;
                                    window.disconnectingDevices = Object.assign({}, dd);
                                    busyTimeout.restart();
                                    
                                    let cmd = "";
                                    if (window.activeMode === "eth") cmd = "nmcli device disconnect '" + coreContainer.myId + "'";
                                    else if (window.activeMode === "wifi") cmd = "nmcli device disconnect $(nmcli -t -f DEVICE,TYPE d | grep wifi | cut -d: -f1 | head -n1)";
                                    else cmd = "bash " + window.scriptsDir + "/bluetooth_panel_logic.sh --disconnect '" + coreContainer.myId + "'";
                                    Quickshell.execDetached(["sh", "-c", cmd])
                                    
                                    centralCore.disconnectFill = 0.0;
                                    centralCore.disconnectTriggered = false;
                                    
                                    if (window.activeMode === "eth") ethPoller.running = true;
                                    else if (window.activeMode === "wifi") wifiPoller.running = true; 
                                    else btPoller.running = true;
                                }
                            }
                            
                            NumberAnimation {
                                id: coreDrainAnim
                                target: centralCore
                                property: "disconnectFill"
                                to: 0.0
                                duration: 1000 * centralCore.disconnectFill 
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    opacity: window.currentPower ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

                    Repeater {
                        id: orbitRepeater
                        model: (window.currentConn && window.showInfoView) ? infoListModel : (window.activeMode === "wifi" ? wifiListModel : (window.activeMode === "bt" ? btListModel : null))
                        
                        delegate: Item {
                            id: floatCardDelegateContainer
                            width: window.s(170); height: window.s(60)

                            property bool isLoaded: false
                            opacity: isLoaded ? 1.0 : 0.0
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                            property real entryAnim: isLoaded ? 1.0 : 0.0
                            Behavior on entryAnim { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }

                            Timer {
                                running: true
                                interval: window.activeMode === "eth" ? (600 + (index * 80)) : (40 + (index * 30)) 
                                onTriggered: floatCardDelegateContainer.isLoaded = true
                            }

                            property int myParentIdx: model.parentIndex !== undefined ? model.parentIndex : -1
                            
                            property int siblingsCount: {
                                let c = 0;
                                let m = orbitRepeater.model;
                                if (m && m.count !== undefined) {
                                    for (let i = 0; i < m.count; i++) {
                                        let d = m.get(i);
                                        if (d && (d.parentIndex !== undefined ? d.parentIndex : -1) === myParentIdx) c++;
                                    }
                                }
                                return Math.max(1, c);
                            }
                            property int localIndex: {
                                let idx = 0;
                                let m = orbitRepeater.model;
                                if (m && m.count !== undefined) {
                                    for (let i = 0; i < index; i++) {
                                        let d = m.get(i);
                                        if (d && (d.parentIndex !== undefined ? d.parentIndex : -1) === myParentIdx) idx++;
                                    }
                                }
                                return idx;
                            }

                            property real unifiedRatio: window.activeMode === "wifi" || window.activeMode === "eth" ? 0.0 : window.multiTransitionState

                            property real activeCount: (unifiedRatio > 0.5 && myParentIdx !== -1) ? siblingsCount : orbitRepeater.count
                            property real dynamicScale: activeCount > 10 ? Math.max(0.6, 12.0 / activeCount) : (unifiedRatio > 0.5 ? (window.activeCoreCount > 2 ? 0.7 : 0.8) : 1.0)
                            
                            property real safeMultiShift: window.activeMode === "wifi" || window.activeMode === "eth" ? 0.0 : window.multiTransitionState
                            property var pItem: myParentIdx !== -1 ? coreRepeater.itemAt(myParentIdx) : null
                            
                            property real parentX: pItem ? (orbitContainer.width / 2) + (Math.cos(parentCoreAngle) * pItem.myOrbitRadiusX * safeMultiShift * pItem.activeTransition) : (orbitContainer.width / 2)
                            property real parentY: pItem ? (orbitContainer.height / 2) + (Math.sin(parentCoreAngle) * pItem.myOrbitRadiusY * safeMultiShift * pItem.activeTransition) : (orbitContainer.height / 2)

                            property real parentBaseAngle: pItem ? pItem.animatedBaseAngle : 0
                            
                            property real targetSingleBaseAngle: (index / Math.max(1, orbitRepeater.count)) * Math.PI * 2
                            property real singleBaseAngle: targetSingleBaseAngle
                            Behavior on singleBaseAngle { NumberAnimation { duration: 800; easing.type: Easing.OutExpo } }

                            property real singleLiveAngle: (window.globalOrbitAngle * 1.5) + singleBaseAngle
                            
                            property real arcSpread: Math.PI * 0.8 
                            property real targetNodeOffset: (siblingsCount > 1) ? ((localIndex / (siblingsCount - 1)) - 0.5) * arcSpread : 0
                            property real nodeOffset: targetNodeOffset
                            Behavior on nodeOffset { NumberAnimation { duration: 800; easing.type: Easing.OutExpo } }

                            property real parentCoreAngle: (window.globalOrbitAngle * 1.5) + parentBaseAngle
                            property real multiLiveAngle: myParentIdx === -1 ? singleLiveAngle : (parentCoreAngle + nodeOffset)

                            property int ringIndex: isInfoNode ? 0 : index % 2
                            property real targetRingOffset: ringIndex * window.s(40)
                            property real ringOffset: targetRingOffset
                            Behavior on ringOffset { NumberAnimation { duration: 800; easing.type: Easing.OutExpo } }

                            property real singleRadX: isInfoNode ? window.s(280) : window.s(320) + ringOffset
                            property real singleRadY: isInfoNode ? window.s(180) : window.s(200) + ringOffset
                            
                            property real multiRadX: isInfoNode ? (myParentIdx === -1 ? 0 : (window.activeCoreCount > 2 ? window.s(180) : window.s(160))) : window.s(340) + ringOffset
                            property real multiRadY: isInfoNode ? (myParentIdx === -1 ? 0 : (window.activeCoreCount > 2 ? window.s(180) : window.s(160))) : window.s(240) + ringOffset

                            property real currentRadX: window.activeMode === "eth" ? window.s(280) : ((singleRadX * (1 - unifiedRatio)) + (multiRadX * unifiedRatio))
                            property real currentRadY: window.activeMode === "eth" ? window.s(180) : ((singleRadY * (1 - unifiedRatio)) + (multiRadY * unifiedRatio))
                            property real currentAngle: (singleLiveAngle * (1 - unifiedRatio)) + (multiLiveAngle * unifiedRatio)
                            
                            property real pwrDrift: window.currentPower ? 0 : window.s(40)
                            Behavior on pwrDrift { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

                            property real animRadX: (currentRadX + pwrDrift) * (0.25 + 0.75 * entryAnim)
                            property real animRadY: (currentRadY + pwrDrift) * (0.25 + 0.75 * entryAnim)

                            property real targetX: myParentIdx === -1 
                                ? (orbitContainer.width / 2) - (width / 2) + Math.cos(currentAngle) * animRadX
                                : parentX - (width / 2) + Math.cos(currentAngle) * animRadX
                                
                            property real targetY: myParentIdx === -1 
                                ? (orbitContainer.height / 2) - (height / 2) + Math.sin(currentAngle) * animRadY
                                : parentY - (height / 2) + Math.sin(currentAngle) * animRadY

                            property real liveBob: myParentIdx === -1 && isInfoNode 
                                ? Math.sin(window.globalOrbitAngle * 6) * window.s(12) * (1 - unifiedRatio) 
                                : 0

                            x: targetX
                            y: targetY + liveBob

                            scale: (!isLoaded ? 0.0 : (floatMa.pressed ? dynamicScale * 0.95 : (floatCard.locksList ? dynamicScale * 1.08 : dynamicScale))) * floatCard.bumpScale
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
                            z: floatCard.locksList ? 10 : index

                            MultiEffect {
                                source: floatCard
                                anchors.fill: floatCard
                                shadowEnabled: window.currentPower && floatCardDelegateContainer.opacity > 0.05
                                shadowColor: "#000000"
                                shadowOpacity: 0.3
                                shadowBlur: 0.8
                                shadowVerticalOffset: window.s(4)
                                z: -1
                            }

                            Rectangle {
                                id: floatCard
                                anchors.fill: parent
                                radius: window.s(14)
                                
                                property string itemId: id
                                property string itemName: name
                                
                                property bool isMyBusy: window.connectingId === itemId || !!window.busyTasks[itemId]
                                property bool isFailed: window.failedId === itemId
                                
                                property bool isPairedBT: window.activeMode === "bt" && action === "Connect"
                                property bool isTargetWifi: window.activeMode === "wifi" && !window.isWifiConn && itemId === window.targetWifiSsid
                                property bool isSpecialAction: itemId === "action_scan" || itemId === "action_settings"
                                property bool isHighlighted: isPairedBT || isTargetWifi || isSpecialAction
                                
                                property bool isCurrentlyConnected: {
                                    if (window.activeMode === "eth") return (window.ethConnected && window.ethConnected.id === itemId);
                                    if (window.activeMode === "wifi") return (window.wifiConnected && window.wifiConnected.ssid === itemId);
                                    for (let i = 0; i < window.btConnected.length; i++) {
                                        if (window.btConnected[i].mac === itemId) return true;
                                    }
                                    return false;
                                }
                                
                                property bool isInteractable: !isInfoNode || isActionable
                                property bool locksList: isInteractable && (floatMa.containsMouse || floatMa.pressed)
                                onLocksListChanged: { if (locksList) window.hoveredCardCount++; else window.hoveredCardCount--; }
                                Component.onDestruction: { if (locksList) window.hoveredCardCount--; }
                                
                                property real bumpScale: 1.0
                                SequentialAnimation on bumpScale {
                                    id: cardBumpAnim
                                    running: false
                                    NumberAnimation { to: 1.2; duration: 200; easing.type: Easing.OutBack }
                                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.OutQuint }
                                }

                                property real nameImplicitWidth: baseNameText.implicitWidth
                                property real nameContainerWidth: nameContainerBase.width
                                property bool doMarquee: floatMa.containsMouse && nameImplicitWidth > nameContainerWidth
                                property real textOffset: 0

                                SequentialAnimation on textOffset {
                                    running: floatCard.doMarquee
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: 600 } 
                                    NumberAnimation {
                                        from: 0
                                        to: -(floatCard.nameImplicitWidth + window.s(30))
                                        duration: (floatCard.nameImplicitWidth + window.s(30)) * 35
                                    }
                                }
                                onDoMarqueeChanged: if (!doMarquee) textOffset = 0;

                                property real fillLevel: 0.0
                                property bool triggered: false
                                property real flashOpacity: 0.0
                                
                                property real renderFill: (isCurrentlyConnected) ? 1.0 : fillLevel
                                
                                onIsFailedChanged: {
                                    if (isFailed) {
                                        triggered = false;
                                        drainAnim.start();
                                    }
                                }

                                Connections {
                                    target: window
                                    function onPendingWifiIdChanged() {
                                        if (window.pendingWifiId === "" && floatCard.fillLevel > 0 && !floatCard.isMyBusy && !floatCard.isCurrentlyConnected) {
                                            floatCard.triggered = false;
                                            drainAnim.start();
                                        }
                                    }
                                }

                                color: locksList ? "#2affffff" : "#0effffff"
                                Behavior on color { ColorAnimation { duration: 200 } }
                                
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: window.red
                                    opacity: floatCard.isFailed ? 0.3 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: window.s(14)
                                    color: "transparent"
                                    border.width: 1
                                    border.color: floatCard.isFailed ? window.red : window.surface2
                                    visible: !isHighlighted && !locksList
                                    Behavior on border.color { ColorAnimation { duration: 300 } }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: window.s(14)
                                    opacity: locksList || isHighlighted ? 1.0 : 0.0
                                    color: "transparent"
                                    border.width: isHighlighted && !locksList ? 1 : window.s(2)
                                    border.color: floatCard.isFailed ? window.red : "transparent"
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: isHighlighted && !locksList ? 1 : window.s(2)
                                        radius: window.s(12)
                                        color: window.base
                                        opacity: locksList ? 0.9 : 1.0
                                    }
                                    
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: floatCard.isFailed ? Qt.lighter(window.red, 1.15) : Qt.lighter(window.activeColor, 1.15) }
                                        GradientStop { position: 1.0; color: floatCard.isFailed ? window.red : window.activeColor }
                                    }
                                    z: -1
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: window.s(14)
                                    color: "#ffffff"
                                    opacity: floatCard.flashOpacity
                                    PropertyAnimation on opacity { id: cardFlashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                                    z: 5
                                }

                                Canvas {
                                    id: waveCanvas
                                    anchors.fill: parent
                                    
                                    property real scaleTrigger: window.s(1)
                                    onScaleTriggerChanged: requestPaint()

                                    property real wavePhase: 0.0
                                    
                                    NumberAnimation on wavePhase {
                                        running: floatCard.renderFill > 0.0 && floatCard.renderFill < 1.0
                                        loops: Animation.Infinite
                                        from: 0; to: Math.PI * 2
                                        duration: 800
                                    }

                                    onWavePhaseChanged: requestPaint()
                                    Connections { target: floatCard; function onRenderFillChanged() { waveCanvas.requestPaint() } }

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        var s = window.s;
                                        ctx.clearRect(0, 0, width, height);
                                        if (floatCard.renderFill <= 0.001) return;

                                        var currentW = width * floatCard.renderFill;
                                        var r = s(14); 

                                        ctx.save();
                                        ctx.beginPath();
                                        ctx.moveTo(0, 0);
                                        
                                        if (floatCard.renderFill < 0.99) {
                                            var waveAmp = s(12) * Math.sin(floatCard.renderFill * Math.PI); 
                                            if (currentW - waveAmp < 0) waveAmp = currentW;
                                            var cp1x = currentW + Math.sin(wavePhase) * waveAmp;
                                            var cp2x = currentW + Math.cos(wavePhase + Math.PI) * waveAmp;

                                            ctx.lineTo(currentW, 0);
                                            ctx.bezierCurveTo(cp2x, height * 0.33, cp1x, height * 0.66, currentW, height);
                                            ctx.lineTo(0, height);
                                        } else {
                                            ctx.lineTo(width, 0);
                                            ctx.lineTo(width, height);
                                            ctx.lineTo(0, height);
                                        }
                                        ctx.closePath();
                                        ctx.clip(); 

                                        ctx.beginPath();
                                        ctx.moveTo(r, 0);
                                        ctx.lineTo(width - r, 0);
                                        ctx.arcTo(width, 0, width, r, r);
                                        ctx.lineTo(width, height - r);
                                        ctx.arcTo(width, height, width - r, height, r);
                                        ctx.lineTo(r, height);
                                        ctx.arcTo(0, height, 0, height - r, r);
                                        ctx.lineTo(0, r);
                                        ctx.arcTo(0, 0, r, 0, r);
                                        ctx.closePath();

                                        var grad = ctx.createLinearGradient(0, 0, currentW, 0);
                                        grad.addColorStop(0, Qt.lighter(window.activeColor, 1.15).toString());
                                        grad.addColorStop(1, window.activeColor.toString());
                                        ctx.fillStyle = grad;
                                        ctx.fill();

                                        ctx.restore();
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.color: window.activeColor
                                    border.width: window.s(2)
                                    visible: parent.isHighlighted && !parent.isMyBusy && !parent.isCurrentlyConnected && !parent.isFailed
                                    
                                    SequentialAnimation on scale {
                                        loops: Animation.Infinite; running: parent.visible
                                        NumberAnimation { to: 1.15; duration: 1200; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                                    }
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite; running: parent.visible
                                        NumberAnimation { to: 0.0; duration: 1200; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 0.8; duration: 1200; easing.type: Easing.InOutSine }
                                    }
                                }

                                RowLayout {
                                    id: baseTextRow
                                    anchors.fill: parent
                                    anchors.margins: window.s(12)
                                    spacing: window.s(10)
                                    
                                    Text {
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(20)
                                        color: floatCard.isFailed ? window.red : (floatCard.isMyBusy ? window.text : window.activeColor)
                                        text: icon
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: window.s(2)
                                        
                                        Item {
                                            id: nameContainerBase
                                            Layout.fillWidth: true
                                            height: window.s(18)
                                            clip: true

                                            Text {
                                                id: baseNameText
                                                anchors.left: parent.left
                                                anchors.leftMargin: floatCard.textOffset
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: floatCard.itemName
                                                font.family: "JetBrains Mono"
                                                font.weight: Font.Bold
                                                font.pixelSize: window.s(13)
                                                color: floatCard.isFailed ? window.red : (floatCard.isHighlighted ? window.activeColor : window.text)
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                            Text {
                                                anchors.left: baseNameText.right
                                                anchors.leftMargin: window.s(30)
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: floatCard.doMarquee
                                                text: floatCard.itemName
                                                font.family: "JetBrains Mono"
                                                font.weight: Font.Bold
                                                font.pixelSize: window.s(13)
                                                color: floatCard.isFailed ? window.red : (floatCard.isHighlighted ? window.activeColor : window.text)
                                            }
                                        }
                                        
                                        Text {
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(10)
                                            color: floatCard.isFailed ? window.maroon : (floatCard.isMyBusy ? window.activeColor : window.overlay0)
                                            text: floatCard.isFailed ? "Connection Failed" : (floatCard.isMyBusy ? "Connecting..." : (floatCard.renderFill > 0.1 && floatCard.renderFill < 1.0 ? "Hold..." : action))
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }
                                }

                                Item {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: floatCard.width * floatCard.renderFill
                                    clip: true
                                    
                                    RowLayout {
                                        x: baseTextRow.x; y: baseTextRow.y
                                        width: baseTextRow.width; height: baseTextRow.height
                                        spacing: window.s(10)
                                        
                                        Text { font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(20); color: window.crust; text: icon }
                                        
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: window.s(2)

                                            Item {
                                                Layout.fillWidth: true
                                                height: window.s(18)
                                                clip: true
                                                
                                                Text {
                                                    id: filledNameText
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: floatCard.textOffset
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: floatCard.itemName
                                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.crust 
                                                }
                                                Text { 
                                                    anchors.left: filledNameText.right
                                                    anchors.leftMargin: window.s(30)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: floatCard.doMarquee
                                                    text: floatCard.itemName
                                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.crust 
                                                }
                                            }
                                            Text {
                                                font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.crust
                                                text: floatCard.isMyBusy ? "Connecting..." : (floatCard.renderFill > 0.1 && floatCard.renderFill < 1.0 ? "Hold..." : action)
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: floatMa
                                    anchors.fill: parent
                                    hoverEnabled: floatCard.isInteractable
                                    
                                    cursorShape: (floatCard.triggered || floatCard.isMyBusy || floatCard.renderFill === 1.0 || !floatCard.isInteractable) ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    
                                    onPressed: { 
                                        if (floatCard.isInteractable && !floatCard.triggered && !floatCard.isMyBusy && floatCard.fillLevel === 0.0) {
                                            if (window.pendingWifiId !== "") {
                                                window.pendingWifiId = ""; window.pendingWifiSsid = "";
                                            }
                                            drainAnim.stop()
                                            fillAnim.start()
                                        }
                                    }
                                    onReleased: {
                                        if (floatCard.isInteractable && !floatCard.triggered && !floatCard.isMyBusy && floatCard.fillLevel < 1.0) {
                                            fillAnim.stop()
                                            drainAnim.start()
                                        }
                                    }
                                }

                                NumberAnimation {
                                    id: fillAnim
                                    target: floatCard
                                    property: "fillLevel"
                                    to: 1.0
                                    duration: 600 * (1.0 - floatCard.fillLevel) 
                                    easing.type: Easing.InSine
                                    onFinished: {
                                        floatCard.triggered = true;
                                        floatCard.flashOpacity = 0.6;
                                        cardFlashAnim.start();
                                        cardBumpAnim.start();
                                        
                                        if (cmdStr === "TOGGLE_VIEW") {
                                            window.playSfx("switch.wav");
                                            window.showInfoView = !window.showInfoView;
                                            floatCard.triggered = false;
                                            drainAnim.start();
                                        } else if (isInfoNode && cmdStr) {
                                            Quickshell.execDetached(["sh", "-c", cmdStr]);
                                            if (window.activeMode === "bt") btPoller.running = true;
                                            floatCard.triggered = false;
                                            drainAnim.start(); 
                                        } else {
                                            let sec = typeof security !== "undefined" && security ? security.trim().toLowerCase() : "";
                                            let isSecure = sec !== "" && sec !== "open" && sec !== "--" && sec !== "none";
                                            let isSaved = false;
                                            for (let i = 0; i < window.savedWifiNetworks.length; i++) {
                                                if (window.savedWifiNetworks[i] === ssid) { isSaved = true; break; }
                                            }

                                            if (window.activeMode === "wifi" && isSecure && !isSaved) {
                                                window.pendingWifiSsid = ssid;
                                                window.pendingWifiId = floatCard.itemId;
                                            } else {
                                                window.connectDevice(window.activeMode, floatCard.itemId, window.activeMode === "wifi" ? ssid : (window.activeMode === "eth" ? floatCard.itemId : mac), "");
                                            }
                                        }
                                    }
                                }
                                
                                NumberAnimation {
                                    id: drainAnim
                                    target: floatCard
                                    property: "fillLevel"
                                    to: 0.0
                                    duration: 1500 * floatCard.fillLevel 
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: window.s(25)
                width: window.s(360)
                height: window.s(54)
                radius: window.s(14)
                color: "#1affffff" 
                border.color: "#1affffff"
                border.width: 1
                visible: window.ethPresent || window.wifiPresent || window.btPresent

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: window.s(6)
                    spacing: window.s(6)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: window.ethPresent
                        radius: window.s(10)
                        color: window.activeMode === "eth" ? "transparent" : (ethTabMa.containsMouse ? window.surface1 : "transparent")
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: window.s(10)
                            opacity: window.activeMode === "eth" ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.lighter(window.sharedAccent, 1.15) }
                                GradientStop { position: 1.0; color: window.sharedAccent }
                            }
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: window.s(8)
                            Text { font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.activeMode === "eth" ? window.crust : window.text; text: "󰈀"; Behavior on color { ColorAnimation{duration:200} } }
                            Text { font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(13); color: window.activeMode === "eth" ? window.crust : window.text; text: "Ethernet"; Behavior on color { ColorAnimation{duration:200} } }
                        }
                        MouseArea {
                            id: ethTabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (window.pendingWifiId !== "") { window.pendingWifiId = ""; window.pendingWifiSsid = ""; }
                                if (window.activeMode !== "eth") {
                                    window.powerAnimAllowed = false;
                                    powerAnimBlocker.restart();
                                    window.playSfx("switch.wav");
                                    window.activeMode = "eth";
                                }
                            }
                        }
                    }

                    Rectangle { visible: window.ethPresent && (window.wifiPresent || window.btPresent); width: 1; Layout.fillHeight: true; Layout.margins: window.s(5); color: "#33ffffff" }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: window.wifiPresent
                        radius: window.s(10)
                        
                        color: window.activeMode === "wifi" ? "transparent" : (wifiTabMa.containsMouse ? window.surface1 : "transparent")
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: window.s(10)
                            opacity: window.activeMode === "wifi" ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.lighter(window.sharedAccent, 1.15) }
                                GradientStop { position: 1.0; color: window.sharedAccent }
                            }
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: window.s(8)
                            Text { font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.activeMode === "wifi" ? window.crust : window.text; text: "󰤨"; Behavior on color { ColorAnimation{duration:200} } }
                            Text { font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(13); color: window.activeMode === "wifi" ? window.crust : window.text; text: "Wi-Fi"; Behavior on color { ColorAnimation{duration:200} } }
                        }
                        MouseArea {
                            id: wifiTabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (window.pendingWifiId !== "") { window.pendingWifiId = ""; window.pendingWifiSsid = ""; }
                                if (window.activeMode !== "wifi") {
                                    window.powerAnimAllowed = false;
                                    powerAnimBlocker.restart();
                                    window.playSfx("switch.wav");
                                    window.activeMode = "wifi";
                                }
                            }
                        }
                    }

                    Rectangle { visible: window.wifiPresent && window.btPresent; width: 1; Layout.fillHeight: true; Layout.margins: window.s(5); color: "#33ffffff" }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: window.btPresent
                        radius: window.s(10)
                        color: window.activeMode === "bt" ? "transparent" : (btTabMa.containsMouse ? window.surface1 : "transparent")
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: window.s(10)
                            opacity: window.activeMode === "bt" ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.lighter(window.btAccent, 1.15) }
                                GradientStop { position: 1.0; color: window.btAccent }
                            }
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: window.s(8)
                            Text { font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.activeMode === "bt" ? window.crust : window.text; text: "󰂯"; Behavior on color { ColorAnimation{duration:200} } }
                            Text { font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(13); color: window.activeMode === "bt" ? window.crust : window.text; text: "Bluetooth"; Behavior on color { ColorAnimation{duration:200} } }
                        }
                        MouseArea {
                            id: btTabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (window.pendingWifiId !== "") { window.pendingWifiId = ""; window.pendingWifiSsid = ""; }
                                if (window.activeMode !== "bt") {
                                    window.powerAnimAllowed = false;
                                    powerAnimBlocker.restart();
                                    window.playSfx("switch.wav");
                                    window.activeMode = "bt";
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: powerToggleContainer
                z: 100
                x: window.currentPower ? parent.width - window.s(30) - window.s(48) : parent.width / 2 - window.s(80)
                y: window.currentPower ? parent.height - window.s(30) - window.s(48) : (parent.height - window.s(80)) / 2 - window.s(80)
                width: window.currentPower ? window.s(48) : window.s(160)
                height: width

                Behavior on x { enabled: window.powerAnimAllowed; NumberAnimation { duration: 800; easing.type: Easing.InOutQuint } }
                Behavior on y { enabled: window.powerAnimAllowed; NumberAnimation { duration: 800; easing.type: Easing.InOutQuint } }
                Behavior on width { enabled: window.powerAnimAllowed; NumberAnimation { duration: 800; easing.type: Easing.InOutQuint } }

                MultiEffect {
                    source: powerBtnRect
                    anchors.fill: powerBtnRect
                    shadowEnabled: true
                    shadowColor: "#000000"
                    shadowOpacity: 0.4
                    shadowBlur: 1.2
                    shadowVerticalOffset: window.s(4)
                }

                Rectangle {
                    id: powerBtnRect
                    anchors.fill: parent
                    radius: width / 2
                    
                    scale: pwrMa.pressed ? 0.95 : (pwrMa.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: window.currentPower ? "transparent" : window.surface1 }
                        GradientStop { position: 1.0; color: window.currentPower ? "transparent" : window.crust }
                    }

                    border.color: window.currentPowerPending ? window.activeColor : (window.currentPower ? "transparent" : window.surface2)
                    border.width: window.s(2)
                    Behavior on border.color { enabled: window.powerAnimAllowed; ColorAnimation { duration: 800; easing.type: Easing.InOutQuint } }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        opacity: window.currentPower ? 1.0 : 0.0
                        Behavior on opacity { enabled: window.powerAnimAllowed; NumberAnimation { duration: 800; easing.type: Easing.InOutQuint } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.lighter(window.activeColor, 1.15) }
                            GradientStop { position: 1.0; color: window.activeColor }
                        }
                    }

                    Text {
                        id: pwrIcon
                        anchors.centerIn: parent
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: window.currentPower ? window.s(22) : window.s(64)
                        color: window.currentPower ? window.crust : window.text
                        text: window.currentPowerPending ? "󰑮" : ""
                        Behavior on font.pixelSize { enabled: window.powerAnimAllowed; NumberAnimation { duration: 800; easing.type: Easing.InOutQuint } }
                        Behavior on color { enabled: window.powerAnimAllowed; ColorAnimation { duration: 800; easing.type: Easing.InOutQuint } }

                        RotationAnimation {
                            target: pwrIcon
                            property: "rotation"
                            from: 0; to: 360
                            duration: 800
                            loops: Animation.Infinite
                            running: window.currentPowerPending
                            onRunningChanged: {
                                if (!running) pwrIcon.rotation = 0;
                            }
                        }
                    }

                    MouseArea {
                        id: pwrMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (window.pendingWifiId !== "") { window.pendingWifiId = ""; window.pendingWifiSsid = ""; }
                            
                            if (window.activeMode === "eth") {
                                if (window.ethPowerPending) return;
                                window.expectedEthPower = window.ethPower === "on" ? "off" : "on";
                                window.ethPowerPending = true;
                                if (window.expectedEthPower === "on") window.playSfx("power_on.wav"); else window.playSfx("power_off.wav");
                                ethPendingReset.restart();
                                window.ethPower = window.expectedEthPower; 
                                let targetDev = window.ethDeviceName !== "" ? window.ethDeviceName : (window.currentCores[0] ? window.currentCores[0].id : "");
                                if (targetDev !== "") {
                                    if (window.expectedEthPower === "on") Quickshell.execDetached(["nmcli", "device", "connect", targetDev]);
                                    else Quickshell.execDetached(["nmcli", "device", "disconnect", targetDev]);
                                }
                                ethPoller.running = true;
                            } else if (window.activeMode === "wifi") {
                                if (window.wifiPowerPending) return;
                                window.expectedWifiPower = window.wifiPower === "on" ? "off" : "on";
                                window.wifiPowerPending = true;
                                if (window.expectedWifiPower === "on") window.playSfx("power_on.wav"); else window.playSfx("power_off.wav");
                                wifiPendingReset.restart();
                                window.wifiPower = window.expectedWifiPower;
                                Quickshell.execDetached(["nmcli", "radio", "wifi", window.wifiPower]);
                                wifiPoller.running = true;
                            } else {
                                if (window.btPowerPending) return;
                                window.expectedBtPower = window.btPower === "on" ? "off" : "on";
                                window.btPowerPending = true;
                                if (window.expectedBtPower === "on") window.playSfx("power_on.wav"); else window.playSfx("power_off.wav");
                                btPendingReset.restart();
                                window.btPower = window.expectedBtPower;
                                Quickshell.execDetached(["bash", window.scriptsDir + "/bluetooth_panel_logic.sh", "--toggle"]);
                                btPoller.running = true;
                            }
                        }
                    }
                }
            }
        }
    }
}
