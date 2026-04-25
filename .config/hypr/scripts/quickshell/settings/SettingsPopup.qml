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

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }
    function s(val) { 
        return scaler.s(val); 
    }
    property bool isLayoutDropdownOpen: false

    property bool isSearchMode: false
    property string globalSearchQuery: ""

    property int highlightedBox: -1

    property int searchHighlightIndex: -1

    property var searchResultItems: []

    function rebuildSearchResultItems() {
        let items = [];
        for (let i = 0; i < root.allSettingsCards.length; i++) {
            let card = root.allSettingsCards[i];
            if (root.globalSearchMatches(card, root.globalSearchQuery)) {
                items.push({ kind: "card", cardIndex: i, kbIndex: -1 });
            }
        }
        let kbIndices = root.matchingKeybindIndices;
        for (let j = 0; j < kbIndices.length; j++) {
            items.push({ kind: "keybind", cardIndex: -1, kbIndex: kbIndices[j] });
        }
        root.searchResultItems = items;
        if (root.searchHighlightIndex >= items.length) {
            root.searchHighlightIndex = items.length - 1;
        }
    }

    onGlobalSearchQueryChanged: {
        root.matchingKeybindIndices = root.getMatchingKeybindIndices(root.globalSearchQuery);
        root.rebuildSearchResultItems();
        root.searchHighlightIndex = -1;
    }

    onIsSearchModeChanged: {
        if (!root.isSearchMode) {
            root.searchHighlightIndex = -1;
        } else {
            root.rebuildSearchResultItems();
        }
    }

    function activateSearchHighlight() {
        if (root.searchHighlightIndex < 0 || root.searchHighlightIndex >= root.searchResultItems.length) return;
        let item = root.searchResultItems[root.searchHighlightIndex];
        if (item.kind === "card") {
            let card = root.allSettingsCards[item.cardIndex];
            jumpToSettingTimer.targetTab = card.tab;
            jumpToSettingTimer.targetBox = card.boxIndex;
            jumpToSettingTimer.start();
            root.currentTab = card.tab;
            if (card.tab === 0) root.tab0Loaded = true;
            else if (card.tab === 1) root.tab1Loaded = true;
            else if (card.tab === 2) root.tab2Loaded = true;
        } else {
            jumpToSettingTimer.targetTab = 2;
            jumpToSettingTimer.targetBox = item.kbIndex;
            jumpToSettingTimer.start();
            root.currentTab = 2;
            root.tab2Loaded = true;
        }
        root.isSearchMode = false;
        root.forceActiveFocus();
        globalSearchInput.text = "";
        root.globalSearchQuery = "";
    }

    function scrollSearchToHighlight(idx) {
        if (idx < 0 || idx >= root.searchResultItems.length) return;
        let nCards = 0;
        for (let i = 0; i < root.allSettingsCards.length; i++) {
            if (root.globalSearchMatches(root.allSettingsCards[i], root.globalSearchQuery)) nCards++;
        }
        let itemH = root.s(60) + root.s(10);
        let headerH = (root.matchingKeybindIndices.length > 0) ? root.s(32) + root.s(10) : 0;
        let approxY = 0;
        let it = root.searchResultItems[idx];
        if (it.kind === "card") {
            let pos = 0;
            for (let i = 0; i < root.allSettingsCards.length; i++) {
                if (root.globalSearchMatches(root.allSettingsCards[i], root.globalSearchQuery)) {
                    if (root.allSettingsCards[i] === root.allSettingsCards[item_cardIndex_from(idx)]) break;
                    pos++;
                }
            }
            approxY = pos * itemH;
        } else {
            approxY = nCards * itemH + headerH + (idx - nCards) * itemH;
        }
        let target = Math.max(0, approxY - root.s(20));
        searchResultsFlickable.contentY = Math.min(target, Math.max(0, searchResultsFlickable.contentHeight - searchResultsFlickable.height));
    }

    function item_cardIndex_from(idx) {
        let item = root.searchResultItems[idx];
        return item.cardIndex;
    }

    function clearHighlight() {
        root.highlightedBox = -1;
    }

    function maxHighlightForTab(tab) {
        if (tab === 0) return 6;
        if (tab === 1) return 3;
        if (tab === 2) return dynamicKeybindsModel.count - 1;
        return -1;
    }

    function activateHighlightedBox() {
        if (root.currentTab === 0) {
            if (root.highlightedBox === 0) {
                root.setOpenGuideAtStartup = !root.setOpenGuideAtStartup;
            } else if (root.highlightedBox === 1) {
                root.setTopbarHelpIcon = !root.setTopbarHelpIcon;
            } else if (root.highlightedBox === 2) {
            } else if (root.highlightedBox === 3) {
                if (generalLoader.item) generalLoader.item.focusLangInput();
            } else if (root.highlightedBox === 4) {
                root.isLayoutDropdownOpen = !root.isLayoutDropdownOpen;
            } else if (root.highlightedBox === 5) {
                if (generalLoader.item) generalLoader.item.focusWpDirInput();
            } else if (root.highlightedBox === 6) {
            }
        } else if (root.currentTab === 1) {
            if (root.highlightedBox === 0) {
            } else if (root.highlightedBox === 1) {
                if (weatherLoader.item) weatherLoader.item.focusApiKey();
            } else if (root.highlightedBox === 2) {
                if (weatherLoader.item) weatherLoader.item.focusCityId();
            } else if (root.highlightedBox === 3) {
            }
        } else if (root.currentTab === 2) {
            if (root.highlightedBox >= 0 && root.highlightedBox < dynamicKeybindsModel.count) {
                let isEd = dynamicKeybindsModel.get(root.highlightedBox).isEditing;
                dynamicKeybindsModel.setProperty(root.highlightedBox, "isEditing", !isEd);
            }
        }
    }

    onHighlightedBoxChanged: {
        if (root.highlightedBox < 0) return;
        Qt.callLater(function() { root.scrollHighlightedIntoView(); });
    }

    function scrollHighlightedIntoView() {
        let box = root.highlightedBox;
        if (box < 0) return;
        if (root.currentTab === 0 && generalLoader.item) {
            let approxY = 0;
            if (box === 0 || box === 1) approxY = 0;
            else if (box === 2) approxY = root.s(120);
            else if (box === 3 || box === 4) approxY = root.s(240);
            else if (box === 5) approxY = root.s(400);
            else if (box === 6) approxY = root.s(520);
            generalLoader.item.scrollToBox(approxY);
        } else if (root.currentTab === 1 && weatherLoader.item) {
            let approxY = 0;
            if (box === 0) approxY = 0;
            else if (box === 1) approxY = root.s(140);
            else if (box === 2) approxY = root.s(240);
            else if (box === 3) approxY = root.s(340);
            weatherLoader.item.scrollToBox(approxY);
        } else if (root.currentTab === 2 && keybindLoader.item) {
            let approxY = box * root.s(56) + root.s(120);
            keybindLoader.item.scrollToBox(approxY);
        }
    }

    property int currentTab: 0
    property var tabNames: ["General", "Weather", "Keybinds"]
    // FIX 3: Added gear icon for General tab
    property var tabIcons: ["󰒓", "󰖐", "󰌌"]
    property var tabColors: ["teal", "blue", "peach"]

    property bool tab0Loaded: false
    property bool tab1Loaded: false
    property bool tab2Loaded: false

    onCurrentTabChanged: {
        root.clearHighlight();
        if (currentTab === 0) root.tab0Loaded = true;
        else if (currentTab === 1) root.tab1Loaded = true;
        else if (currentTab === 2) root.tab2Loaded = true;
    }

    Keys.onEscapePressed: {
        if (root.isSearchMode) {
            root.isSearchMode = false;
            root.globalSearchQuery = "";
            globalSearchInput.text = "";
            root.searchHighlightIndex = -1;
            event.accepted = true;
        } else if (root.isLayoutDropdownOpen) {
            root.isLayoutDropdownOpen = false;
            event.accepted = true;
        } else if (root.highlightedBox >= 0) {
            root.clearHighlight();
            event.accepted = true;
        } else {
            closeSequence.start();
            event.accepted = true;
        }
    }

    Keys.onTabPressed: (event) => {
        if (root.isSearchMode) return;
        root.currentTab = (root.currentTab + 1) % 3;
        event.accepted = true;
    }
    Keys.onBacktabPressed: (event) => {
        if (root.isSearchMode) return;
        root.currentTab = (root.currentTab + 2) % 3;
        event.accepted = true;
    }

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) || 
            (event.key === Qt.Key_Slash && !root.isSearchMode)) {
            root.isSearchMode = true;
            globalSearchInput.forceActiveFocus();
            event.accepted = true;
            return;
        }

        if (root.isSearchMode) {
            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                root.forceActiveFocus();
                let total = root.searchResultItems.length;
                if (total === 0) { event.accepted = true; return; }
                if (event.key === Qt.Key_Down) {
                    if (root.searchHighlightIndex < total - 1) {
                        root.searchHighlightIndex++;
                    } else {
                        root.searchHighlightIndex = 0;
                    }
                } else {
                    if (root.searchHighlightIndex > 0) {
                        root.searchHighlightIndex--;
                    } else if (root.searchHighlightIndex === 0) {
                        root.searchHighlightIndex = total - 1;
                    } else {
                        root.searchHighlightIndex = total - 1;
                    }
                }
                root.scrollSearchHighlightIntoView(root.searchHighlightIndex);
                event.accepted = true;
                return;
            }
            return;
        }

        if (root.isLayoutDropdownOpen) {
            if (event.key === Qt.Key_Down) {
                if (generalLoader.item) generalLoader.item.layoutListIncrementIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                if (generalLoader.item) generalLoader.item.layoutListDecrementIndex();
                event.accepted = true;
            }
            return;
        }
        
        // FIX 2: Left/Right arrow keys adjust UI Scale (box 2) and Workspaces (box 6)
        if (event.key === Qt.Key_Left) {
            if (root.currentTab === 0 && root.highlightedBox === 2) {
                root.setUiScale = Math.max(0.5, (root.setUiScale - 0.1).toFixed(1));
                event.accepted = true;
                return;
            } else if (root.currentTab === 0 && root.highlightedBox === 6) {
                root.setWorkspaceCount = Math.max(2, root.setWorkspaceCount - 1);
                event.accepted = true;
                return;
            }
        }
        if (event.key === Qt.Key_Right) {
            if (root.currentTab === 0 && root.highlightedBox === 2) {
                root.setUiScale = Math.min(2.0, (root.setUiScale + 0.1).toFixed(1));
                event.accepted = true;
                return;
            } else if (root.currentTab === 0 && root.highlightedBox === 6) {
                root.setWorkspaceCount = Math.min(10, root.setWorkspaceCount + 1);
                event.accepted = true;
                return;
            }
        }

        if (event.key === Qt.Key_Down) {
            let maxIdx = root.maxHighlightForTab(root.currentTab);
            if (maxIdx < 0) { event.accepted = true; return; }
            if (root.highlightedBox < maxIdx) {
                root.highlightedBox = root.highlightedBox + 1;
            } else if (root.highlightedBox === maxIdx) {
                root.highlightedBox = -1;
            } else {
                root.highlightedBox = 0;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            let maxIdx = root.maxHighlightForTab(root.currentTab);
            if (maxIdx < 0) { event.accepted = true; return; }
            if (root.highlightedBox > 0) {
                root.highlightedBox = root.highlightedBox - 1;
            } else if (root.highlightedBox === 0) {
                root.highlightedBox = -1;
            } else {
                root.highlightedBox = maxIdx;
            }
            event.accepted = true;
        }
    }

    Keys.onReturnPressed: (event) => root.handleRootEnter(event)
    Keys.onEnterPressed: (event) => root.handleRootEnter(event)

    function handleRootEnter(event) {
        if (root.isSearchMode) {
            if (root.searchHighlightIndex >= 0) {
                root.activateSearchHighlight();
                event.accepted = true;
            }
            return;
        }
        if (root.isLayoutDropdownOpen) {
            if (generalLoader.item) generalLoader.item.acceptLayoutSelection();
            root.isLayoutDropdownOpen = false;
            event.accepted = true;
            return;
        }
        if (root.highlightedBox >= 0) {
            root.activateHighlightedBox();
            event.accepted = true;
            return;
        }
        if (root.currentTab === 0) root.saveAppSettings();
        else if (root.currentTab === 1) root.saveWeatherConfig();
        else if (root.currentTab === 2) root.saveAllKeybinds();
        event.accepted = true;
    }

    function scrollSearchHighlightIntoView(idx) {
        if (idx < 0 || idx >= root.searchResultItems.length) return;

        let nCards = 0;
        for (let i = 0; i < root.allSettingsCards.length; i++) {
            if (root.globalSearchMatches(root.allSettingsCards[i], root.globalSearchQuery)) nCards++;
        }
        let hasKbHeader = root.matchingKeybindIndices.length > 0;
        let itemH = root.s(60) + root.s(10);
        let headerH = hasKbHeader ? (root.s(32) + root.s(10)) : 0;

        let approxY = 0;
        let it = root.searchResultItems[idx];
        if (it.kind === "card") {
            let pos = 0;
            for (let i = 0; i < root.searchResultItems.length; i++) {
                if (i === idx) break;
                if (root.searchResultItems[i].kind === "card") pos++;
            }
            approxY = pos * itemH;
        } else {
            let kbPos = 0;
            for (let i = 0; i < root.searchResultItems.length; i++) {
                if (i === idx) break;
                if (root.searchResultItems[i].kind === "keybind") kbPos++;
            }
            approxY = nCards * itemH + headerH + kbPos * itemH;
        }

        let viewH = searchResultsFlickable.height;
        let contentH = searchResultsFlickable.contentHeight;
        let curY = searchResultsFlickable.contentY;
        let itemTop = approxY;
        let itemBottom = approxY + root.s(60);

        if (itemTop < curY + root.s(10)) {
            searchResultsFlickable.contentY = Math.max(0, itemTop - root.s(10));
        } else if (itemBottom > curY + viewH - root.s(10)) {
            searchResultsFlickable.contentY = Math.min(contentH - viewH, itemBottom - viewH + root.s(10));
        }
    }

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
    readonly property color teal: _theme.teal
    readonly property color green: _theme.green
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red

    property int initialWorkspaceCount: 8 
    property real setUiScale: 1.0
    property bool setOpenGuideAtStartup: true
    property bool setTopbarHelpIcon: true
    property int setWorkspaceCount: 8
    property string setWallpaperDir: {
        const dir = Quickshell.env("WALLPAPER_DIR")
        return (dir && dir !== "") 
        ? dir 
        : Quickshell.env("HOME") + "/Pictures/Wallpapers"
    }
    property string setLanguage: ""
    property string setKbOptions: "grp:alt_shift_toggle"
    property bool requiresReload: false

    property var kbToggleModelArr: [
        { label: "Alt + Shift", val: "grp:alt_shift_toggle" },
        { label: "Win + Space", val: "grp:win_space_toggle" },
        { label: "Caps Lock", val: "grp:caps_toggle" },
        { label: "Ctrl + Shift", val: "grp:ctrl_shift_toggle" },
        { label: "Ctrl + Alt", val: "grp:ctrl_alt_toggle" },
        { label: "Right Alt", val: "grp:toggle" },
        { label: "No Toggle", val: "" }
    ]

    function getKbToggleLabel(val) {
        for (let i = 0; i < root.kbToggleModelArr.length; i++) {
            if (root.kbToggleModelArr[i].val === val) return root.kbToggleModelArr[i].label;
        }
        return "Alt + Shift";
    }

    function saveAppSettings() {
        let config = {
            "uiScale": root.setUiScale,
            "openGuideAtStartup": root.setOpenGuideAtStartup,
            "topbarHelpIcon": root.setTopbarHelpIcon,
            "wallpaperDir": root.setWallpaperDir,
            "language": root.setLanguage,
            "kbOptions": root.setKbOptions,
            "workspaceCount": root.setWorkspaceCount
        };
        let jsonString = JSON.stringify(config);
        let cmd = "mkdir -p ~/.config/hypr/ && [ ! -f ~/.config/hypr/settings.json ] && echo '{}' > ~/.config/hypr/settings.json; " +
                  "jq '. + " + jsonString + "' ~/.config/hypr/settings.json > ~/.config/hypr/settings.json.tmp && " +
                  "mv ~/.config/hypr/settings.json.tmp ~/.config/hypr/settings.json && " +
                  "notify-send 'Quickshell' 'Settings Applied Successfully!'";
        Quickshell.execDetached(["bash", "-c", cmd]);
        if (root.setWorkspaceCount !== root.initialWorkspaceCount) {
            Quickshell.execDetached(["qs", "-p", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/TopBar.qml", "ipc", "call", "topbar", "queueReload"]);
            root.initialWorkspaceCount = root.setWorkspaceCount; 
        }
    }

    property string selectedUnit: "metric"
    property bool apiKeyVisible: false
    property string _apiKeyText: ""
    property string _cityIdText: ""

    function saveWeatherConfig() {
        var cache_weather = Quickshell.env("HOME") + "/.cache/quickshell/weather";
        var file = Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/calendar/.env";
        var cmds = [
            "mkdir -p $(dirname " + file + ")",
            "echo '# OpenWeather API Configuration (OVERWRITE, not add)' > " + file,
            "echo 'OPENWEATHER_KEY=" + root._apiKeyText + "' >> " + file,
            "echo 'OPENWEATHER_CITY_ID=" + root._cityIdText + "' >> " + file,
            "echo 'OPENWEATHER_UNIT=" + root.selectedUnit + "' >> " + file,
            "rm -rf " + cache_weather,
            "notify-send 'Weather' 'API configuration saved successfully!'"
        ];
        var finalCmd = cmds.join(" && ");
        Quickshell.execDetached(["bash", "-c", finalCmd]);
    }

    Process {
        id: envReader
        command: ["bash", "-c", "cat ~/.config/hypr/scripts/quickshell/calendar/.env 2>/dev/null || echo ''"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text ? this.text.trim().split('\n') : [];
                for (let line of lines) {
                    line = line.trim();
                    if (line.startsWith("OPENWEATHER_KEY=")) root._apiKeyText = line.substring(16).trim();
                    else if (line.startsWith("OPENWEATHER_CITY_ID=")) root._cityIdText = line.substring(20).trim();
                    else if (line.startsWith("OPENWEATHER_UNIT=")) root.selectedUnit = line.substring(17).trim();
                }
            }
        }
    }

    ListModel { id: dynamicKeybindsModel }
    
    property var bindTypes: ["bind", "binde", "bindl", "bindel", "bindm"]
    property var dispatchers: ["exec", "exec-once", "dispatch", "workspace", "movetoworkspace", "movewindow", "resizeactive", "movefocus", "togglefloating", "killactive"]

    function buildKeybinds() {
        dynamicKeybindsModel.clear(); 
    }

    function saveAllKeybinds() {
        let bindsArray = [];
        for (let i = 0; i < dynamicKeybindsModel.count; i++) {
            let item = dynamicKeybindsModel.get(i);
            if (!item.key && !item.command) continue; 
            bindsArray.push({
                type: item.type,
                mods: item.mods,
                key: item.key,
                dispatcher: item.dispatcher,
                command: item.command
            });
        }
        let jsonStr = JSON.stringify(bindsArray).replace(/'/g, "'\\''"); 
        let cmd = "mkdir -p ~/.config/hypr/ && [ ! -f ~/.config/hypr/settings.json ] && echo '{}' > ~/.config/hypr/settings.json; " +
                  "jq '.keybinds = " + jsonStr + "' ~/.config/hypr/settings.json > ~/.config/hypr/settings.json.tmp && " +
                  "mv ~/.config/hypr/settings.json.tmp ~/.config/hypr/settings.json && " +
                  "notify-send 'Quickshell' 'Keybinds Saved Successfully!'";
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    function validateKeybind(index, mods, key, dispatcher, command) {
        let validMods = ["SHIFT", "SHIFT_L", "SHIFT_R", "CAPS", "CTRL", "CONTROL", "ALT", "MOD2", "MOD3", "SUPER", "WIN", "LOGO", "MOD4", "MOD5", "$mainMod"];
        let modArray = mods ? mods.replace(/&/g, " ").split(" ").filter(x => x !== "") : [];
        
        for (let i = 0; i < modArray.length; i++) {
            if (!validMods.includes(modArray[i])) {
                return "Invalid modifier: " + modArray[i] + ".\nKeys like SPACE cannot be used as modifiers.";
            }
        }

        let currentModsNormalized = modArray.slice().sort().join(" ");
        let currentKeyNormalized = key.trim().toLowerCase();

        for (let i = 0; i < dynamicKeybindsModel.count; i++) {
            if (i === index) continue;

            let item = dynamicKeybindsModel.get(i);
            if (!item.key) continue;

            let itemModsNormalized = item.mods ? item.mods.replace(/&/g, " ").split(" ").filter(x => x !== "").sort().join(" ") : "";
            let itemKeyNormalized = item.key.trim().toLowerCase();

            if (itemModsNormalized === currentModsNormalized && itemKeyNormalized === currentKeyNormalized) {
                return "Duplicate keybind!\nThis exact combination already exists.";
            }
        }

        return "VALID";
    }

    Timer {
        id: scrollTimer
        interval: 50
        onTriggered: {
            if (keybindLoader.item) {
                keybindLoader.item.scrollToBottom();
            }
        }
    }

    Timer {
        id: jumpToSettingTimer
        interval: 100
        property int targetTab: 0
        property int targetBox: -1

        onTriggered: {
            if (targetBox >= 0) {
                root.highlightedBox = targetBox;
                
                let approxY = 0;

                if (targetTab === 0 && generalLoader.item) {
                    if (targetBox === 0 || targetBox === 1) approxY = 0;
                    else if (targetBox === 2) approxY = root.s(120);
                    else if (targetBox === 3 || targetBox === 4) approxY = root.s(240);
                    else if (targetBox === 5) approxY = root.s(400);
                    else if (targetBox === 6) approxY = root.s(520);
                    generalLoader.item.scrollTo(approxY);
                } else if (targetTab === 1 && weatherLoader.item) {
                    if (targetBox === 1) approxY = root.s(140);
                    else if (targetBox === 2) approxY = root.s(240);
                    else if (targetBox === 3) approxY = root.s(340);
                    weatherLoader.item.scrollTo(approxY);
                } else if (targetTab === 2 && keybindLoader.item) {
                    approxY = targetBox * (root.s(56)) + root.s(120);
                    keybindLoader.item.scrollTo(approxY);
                }

                targetBox = -1;
            }
        }
    }    

    Process {
        id: hyprLangReader
        command: ["bash", "-c", "grep -m1 '^ *kb_layout *=' ~/.config/hypr/hyprland.conf | cut -d'=' -f2 | tr -d ' '"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out.length > 0 && root.setLanguage === "") {
                    root.setLanguage = out;
                }
            }
        }
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
                        if (parsed.uiScale !== undefined) root.setUiScale = parsed.uiScale;
                        if (parsed.openGuideAtStartup !== undefined) root.setOpenGuideAtStartup = parsed.openGuideAtStartup;
                        if (parsed.topbarHelpIcon !== undefined) root.setTopbarHelpIcon = parsed.topbarHelpIcon;
                        if (parsed.wallpaperDir !== undefined) root.setWallpaperDir = parsed.wallpaperDir;
                        if (parsed.language !== undefined && parsed.language !== "") root.setLanguage = parsed.language;
                        if (parsed.kbOptions !== undefined) root.setKbOptions = parsed.kbOptions;
                        if (parsed.workspaceCount !== undefined) {
                            root.setWorkspaceCount = parsed.workspaceCount;
                            root.initialWorkspaceCount = parsed.workspaceCount; 
                        }
                        if (parsed.keybinds !== undefined && Array.isArray(parsed.keybinds)) {
                            dynamicKeybindsModel.clear();
                            let tempBinds = [];
                            for (let k of parsed.keybinds) {
                                tempBinds.push({
                                    type: k.type || "bind",
                                    mods: k.mods || "",
                                    key: k.key || "",
                                    dispatcher: k.dispatcher || "exec",
                                    command: k.command || "",
                                    isEditing: false
                                });
                            }
                            dynamicKeybindsModel.append(tempBinds); 
                        } else {
                            buildKeybinds();
                            root.saveAllKeybinds();
                        }
                    } else {
                        root.saveAppSettings();
                        buildKeybinds();
                        root.saveAllKeybinds();
                    }
                } catch (e) {
                    console.log("Error parsing global settings:", e);
                    buildKeybinds();
                }
                root.dataReady = true;
            }
        }
    }
    property bool dataReady: false

    ListModel {
        id: langModel
        ListElement { code: "us"; name: "English (US)" }
        ListElement { code: "gb"; name: "English (UK)" }
        ListElement { code: "au"; name: "English (Australia)" }
        ListElement { code: "ca"; name: "English/French (Canada)" }
        ListElement { code: "ie"; name: "English (Ireland)" }
        ListElement { code: "nz"; name: "English (New Zealand)" }
        ListElement { code: "za"; name: "English (South Africa)" }
        ListElement { code: "fr"; name: "French" }
        ListElement { code: "de"; name: "German" }
        ListElement { code: "es"; name: "Spanish" }
        ListElement { code: "pt"; name: "Portuguese" }
        ListElement { code: "it"; name: "Italian" }
        ListElement { code: "se"; name: "Swedish" }
        ListElement { code: "no"; name: "Norwegian" }
        ListElement { code: "dk"; name: "Danish" }
        ListElement { code: "fi"; name: "Finnish" }
        ListElement { code: "pl"; name: "Polish" }
        ListElement { code: "ru"; name: "Russian" }
        ListElement { code: "ua"; name: "Ukrainian" }
        ListElement { code: "cn"; name: "Chinese" }
        ListElement { code: "jp"; name: "Japanese" }
        ListElement { code: "kr"; name: "Korean" }
    }

    ListModel { id: pathSuggestModel }
    ListModel { id: langSearchModel }

    function updateLangSearch(query) {
        langSearchModel.clear();
        let q = query.trim().toLowerCase();
        for (let i = 0; i < langModel.count; i++) {
            let item = langModel.get(i);
            if (q === "" || item.code.toLowerCase().includes(q) || item.name.toLowerCase().includes(q)) {
                langSearchModel.append({ code: item.code, name: item.name });
            }
        }
    }

    Process {
        id: pathSuggestProc
        property string query: ""
        command: ["bash", "-c", "eval ls -dp " + query + "* 2>/dev/null | grep '/$' | head -n 5 || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                pathSuggestModel.clear();
                if (this.text) {
                    let lines = this.text.trim().split('\n');
                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i];
                        if (line.length > 0) {
                            if (line.endsWith('/')) { line = line.slice(0, -1); }
                            pathSuggestModel.append({ path: line });
                        }
                    }
                }
            }
        }
    }

    property var allSettingsCards: [
        { tab: 0, boxIndex: 0, label: "Guide on startup",  desc: "Launch on login",        icon: "󰑊", color: "peach" },
        { tab: 0, boxIndex: 1, label: "Help icon",         desc: "Show button in topbar",  icon: "󰋖", color: "blue" },
        { tab: 0, boxIndex: 2, label: "UI Scale",          desc: "Base size scalar",       icon: "󰁦", color: "sapphire" },
        { tab: 0, boxIndex: 3, label: "Keyboard layouts",  desc: "Matches hyprland.conf",  icon: "󰌌", color: "green" },
        { tab: 0, boxIndex: 4, label: "Layout shortcut",   desc: "Toggle combination",     icon: "󰯍", color: "teal" },
        { tab: 0, boxIndex: 5, label: "Wallpaper directory",desc: "Absolute source path",  icon: "󰋩", color: "mauve" },
        { tab: 0, boxIndex: 6, label: "Workspaces",        desc: "Static count in topbar", icon: "󰽿", color: "red" },
        { tab: 1, boxIndex: 1, label: "API Key",           desc: "OpenWeather API key",    icon: "󰌆", color: "blue" },
        { tab: 1, boxIndex: 2, label: "City ID",           desc: "OpenWeather city ID",    icon: "󰖐", color: "blue" },
        { tab: 1, boxIndex: 3, label: "Temperature Unit",  desc: "Celsius / Fahrenheit / K", icon: "󰔄", color: "blue" }
    ]

    function getMatchingKeybindIndices(query) {
        if (query.trim() === "") return [];
        let results = [];
        try {
            let re = new RegExp(query, "i");
            for (let i = 0; i < dynamicKeybindsModel.count; i++) {
                let item = dynamicKeybindsModel.get(i);
                if (re.test(item.mods) || re.test(item.key) || re.test(item.dispatcher) || re.test(item.command) || re.test(item.type)) {
                    results.push(i);
                }
            }
        } catch(e) {
            let q = query.trim().toLowerCase();
            for (let i = 0; i < dynamicKeybindsModel.count; i++) {
                let item = dynamicKeybindsModel.get(i);
                if ((item.mods && item.mods.toLowerCase().includes(q)) ||
                    (item.key && item.key.toLowerCase().includes(q)) ||
                    (item.dispatcher && item.dispatcher.toLowerCase().includes(q)) ||
                    (item.command && item.command.toLowerCase().includes(q))) {
                    results.push(i);
                }
            }
        }
        return results;
    }

    property var matchingKeybindIndices: []

    function globalSearchMatches(card, query) {
        if (query.trim() === "") return false;
        let q = query.trim().toLowerCase();
        return card.label.toLowerCase().includes(q) || card.desc.toLowerCase().includes(q);
    }

    property real introContent: 0.0
    Component.onCompleted: { 
        root.tab0Loaded = true;
        startupSequence.start(); 
    }

    SequentialAnimation {
        id: startupSequence
        PauseAnimation { duration: 50 }
        NumberAnimation { 
            target: root
            property: "introContent"
            from: 0.0
            to: 1.0
            duration: 600
            easing.type: Easing.OutQuart
        } 
    }

    SequentialAnimation {
        id: closeSequence
        NumberAnimation { 
            target: root
            property: "introContent"
            to: 0.0
            duration: 200
            easing.type: Easing.InQuart
        }
        ScriptAction { 
            script: {
                Quickshell.execDetached(["hyprctl", "dispatch", "submap", "reset"]);

                if (root.requiresReload) {
                    let script = Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh close; " +
                                 "while [ -n \"$(cat /tmp/qs_current_widget 2>/dev/null)\" ]; do sleep 0.1; done; " +
                                 "sleep 0.2; " + 
                                 "qs -p ~/.config/hypr/scripts/quickshell/TopBar.qml ipc call topbar forceReload";
                    Quickshell.execDetached(["bash", "-c", script]);
                } else {
                    Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
                }
            } 
        }    
    }

    Component {
        id: generalTabComponent
        Item {
            id: generalTabRoot

            function focusLangInput() { langInput.forceActiveFocus(); }
            function focusWpDirInput() { wpDirInput.forceActiveFocus(); }
            function layoutListIncrementIndex() { layoutListView.incrementCurrentIndex(); }
            function layoutListDecrementIndex() { layoutListView.decrementCurrentIndex(); }
            function acceptLayoutSelection() {
                if (layoutListView.currentIndex >= 0 && layoutListView.currentIndex < root.kbToggleModelArr.length) {
                    root.setKbOptions = root.kbToggleModelArr[layoutListView.currentIndex].val;
                }
            }
            function scrollTo(y) {
                let maxY = Math.max(0, generalFlickable.contentHeight - generalFlickable.height);
                generalFlickable.contentY = Math.max(0, Math.min(y - root.s(40), maxY > 0 ? maxY : y));
            }
            function scrollToBox(approxItemY) {
                let viewH = generalFlickable.height;
                let itemTop = approxItemY;
                let itemBottom = approxItemY + root.s(80);
                let curY = generalFlickable.contentY;
                let maxY = Math.max(0, generalFlickable.contentHeight - viewH);
                if (itemTop < curY + root.s(10)) {
                    generalFlickable.contentY = Math.max(0, itemTop - root.s(20));
                } else if (itemBottom > curY + viewH - root.s(10)) {
                    generalFlickable.contentY = Math.min(maxY, itemBottom - viewH + root.s(20));
                }
            }

            Flickable {
                id: generalFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: settingsMainCol.implicitHeight + root.s(100)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.clearHighlight()
                    z: -1
                }

                ColumnLayout {
                    id: settingsMainCol
                    width: parent.width
                    spacing: root.s(10)

                    // ── Box 0: Guide on startup ──────────────────────────────
                    Rectangle {
                        id: box0
                        Layout.fillWidth: true
                        Layout.preferredHeight: guideRow.implicitHeight + root.s(28)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 0
                        color: isActive ? root.peach : root.surface0
                        border.color: isActive ? root.peach : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 0; z: -1 }

                        RowLayout {
                            id: guideRow
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(16)
                            spacing: root.s(14)
                            Item {
                                Layout.preferredWidth: root.s(22)
                                Layout.alignment: Qt.AlignVCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰑊"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(18)
                                    color: box0.isActive ? root.base : root.peach
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(3)
                                Text {
                                    text: "Guide on startup"
                                    font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                                    color: box0.isActive ? root.base : root.text
                                    Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                                Text {
                                    text: "Launch on login"
                                    font.family: "Inter"; font.pixelSize: root.s(11)
                                    color: box0.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7)
                                    Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                            }
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                Layout.preferredWidth: root.s(40)
                                Layout.preferredHeight: root.s(22)
                                radius: root.s(11)
                                scale: toggle1Ma.containsMouse ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                color: root.setOpenGuideAtStartup
                                    ? (box0.isActive ? root.base : root.peach)
                                    : Qt.alpha(root.surface2, box0.isActive ? 0.4 : 1.0)
                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                Rectangle {
                                    width: root.s(16); height: root.s(16); radius: root.s(8)
                                    color: root.setOpenGuideAtStartup
                                        ? (box0.isActive ? root.peach : root.base)
                                        : (box0.isActive ? root.peach : root.surface0)
                                    y: root.s(3); x: root.setOpenGuideAtStartup ? root.s(21) : root.s(3)
                                    Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                                MouseArea { id: toggle1Ma; anchors.fill: parent; hoverEnabled: true; onClicked: root.setOpenGuideAtStartup = !root.setOpenGuideAtStartup; cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }

                    // ── Box 1: Help icon ─────────────────────────────────────
                    Rectangle {
                        id: box1
                        Layout.fillWidth: true
                        Layout.preferredHeight: helpIconRow.implicitHeight + root.s(28)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 1
                        color: isActive ? root.blue : root.surface0
                        border.color: isActive ? root.blue : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 1; z: -1 }

                        RowLayout {
                            id: helpIconRow
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(16)
                            spacing: root.s(14)
                            Item {
                                Layout.preferredWidth: root.s(22)
                                Layout.alignment: Qt.AlignVCenter
                                Text {
                                    anchors.centerIn: parent; text: "󰋖"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18)
                                    color: box1.isActive ? root.base : root.blue
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: root.s(3)
                                Text {
                                    text: "Help icon"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                                    color: box1.isActive ? root.base : root.text; Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                                Text {
                                    text: "Show button in topbar"; font.family: "Inter"; font.pixelSize: root.s(11)
                                    color: box1.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                            }
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                Layout.preferredWidth: root.s(40); Layout.preferredHeight: root.s(22); radius: root.s(11)
                                scale: toggle2Ma.containsMouse ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                color: root.setTopbarHelpIcon
                                    ? (box1.isActive ? root.base : root.blue)
                                    : Qt.alpha(root.surface2, box1.isActive ? 0.4 : 1.0)
                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                Rectangle {
                                    width: root.s(16); height: root.s(16); radius: root.s(8)
                                    color: root.setTopbarHelpIcon
                                        ? (box1.isActive ? root.blue : root.base)
                                        : (box1.isActive ? root.blue : root.surface0)
                                    y: root.s(3); x: root.setTopbarHelpIcon ? root.s(21) : root.s(3)
                                    Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                                MouseArea { id: toggle2Ma; anchors.fill: parent; hoverEnabled: true; onClicked: root.setTopbarHelpIcon = !root.setTopbarHelpIcon; cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }

                    // ── Box 2: UI Scale ──────────────────────────────────────
                    // FIX 1: Changed color from pink to sapphire
                    Rectangle {
                        id: box2
                        Layout.fillWidth: true
                        Layout.preferredHeight: col2.implicitHeight + root.s(32)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 2
                        color: isActive ? root.sapphire : root.surface0
                        border.color: isActive ? root.sapphire : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 2; z: -1 }

                        ColumnLayout {
                            id: col2
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            RowLayout {
                                Layout.fillWidth: true; spacing: root.s(14)
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        anchors.centerIn: parent; text: "󰁦"
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18)
                                        color: box2.isActive ? root.base : root.sapphire
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: root.s(3)
                                    Text {
                                        text: "UI Scale"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                                        color: box2.isActive ? root.base : root.text; Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Text {
                                        text: "Base size scalar"; font.family: "Inter"; font.pixelSize: root.s(11)
                                        color: box2.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                RowLayout {
                                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight; spacing: root.s(10)
                                    Rectangle {
                                        width: root.s(28); height: root.s(28); radius: root.s(6)
                                        color: sMinusMa.pressed
                                            ? Qt.alpha(root.base, 0.3)
                                            : (sMinusMa.containsMouse
                                                ? Qt.alpha(root.base, 0.2)
                                                : Qt.alpha(root.base, 0.15))
                                        scale: sMinusMa.pressed ? 0.90 : (sMinusMa.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent; text: "-"
                                            font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: root.s(15)
                                            color: box2.isActive ? root.base : root.sapphire
                                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                        }
                                        MouseArea { id: sMinusMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setUiScale = Math.max(0.5, (root.setUiScale - 0.1).toFixed(1)) }
                                    }
                                    Text { 
                                        text: root.setUiScale.toFixed(1) + "x"
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13)
                                        color: box2.isActive ? root.base : root.sapphire
                                        Layout.minimumWidth: root.s(36); horizontalAlignment: Text.AlignHCenter
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Rectangle {
                                        width: root.s(28); height: root.s(28); radius: root.s(6)
                                        color: sPlusMa.pressed
                                            ? Qt.alpha(root.base, 0.3)
                                            : (sPlusMa.containsMouse ? Qt.alpha(root.base, 0.2) : Qt.alpha(root.base, 0.15))
                                        scale: sPlusMa.pressed ? 0.90 : (sPlusMa.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent; text: "+"
                                            font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: root.s(15)
                                            color: box2.isActive ? root.base : root.sapphire
                                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                        }
                                        MouseArea { id: sPlusMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setUiScale = Math.min(2.0, (root.setUiScale + 0.1).toFixed(1)) }
                                    }
                                }
                            }
                        }
                    }

                    // ── Box 3: Keyboard layouts ──────────────────────────────
                    Rectangle {
                        id: box3
                        Layout.fillWidth: true
                        Layout.preferredHeight: col3lang.implicitHeight + root.s(32)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 3
                        color: isActive ? root.green : root.surface0
                        border.color: isActive ? root.green : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 3; z: -1 }

                        ColumnLayout {
                            id: col3lang
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            spacing: root.s(16)
                            RowLayout {
                                Layout.fillWidth: true; spacing: root.s(14)
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.alignment: Qt.AlignTop; Layout.topMargin: root.s(2)
                                    Text {
                                        anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                                        text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18)
                                        color: box3.isActive ? root.base : root.green
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: root.s(3)
                                    Text {
                                        text: "Keyboard layouts"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                                        color: box3.isActive ? root.base : root.text; Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Text {
                                        text: "Matches hyprland.conf. Click ✖ to remove."; font.family: "Inter"; font.pixelSize: root.s(11)
                                        color: box3.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Flow {
                                        Layout.fillWidth: true; spacing: root.s(6); Layout.topMargin: root.s(8)
                                        Repeater {
                                            model: root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : []
                                            Rectangle {
                                                width: langChipLayout.implicitWidth + root.s(20); height: root.s(26); radius: root.s(13)
                                                color: box3.isActive ? Qt.alpha(root.base, 0.2) : root.surface1
                                                border.color: chipMa.containsMouse ? root.red : (box3.isActive ? Qt.alpha(root.base, 0.4) : "transparent")
                                                border.width: chipMa.containsMouse ? 1 : 0
                                                scale: chipMa.containsMouse ? 1.05 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                RowLayout {
                                                    id: langChipLayout; anchors.centerIn: parent; spacing: root.s(6)
                                                    Text {
                                                        text: modelData; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: root.s(11)
                                                        color: chipMa.containsMouse ? root.red : (box3.isActive ? root.base : root.text)
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                    Text {
                                                        text: "✖"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                                        color: chipMa.containsMouse ? root.red : (box3.isActive ? Qt.alpha(root.base, 0.6) : root.subtext0)
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                }
                                                MouseArea {
                                                    id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        let arr = root.setLanguage.split(",").filter(x => x.trim() !== "");
                                                        arr.splice(index, 1);
                                                        root.setLanguage = arr.join(",");
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            // FIX 4: Language search input - colors adapt when box3 is active
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: root.s(34); Layout.topMargin: root.s(8)
                                radius: root.s(7)
                                color: box3.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                                border.color: langInput.activeFocus
                                    ? (box3.isActive ? root.base : root.green)
                                    : (box3.isActive ? Qt.alpha(root.base, 0.3) : root.surface2)
                                border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                TextInput {
                                    id: langInput
                                    anchors.fill: parent; anchors.margins: root.s(9)
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                    color: box3.isActive ? root.base : root.text; clip: true; selectByMouse: true
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    Keys.onPressed: (event) => {
                                        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                                            if (langSearchModel.count > 0) { langListView.incrementCurrentIndex(); event.accepted = true; }
                                        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                                            if (langSearchModel.count > 0) { langListView.decrementCurrentIndex(); event.accepted = true; }
                                        }
                                    }
                                    Keys.onReturnPressed: (event) => langInputAccept(event)
                                    Keys.onEnterPressed: (event) => langInputAccept(event)
                                    function langInputAccept(event) {
                                        if (langSearchModel.count > 0 && langListView.currentIndex >= 0) {
                                            let item = langSearchModel.get(langListView.currentIndex);
                                            let arr = root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : [];
                                            if (!arr.includes(item.code)) { arr.push(item.code); root.setLanguage = arr.join(","); }
                                        }
                                        text = ""; focus = false; event.accepted = true;
                                    }
                                    onActiveFocusChanged: { if (activeFocus) root.updateLangSearch(text); }
                                    onTextChanged: { root.updateLangSearch(text); }
                                    Text {
                                        text: "Search to add..."
                                        color: box3.isActive ? Qt.alpha(root.base, 0.5) : Qt.alpha(root.subtext0, 0.7)
                                        visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                            }
                            // FIX 4: Language dropdown list - colors adapt when box3 is active
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: langInput.activeFocus && langSearchModel.count > 0 ? Math.min(root.s(160), langSearchModel.count * root.s(30) + root.s(8)) : 0
                                radius: root.s(7)
                                color: box3.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                                border.color: box3.isActive ? Qt.alpha(root.base, 0.3) : root.surface1
                                border.width: 1
                                clip: true
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                ListView {
                                    id: langListView
                                    anchors.fill: parent; anchors.topMargin: root.s(4); anchors.bottomMargin: root.s(4)
                                    model: langSearchModel; interactive: true
                                    opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                    ScrollBar.vertical: ScrollBar { active: true; policy: ScrollBar.AsNeeded }
                                    delegate: Rectangle {
                                        width: parent.width - root.s(8); height: root.s(30)
                                        anchors.horizontalCenter: parent.horizontalCenter; radius: root.s(4)
                                        property bool isHovered: sMa.containsMouse
                                        color: isHovered
                                            ? Qt.alpha(box3.isActive ? root.base : root.green, 0.2)
                                            : (ListView.isCurrentItem ? Qt.alpha(box3.isActive ? root.base : root.green, 0.1) : "transparent")
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: root.s(8); anchors.rightMargin: root.s(8); spacing: root.s(8)
                                            Text { text: model.code; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: box3.isActive ? root.base : root.text; Behavior on color { ColorAnimation { duration: 150 } } }
                                            Text { text: model.name; font.family: "Inter"; font.pixelSize: root.s(11); color: box3.isActive ? Qt.alpha(root.base, 0.7) : Qt.alpha(root.subtext0, 0.7); elide: Text.ElideRight; Layout.fillWidth: true; Behavior on color { ColorAnimation { duration: 150 } } }
                                        }
                                        MouseArea {
                                            id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                let arr = root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : [];
                                                if (!arr.includes(model.code)) { arr.push(model.code); root.setLanguage = arr.join(","); }
                                                langInput.text = ""; langInput.focus = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }                       
                    }

                    // ── Box 4: Layout shortcut ───────────────────────────────
                    Rectangle {
                        id: box4
                        Layout.fillWidth: true
                        Layout.preferredHeight: col4layout.implicitHeight + root.s(32)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 4
                        color: isActive ? root.teal : root.surface0
                        border.color: isActive ? root.teal : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 4; z: -1 }

                        ColumnLayout {
                            id: col4layout
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            spacing: root.s(16)
                            RowLayout {
                                Layout.fillWidth: true; spacing: root.s(14)
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.alignment: Qt.AlignTop; Layout.topMargin: root.s(2)
                                    Text {
                                        anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                                        text: "󰯍"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18)
                                        color: box4.isActive ? root.base : root.teal
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: root.s(3)
                                    Text {
                                        text: "Layout shortcut"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                                        color: box4.isActive ? root.base : root.text; Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Text {
                                        text: "Toggle combination"; font.family: "Inter"; font.pixelSize: root.s(11)
                                        color: box4.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    // FIX 4: Dropdown button colors adapt when box4 is active
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(34); Layout.topMargin: root.s(8)
                                        radius: root.s(7)
                                        color: box4.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                                        border.color: root.isLayoutDropdownOpen
                                            ? (box4.isActive ? root.base : root.teal)
                                            : (box4.isActive ? Qt.alpha(root.base, 0.3) : root.surface2)
                                        border.width: 1
                                        Behavior on border.color { ColorAnimation { duration: 200 } }
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                        RowLayout {
                                            anchors.fill: parent; anchors.margins: root.s(9)
                                            Text {
                                                text: root.getKbToggleLabel(root.setKbOptions)
                                                font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                                color: box4.isActive ? root.base : root.text; Layout.fillWidth: true
                                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                            }
                                            Text {
                                                text: root.isLayoutDropdownOpen ? "▴" : "▾"; font.pixelSize: root.s(12)
                                                color: box4.isActive ? Qt.alpha(root.base, 0.7) : root.subtext0
                                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.isLayoutDropdownOpen = !root.isLayoutDropdownOpen;
                                                if (root.isLayoutDropdownOpen) {
                                                    let idx = root.kbToggleModelArr.findIndex(x => x.val === root.setKbOptions);
                                                    layoutListView.currentIndex = Math.max(0, idx);
                                                }
                                                root.forceActiveFocus();
                                            }
                                        }
                                    }
                                    // FIX 4: Layout dropdown list colors adapt when box4 is active
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.isLayoutDropdownOpen ? root.kbToggleModelArr.length * root.s(30) + root.s(8) : 0
                                        radius: root.s(7)
                                        color: box4.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                                        border.color: box4.isActive ? Qt.alpha(root.base, 0.3) : root.surface1
                                        border.width: 1
                                        clip: true
                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                        ListView {
                                            id: layoutListView
                                            anchors.fill: parent; anchors.topMargin: root.s(4); anchors.bottomMargin: root.s(4)
                                            model: root.kbToggleModelArr; interactive: false
                                            opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 200 } }
                                            delegate: Rectangle {
                                                width: parent.width - root.s(8); height: root.s(30)
                                                anchors.horizontalCenter: parent.horizontalCenter; radius: root.s(4)
                                                property bool isHovered: toggleMa.containsMouse
                                                color: isHovered
                                                    ? Qt.alpha(box4.isActive ? root.base : root.teal, 0.2)
                                                    : (ListView.isCurrentItem ? Qt.alpha(box4.isActive ? root.base : root.teal, 0.1) : "transparent")
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: root.s(8); anchors.rightMargin: root.s(8)
                                                    Text {
                                                        text: modelData.label; font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                                        color: root.setKbOptions === modelData.val
                                                            ? (box4.isActive ? root.base : root.teal)
                                                            : (box4.isActive ? Qt.alpha(root.base, 0.8) : root.text)
                                                        Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                }
                                                MouseArea { id: toggleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.setKbOptions = modelData.val; root.isLayoutDropdownOpen = false; } }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Box 5: Wallpaper directory ───────────────────────────
                    Rectangle {
                        id: box5
                        Layout.fillWidth: true
                        Layout.preferredHeight: col5wp.implicitHeight + root.s(32)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 5
                        color: isActive ? root.mauve : root.surface0
                        border.color: isActive ? root.mauve : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 5; z: -1 }

                        ColumnLayout {
                            id: col5wp
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            RowLayout {
                                Layout.fillWidth: true; spacing: root.s(14)
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.alignment: Qt.AlignTop; Layout.topMargin: root.s(2)
                                    Text {
                                        anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                                        text: "󰋩"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18)
                                        color: box5.isActive ? root.base : root.mauve
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: root.s(3)
                                    Text {
                                        text: "Wallpaper directory"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                                        color: box5.isActive ? root.base : root.text; Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Text {
                                        text: "Absolute source path"; font.family: "Inter"; font.pixelSize: root.s(11)
                                        color: box5.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(34); Layout.topMargin: root.s(8)
                                        radius: root.s(7)
                                        color: box5.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                                        border.color: wpDirInput.activeFocus
                                            ? (box5.isActive ? root.base : root.mauve)
                                            : (box5.isActive ? Qt.alpha(root.base, 0.3) : root.surface2)
                                        border.width: 1
                                        Behavior on border.color { ColorAnimation { duration: 200 } }
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                        TextInput {
                                            id: wpDirInput
                                            anchors.fill: parent; anchors.margins: root.s(9)
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: root.setWallpaperDir
                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                            color: box5.isActive ? root.base : root.text; clip: true; selectByMouse: true
                                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                            Keys.onPressed: (event) => {
                                                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                                                    if (pathSuggestModel.count > 0) { wpSuggestListView.incrementCurrentIndex(); event.accepted = true; }
                                                } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                                                    if (pathSuggestModel.count > 0) { wpSuggestListView.decrementCurrentIndex(); event.accepted = true; }
                                                }
                                            }
                                            Keys.onReturnPressed: (event) => wpDirInputAccept(event)
                                            Keys.onEnterPressed: (event) => wpDirInputAccept(event)
                                            function wpDirInputAccept(event) {
                                                if (pathSuggestModel.count > 0 && wpSuggestListView.currentIndex >= 0) {
                                                    let item = pathSuggestModel.get(wpSuggestListView.currentIndex);
                                                    if (item) { text = item.path; root.setWallpaperDir = text; }
                                                }
                                                pathSuggestModel.clear(); focus = false; event.accepted = true;
                                            }
                                            onActiveFocusChanged: {
                                                if (activeFocus) { pathSuggestProc.query = text; pathSuggestProc.running = false; pathSuggestProc.running = true; }
                                            }
                                            onTextChanged: {
                                                root.setWallpaperDir = text;
                                                if (activeFocus) { pathSuggestProc.query = text; pathSuggestProc.running = false; pathSuggestProc.running = true; }
                                            }
                                            Text {
                                                text: "Enter directory..."; color: box5.isActive ? Qt.alpha(root.base, 0.5) : root.subtext0
                                                visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                    // FIX 4: Wallpaper dir suggestion list colors adapt when box5 is active
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: wpDirInput.activeFocus && pathSuggestModel.count > 0 ? pathSuggestModel.count * root.s(28) + root.s(8) : 0
                                        radius: root.s(7)
                                        color: box5.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                                        border.color: box5.isActive ? Qt.alpha(root.base, 0.3) : root.surface1
                                        border.width: 1
                                        clip: true
                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                        ListView {
                                            id: wpSuggestListView
                                            anchors.fill: parent; anchors.topMargin: root.s(4); anchors.bottomMargin: root.s(4)
                                            model: pathSuggestModel; interactive: false
                                            opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 200 } }
                                            delegate: Rectangle {
                                                width: parent.width - root.s(8); height: root.s(28)
                                                anchors.horizontalCenter: parent.horizontalCenter; radius: root.s(4)
                                                property bool isHovered: suggestMa.containsMouse
                                                color: isHovered
                                                    ? Qt.alpha(box5.isActive ? root.base : root.mauve, 0.2)
                                                    : (ListView.isCurrentItem ? Qt.alpha(box5.isActive ? root.base : root.mauve, 0.1) : "transparent")
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter; x: root.s(8)
                                                    text: model.path; font.family: "JetBrains Mono"; font.pixelSize: root.s(10)
                                                    color: box5.isActive ? root.base : root.text
                                                    elide: Text.ElideMiddle; width: parent.width - root.s(16)
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                MouseArea { id: suggestMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { wpDirInput.text = model.path; pathSuggestModel.clear(); wpDirInput.focus = false; } }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Box 6: Workspaces ────────────────────────────────────
                    Rectangle {
                        id: box6
                        Layout.fillWidth: true
                        Layout.preferredHeight: col6ws.implicitHeight + root.s(32)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 6
                        color: isActive ? root.red : root.surface0
                        border.color: isActive ? root.red : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 6; z: -1 }

                        ColumnLayout {
                            id: col6ws
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            RowLayout {
                                Layout.fillWidth: true; spacing: root.s(14)
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        anchors.centerIn: parent; text: "󰽿"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18)
                                        color: box6.isActive ? root.base : root.red
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: root.s(3)
                                    Text {
                                        text: "Workspaces"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(14)
                                        color: box6.isActive ? root.base : root.text; Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Text {
                                        text: "Static count in topbar"; font.family: "Inter"; font.pixelSize: root.s(11)
                                        color: box6.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                RowLayout {
                                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight; spacing: root.s(10)
                                    Rectangle {
                                        width: root.s(28); height: root.s(28); radius: root.s(6)
                                        color: wsMinusMa.pressed ? Qt.alpha(root.base, 0.3) : (wsMinusMa.containsMouse ? Qt.alpha(root.base, 0.2) : Qt.alpha(root.base, 0.15))
                                        scale: wsMinusMa.pressed ? 0.90 : (wsMinusMa.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent; text: "-"
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(15)
                                            color: box6.isActive ? root.base : root.red
                                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                        }
                                        MouseArea { id: wsMinusMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setWorkspaceCount = Math.max(2, root.setWorkspaceCount - 1) }
                                    }
                                    Text { 
                                        text: root.setWorkspaceCount.toString()
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14)
                                        color: box6.isActive ? root.base : root.red
                                        Layout.minimumWidth: root.s(36); horizontalAlignment: Text.AlignHCenter
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Rectangle {
                                        width: root.s(28); height: root.s(28); radius: root.s(6)
                                        color: wsPlusMa.pressed ? Qt.alpha(root.base, 0.3) : (wsPlusMa.containsMouse ? Qt.alpha(root.base, 0.2) : Qt.alpha(root.base, 0.15))
                                        scale: wsPlusMa.pressed ? 0.90 : (wsPlusMa.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent; text: "+"
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(15)
                                            color: box6.isActive ? root.base : root.red
                                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                        }
                                        MouseArea { id: wsPlusMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setWorkspaceCount = Math.min(10, root.setWorkspaceCount + 1) }
                                    }
                                }
                            }
                        }
                    }
                }
	    }        
        }
    }

    Component {
        id: weatherTabComponent
        Item {
            id: weatherTabRoot

            function focusApiKey() { apiKeyInput.forceActiveFocus(); }
            function focusCityId() { cityIdInput.forceActiveFocus(); }
            function scrollTo(y) {
                let maxY = Math.max(0, weatherFlickable.contentHeight - weatherFlickable.height);
                weatherFlickable.contentY = Math.max(0, Math.min(y - root.s(40), maxY > 0 ? maxY : y));
            }
            function scrollToBox(approxItemY) {
                let viewH = weatherFlickable.height;
                let itemTop = approxItemY;
                let itemBottom = approxItemY + root.s(80);
                let curY = weatherFlickable.contentY;
                let maxY = Math.max(0, weatherFlickable.contentHeight - viewH);
                if (itemTop < curY + root.s(10)) {
                    weatherFlickable.contentY = Math.max(0, itemTop - root.s(20));
                } else if (itemBottom > curY + viewH - root.s(10)) {
                    weatherFlickable.contentY = Math.min(maxY, itemBottom - viewH + root.s(20));
                }
            }

            Component.onCompleted: {
                apiKeyInput.text = root._apiKeyText;
                cityIdInput.text = root._cityIdText;
            }

            Connections {
                target: root
                function on_ApiKeyTextChanged() { if (apiKeyInput.text !== root._apiKeyText) apiKeyInput.text = root._apiKeyText; }
                function on_CityIdTextChanged() { if (cityIdInput.text !== root._cityIdText) cityIdInput.text = root._cityIdText; }
            }

            Flickable {
                id: weatherFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: wCol.implicitHeight + root.s(100)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                MouseArea { anchors.fill: parent; onClicked: root.clearHighlight(); z: -1 }

                ColumnLayout {
                    id: wCol
                    width: parent.width
                    spacing: root.s(10)

                    // ── Box 0: Instructions ──────────────────────────────────
                    Rectangle {
                        id: wBox0
                        Layout.fillWidth: true
                        Layout.preferredHeight: instructionLayout.implicitHeight + root.s(28)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 0
                        color: isActive ? root.blue : root.surface0
                        border.color: isActive ? root.blue : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                        clip: true

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 0; z: -1 }

                        ColumnLayout {
                            id: instructionLayout
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(14)
                            spacing: root.s(10)
                            Text {
                                text: "Weather Widget Setup"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(15)
                                color: wBox0.isActive ? root.base : root.text; Layout.bottomMargin: root.s(2)
                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                            }
                            RowLayout {
                                spacing: root.s(10)
                                Rectangle {
                                    width: root.s(22); height: root.s(22); radius: root.s(11)
                                    color: wBox0.isActive ? Qt.alpha(root.base, 0.25) : Qt.alpha(root.blue, 0.2)
                                    border.color: wBox0.isActive ? Qt.alpha(root.base, 0.5) : root.blue; border.width: 1
                                    Behavior on color { ColorAnimation { duration: 220 } }
                                    Text { anchors.centerIn: parent; text: "1"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: wBox0.isActive ? root.base : root.blue; Behavior on color { ColorAnimation { duration: 220 } } }
                                }
                                Text {
                                    text: "Get an API Key"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(13)
                                    color: wBox0.isActive ? root.base : root.text; Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                            }
                            RowLayout {
                                spacing: root.s(10); Layout.fillWidth: true
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.fillHeight: true
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: parent.height + root.s(10)
                                        color: wBox0.isActive ? Qt.alpha(root.base, 0.3) : root.surface2
                                        Behavior on color { ColorAnimation { duration: 220 } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: root.s(6); Layout.topMargin: root.s(2); Layout.bottomMargin: root.s(2)
                                    // FIX 4: Step items inside instructions adapt color when wBox0 is active
                                    Repeater {
                                        model: ["Go to openweathermap.org & create an account.", "Navigate to profile -> 'My API keys'.", "Generate a new key and paste it below."]
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: root.s(30)
                                            radius: root.s(6)
                                            color: wBox0.isActive ? Qt.alpha(root.base, 0.12) : root.surface0
                                            border.color: wBox0.isActive ? Qt.alpha(root.base, 0.2) : root.surface1; border.width: 1
                                            Behavior on color { ColorAnimation { duration: 220 } }
                                            Behavior on border.color { ColorAnimation { duration: 220 } }
                                            RowLayout { anchors.fill: parent; anchors.margins: root.s(7); spacing: root.s(7)
                                                Text { text: "󰄾"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(12); color: wBox0.isActive ? Qt.alpha(root.base, 0.6) : root.overlay0; Behavior on color { ColorAnimation { duration: 220 } } }
                                                Text { text: modelData; font.family: "Inter"; font.pixelSize: root.s(11); color: wBox0.isActive ? Qt.alpha(root.base, 0.85) : root.subtext1; Layout.fillWidth: true; Behavior on color { ColorAnimation { duration: 220 } } }
                                            }
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                spacing: root.s(10)
                                Rectangle {
                                    width: root.s(22); height: root.s(22); radius: root.s(11)
                                    color: wBox0.isActive ? Qt.alpha(root.base, 0.25) : Qt.alpha(root.peach, 0.2)
                                    border.color: wBox0.isActive ? Qt.alpha(root.base, 0.5) : root.peach; border.width: 1
                                    Behavior on color { ColorAnimation { duration: 220 } }
                                    Text { anchors.centerIn: parent; text: "2"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: wBox0.isActive ? root.base : root.peach; Behavior on color { ColorAnimation { duration: 220 } } }
                                }
                                Text {
                                    text: "Find your City ID"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(13)
                                    color: wBox0.isActive ? root.base : root.text; Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                }
                            }
                            RowLayout {
                                spacing: root.s(10); Layout.fillWidth: true
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.fillHeight: true
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: parent.height - root.s(10); anchors.top: parent.top
                                        color: wBox0.isActive ? Qt.alpha(root.base, 0.3) : root.surface2
                                        Behavior on color { ColorAnimation { duration: 220 } }
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: wBox0.isActive ? Qt.alpha(root.base, 0.3) : root.surface2 }
                                            GradientStop { position: 1.0; color: "transparent" }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: root.s(6); Layout.topMargin: root.s(2); Layout.bottomMargin: root.s(2)
                                    // FIX 4: Step items for city ID section also adapt color
                                    Repeater {
                                        model: ["Search for your city on openweathermap.org.", "Look at the URL (e.g. .../city/2643743).", "Copy the number at the end and paste below."]
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: root.s(30)
                                            radius: root.s(6)
                                            color: wBox0.isActive ? Qt.alpha(root.base, 0.12) : root.surface0
                                            border.color: wBox0.isActive ? Qt.alpha(root.base, 0.2) : root.surface1; border.width: 1
                                            Behavior on color { ColorAnimation { duration: 220 } }
                                            Behavior on border.color { ColorAnimation { duration: 220 } }
                                            RowLayout { anchors.fill: parent; anchors.margins: root.s(7); spacing: root.s(7)
                                                Text { text: "󰄾"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(12); color: wBox0.isActive ? Qt.alpha(root.base, 0.6) : root.overlay0; Behavior on color { ColorAnimation { duration: 220 } } }
                                                Text { text: modelData; font.family: "Inter"; font.pixelSize: root.s(11); color: wBox0.isActive ? Qt.alpha(root.base, 0.85) : root.subtext1; Layout.fillWidth: true; Behavior on color { ColorAnimation { duration: 220 } } }
                                            }
                                        }
                                    }
                                }
                            }
                            Text {
                                text: "* Note: New API keys may take a few hours to activate."; font.family: "Inter"; font.pixelSize: root.s(10)
                                color: wBox0.isActive ? Qt.alpha(root.base, 0.7) : root.yellow; font.italic: true; Layout.topMargin: root.s(2)
                                Behavior on color { ColorAnimation { duration: 220 } }
                            }
                        }
                    }

                    // ── Box 1: API Key ───────────────────────────────────────
                    Rectangle {
                        id: wBox1
                        Layout.fillWidth: true
                        Layout.preferredHeight: apiKeyRow.implicitHeight + root.s(28)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 1
                        color: isActive ? root.blue : root.surface0
                        border.color: isActive ? root.blue : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 1; z: -1 }

                        ColumnLayout {
                            id: apiKeyRow
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            spacing: root.s(10)
                            RowLayout {
                                Layout.fillWidth: true; spacing: root.s(14)
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        anchors.centerIn: parent; text: "󰌆"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18)
                                        color: wBox1.isActive ? root.base : root.blue
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: root.s(3)
                                    Text {
                                        text: "API Key"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                                        color: wBox1.isActive ? root.base : root.text; Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Text {
                                        text: "OpenWeather API key"; font.family: "Inter"; font.pixelSize: root.s(11)
                                        color: wBox1.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: root.s(42)
                                radius: root.s(7)
                                color: wBox1.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                                border.color: apiKeyInput.activeFocus
                                    ? (wBox1.isActive ? root.base : root.blue)
                                    : (wBox1.isActive ? Qt.alpha(root.base, 0.3) : root.surface2)
                                border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: root.s(10); spacing: root.s(10)
                                    Text {
                                        text: "󰌆"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16)
                                        color: wBox1.isActive ? Qt.alpha(root.base, 0.6) : root.subtext0
                                        Behavior on color { ColorAnimation { duration: 220 } }
                                    }
                                    TextInput { 
                                        id: apiKeyInput
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: "JetBrains Mono"; font.pixelSize: root.s(12)
                                        color: wBox1.isActive ? root.base : root.text; clip: true; selectByMouse: true
                                        echoMode: root.apiKeyVisible ? TextInput.Normal : TextInput.Password
                                        passwordCharacter: "•"
                                        onTextChanged: root._apiKeyText = text
                                        Behavior on color { ColorAnimation { duration: 220 } }
                                        Text {
                                            text: "Enter API Key..."; color: wBox1.isActive ? Qt.alpha(root.base, 0.5) : root.subtext0
                                            visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                            Behavior on color { ColorAnimation { duration: 220 } }
                                        }
                                    }
                                    Rectangle {
                                        width: root.s(24); height: root.s(24); radius: root.s(4); color: "transparent"
                                        Text {
                                            anchors.centerIn: parent; text: root.apiKeyVisible ? "󰈈" : "󰈉"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16)
                                            color: eyeMa.containsMouse
                                                ? (wBox1.isActive ? root.base : root.blue)
                                                : (wBox1.isActive ? Qt.alpha(root.base, 0.6) : root.subtext0)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        MouseArea { id: eyeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.apiKeyVisible = !root.apiKeyVisible }
                                    }
                                }
                            }
                        }
                    }

                    // ── Box 2: City ID ───────────────────────────────────────
                    Rectangle {
                        id: wBox2
                        Layout.fillWidth: true
                        Layout.preferredHeight: cityIdRow.implicitHeight + root.s(28)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 2
                        color: isActive ? root.blue : root.surface0
                        border.color: isActive ? root.blue : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 2; z: -1 }

                        ColumnLayout {
                            id: cityIdRow
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            spacing: root.s(10)
                            RowLayout {
                                Layout.fillWidth: true; spacing: root.s(14)
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        anchors.centerIn: parent; text: "󰖐"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18)
                                        color: wBox2.isActive ? root.base : root.blue
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: root.s(3)
                                    Text {
                                        text: "City ID"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                                        color: wBox2.isActive ? root.base : root.text; Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Text {
                                        text: "OpenWeather city ID"; font.family: "Inter"; font.pixelSize: root.s(11)
                                        color: wBox2.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: root.s(42)
                                radius: root.s(7)
                                color: wBox2.isActive ? Qt.alpha(root.base, 0.15) : root.surface0
                                border.color: cityIdInput.activeFocus
                                    ? (wBox2.isActive ? root.base : root.blue)
                                    : (wBox2.isActive ? Qt.alpha(root.base, 0.3) : root.surface2)
                                border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                TextInput {
                                    id: cityIdInput
                                    anchors.fill: parent; anchors.margins: root.s(10)
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(12)
                                    color: wBox2.isActive ? root.base : root.text; clip: true; selectByMouse: true
                                    onTextChanged: root._cityIdText = text
                                    Behavior on color { ColorAnimation { duration: 220 } }
                                    Text {
                                        text: "City ID (e.g. 2624652)"; color: wBox2.isActive ? Qt.alpha(root.base, 0.5) : root.subtext0
                                        visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 220 } }
                                    }
                                }
                            }
                        }
                    }

                    // ── Box 3: Temperature Unit ──────────────────────────────
                    Rectangle {
                        id: wBox3
                        Layout.fillWidth: true
                        Layout.preferredHeight: unitRow.implicitHeight + root.s(28)
                        radius: root.s(12)

                        property bool isActive: root.highlightedBox === 3
                        color: isActive ? root.blue : root.surface0
                        border.color: isActive ? root.blue : root.surface1
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        MouseArea { anchors.fill: parent; onClicked: root.highlightedBox = 3; z: -1 }

                        ColumnLayout {
                            id: unitRow
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            spacing: root.s(10)
                            RowLayout {
                                Layout.fillWidth: true; spacing: root.s(14)
                                Item {
                                    Layout.preferredWidth: root.s(22); Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        anchors.centerIn: parent; text: "°C"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18)
                                        color: wBox3.isActive ? root.base : root.blue
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: root.s(3)
                                    Text {
                                        text: "Temperature Unit"; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(14)
                                        color: wBox3.isActive ? root.base : root.text; Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                    Text {
                                        text: "Celsius / Fahrenheit / Kelvin"; font.family: "Inter"; font.pixelSize: root.s(11)
                                        color: wBox3.isActive ? Qt.alpha(root.base, 0.75) : Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: root.s(8)
                                Repeater {
                                    model: [{ val: "metric", label: "Celsius" }, { val: "imperial", label: "Fahrenheit" }, { val: "standard", label: "Kelvin" }]
                                    Rectangle {
                                        Layout.preferredWidth: root.s(88); Layout.preferredHeight: root.s(30); radius: root.s(6)
                                        property bool isSelected: root.selectedUnit === modelData.val
                                        property bool parentActive: wBox3.isActive
                                        color: isSelected
                                            ? (parentActive ? Qt.alpha(root.base, 0.25) : root.blue)
                                            : (parentActive ? Qt.alpha(root.base, 0.1) : "transparent")
                                        border.color: isSelected
                                            ? (parentActive ? Qt.alpha(root.base, 0.6) : root.blue)
                                            : (parentActive ? Qt.alpha(root.base, 0.2) : root.surface1)
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent; text: modelData.label
                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(10); font.capitalization: Font.Capitalize
                                            color: isSelected
                                                ? (parentActive ? root.base : root.base)
                                                : (parentActive ? Qt.alpha(root.base, 0.6) : root.subtext0)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedUnit = modelData.val }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    
    Component {
        id: keybindTabComponent
        Item {
            id: keybindTabRoot

            function scrollToBottom() {
                keybindFlickable.contentY = Math.max(0, keybindsColLayout.implicitHeight - keybindFlickable.height + root.s(100));
            }
            function scrollTo(y) {
                let maxY = Math.max(0, keybindFlickable.contentHeight - keybindFlickable.height);
                keybindFlickable.contentY = Math.max(0, Math.min(y - root.s(40), maxY > 0 ? maxY : y));
            }
            function scrollToBox(approxItemY) {
                let viewH = keybindFlickable.height;
                let itemTop = approxItemY;
                let itemBottom = approxItemY + root.s(56);
                let curY = keybindFlickable.contentY;
                let maxY = Math.max(0, keybindFlickable.contentHeight - viewH);
                if (itemTop < curY + root.s(10)) {
                    keybindFlickable.contentY = Math.max(0, itemTop - root.s(20));
                } else if (itemBottom > curY + viewH - root.s(10)) {
                    keybindFlickable.contentY = Math.min(maxY, itemBottom - viewH + root.s(20));
                }
            }

            Flickable {
                id: keybindFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: keybindsColLayout.implicitHeight + root.s(100)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                MouseArea { anchors.fill: parent; onClicked: root.clearHighlight(); z: -1 }

                ColumnLayout {
                    id: keybindsColLayout
                    width: parent.width
                    spacing: root.s(8)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: wsCol.implicitHeight + root.s(32)
                        radius: root.s(12)
                        color: root.surface0
                        border.color: root.surface1; border.width: 1
                        ColumnLayout {
                            id: wsCol
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: root.s(16)
                            spacing: root.s(10)
                            Text { text: "Workspaces (SUPER + 1-9)"; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: root.s(12); color: root.text; Layout.alignment: Qt.AlignVCenter }
                            Flow {
                                Layout.fillWidth: true; spacing: root.s(7)
                                Repeater {
                                    model: 9
                                    Rectangle {
                                        property int wsNum: index + 1
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: wsMa.containsMouse ? root.peach : root.surface1
                                        border.color: wsMa.containsMouse ? root.peach : "transparent"; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent; text: parent.wsNum
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                            color: wsMa.containsMouse ? root.base : root.peach
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        MouseArea { id: wsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", wsNum.toString()]) }
                                    }
                                }
                            }
                        }
                    }

                    ListView {
                        id: kbListView
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        implicitHeight: dynamicKeybindsModel.count * root.s(56) + root.s(20)
                        model: dynamicKeybindsModel
                        interactive: false
                        cacheBuffer: root.s(2000)
                        displayMarginBeginning: root.s(100)
                        displayMarginEnd: root.s(100)
                        spacing: root.s(8)

                        delegate: Rectangle {
                            id: kbRowRect
                            property int outerIndex: index // FIX 1: Store outer index to avoid shadowing inside dropdown lists
                            property bool isJumpHighlighted: root.highlightedBox === outerIndex
                            
                            // FIX 2: Layout Ready flag to prevent initial sweeping animations
                            property bool layoutReady: false
                            Component.onCompleted: Qt.callLater(() => layoutReady = true)

                            width: kbListView.width
                            height: root.s(44) + (model.isEditing ? editPanel.implicitHeight + root.s(12) : 0)
                            radius: root.s(8)

                            HoverHandler { id: rowHover }
                            property bool isHovered: rowHover.hovered || model.isEditing || isJumpHighlighted
                            property bool isTypeOpen: false
                            property bool isDispOpen: false

                            color: isJumpHighlighted ? root.surface1 : (isHovered ? root.surface1 : root.surface0)
                            border.color: isJumpHighlighted ? root.peach : (isHovered ? Qt.alpha(root.peach, 0.5) : root.surface1)
                            border.width: isJumpHighlighted ? 2 : 1

                            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }
                            Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }
                            Behavior on border.width { NumberAnimation { duration: 150 } }

                            MouseArea { anchors.fill: parent; z: -2; onClicked: root.highlightedBox = outerIndex; }

                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: root.s(10); spacing: root.s(10)

                                Item {
                                    Layout.fillWidth: true; Layout.preferredHeight: root.s(24); clip: true

                                    Row {
                                        id: modKeyContainer
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: root.s(5)
                                        Rectangle {
                                            width: k1Text.implicitWidth + root.s(10); height: root.s(24); radius: root.s(4)
                                            color: root.surface1
                                            border.color: root.surface2; border.width: 1
                                            visible: model.mods !== ""
                                            Text {
                                                id: k1Text; anchors.centerIn: parent; text: model.mods
                                                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9)
                                                color: root.peach
                                            }
                                        }
                                        Text {
                                            text: "+"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10)
                                            color: root.overlay0
                                            visible: model.mods !== "" && model.key !== ""; anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Rectangle {
                                            width: k2Text.implicitWidth + root.s(10); height: root.s(24); radius: root.s(4)
                                            color: root.surface1
                                            border.color: root.surface2; border.width: 1
                                            visible: model.key !== ""
                                            Text {
                                                id: k2Text; anchors.centerIn: parent; text: model.key
                                                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9)
                                                color: root.peach
                                            }
                                        }
                                    }

                                    // Edit button
                                    Rectangle {
                                        id: editButtonSlide
                                        width: root.s(26); height: root.s(26); radius: root.s(6)
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: kbRowRect.isHovered ? parent.width - width : parent.width
                                        color: model.isEditing
                                            ? root.peach
                                            : (editMa.containsMouse ? root.peach : root.surface2)
                                            
                                        // FIX 2: Only allow animation when layout is ready
                                        Behavior on x { 
                                            enabled: kbRowRect.layoutReady
                                            NumberAnimation { duration: 250; easing.type: Easing.OutQuart } 
                                        }
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                        
                                        Text {
                                            anchors.centerIn: parent
                                            text: model.isEditing ? "▴" : "󰏫"
                                            font.family: model.isEditing ? "Inter" : "Iosevka Nerd Font"
                                            font.pixelSize: root.s(13)
                                            color: model.isEditing
                                                ? root.base
                                                : (editMa.containsMouse ? root.base : root.subtext0)
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                        }
                                        MouseArea { 
                                            id: editMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; 
                                            onClicked: { 
                                                dynamicKeybindsModel.setProperty(outerIndex, "isEditing", !model.isEditing); 
                                                kbRowRect.isTypeOpen = false; 
                                                kbRowRect.isDispOpen = false; 
                                                if (!model.isEditing) {
                                                    root.forceActiveFocus();
                                                }
                                            } 
                                        }
                                    }
                                    Item {
                                        id: cmdClipRect
                                        anchors.left: modKeyContainer.right; anchors.leftMargin: root.s(8)
                                        anchors.right: editButtonSlide.left; anchors.rightMargin: root.s(6)
                                        anchors.verticalCenter: parent.verticalCenter; height: parent.height; clip: true

                                        property int marqueeSpacing: root.s(60)
                                        property bool shouldMarquee: kbRowRect.isHovered && cmdTextMain.implicitWidth > width

                                        // FIX 3: Restored original marquee layout structure, which aligns it right.
                                        Item {
                                            id: marqueeContainer
                                            height: parent.height
                                            width: cmdClipRect.shouldMarquee ? cmdTextMain.implicitWidth * 2 + cmdClipRect.marqueeSpacing : parent.width
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.right: cmdClipRect.shouldMarquee ? undefined : parent.right
                                            anchors.left: cmdClipRect.shouldMarquee ? parent.left : undefined

                                            Row {
                                                spacing: cmdClipRect.marqueeSpacing; anchors.verticalCenter: parent.verticalCenter
                                                anchors.right: cmdClipRect.shouldMarquee ? undefined : parent.right
                                                Text {
                                                    id: cmdTextMain; text: (model.dispatcher + " " + model.command).trim()
                                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(10)
                                                    color: root.subtext0
                                                }
                                                Text {
                                                    id: cmdTextClone; text: cmdTextMain.text; font: cmdTextMain.font; color: cmdTextMain.color
                                                    visible: cmdClipRect.shouldMarquee
                                                }
                                            }

                                            SequentialAnimation on x {
                                                id: cmdAnim; loops: Animation.Infinite
                                                running: cmdClipRect.shouldMarquee && kbRowRect.layoutReady
                                                PauseAnimation { duration: 1500 }
                                                NumberAnimation { from: 0; to: -(cmdTextMain.implicitWidth + cmdClipRect.marqueeSpacing); duration: (cmdTextMain.implicitWidth + cmdClipRect.marqueeSpacing) * 25 }
                                                PropertyAction { target: marqueeContainer; property: "x"; value: 0 }
                                            }
                                            onXChanged: { if (!cmdClipRect.shouldMarquee && x !== 0) x = 0; }
                                        }

                                        onShouldMarqueeChanged: {
                                            if (shouldMarquee) { marqueeContainer.anchors.right = undefined; marqueeContainer.anchors.left = parent.left; marqueeContainer.x = 0; cmdAnim.restart(); }
                                            else { cmdAnim.stop(); marqueeContainer.x = 0; marqueeContainer.anchors.left = undefined; marqueeContainer.anchors.right = parent.right; }
                                        }
                                    }

                                    MouseArea {
                                        id: bindMa
                                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: editButtonSlide.left
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton; enabled: !model.isEditing
                                        onClicked: {
                                            if (model.dispatcher.startsWith("exec")) { Quickshell.execDetached(["bash", "-c", model.command]); }
                                            else { Quickshell.execDetached(["hyprctl", "dispatch", model.dispatcher, model.command]); }
                                        }
                                    }
                                }

                                // ── Edit panel ───────────────────────────────
                                ColumnLayout {
                                    id: editPanel
                                    Layout.fillWidth: true; visible: model.isEditing; spacing: root.s(8); clip: true

                                    // Record shortcut
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                        radius: root.s(6)
                                        color: recordMa.pressed || captureTrap.activeFocus
                                            ? Qt.alpha(root.red, 0.12)
                                            : root.surface0
                                        border.color: recordMa.pressed || captureTrap.activeFocus
                                            ? root.red
                                            : root.surface2
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                            color: captureTrap.activeFocus ? root.red : root.text
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            text: captureTrap.activeFocus ? "Press Keys (Esc to confirm)..." : (model.mods ? model.mods + " + " : "") + (model.key || "[Click to Record Shortcut]")
                                        }
                                        MouseArea {
                                            id: recordMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: { captureTrap.accumulatedMods = []; captureTrap.accumulatedKey = ""; captureTrap.forceActiveFocus(); }
                                        }
                                        Item {
                                            id: captureTrap
                                            focus: false
                                            property var accumulatedMods: []
                                            property string accumulatedKey: ""
                                            Keys.onTabPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onBacktabPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onReturnPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onEnterPressed: (event) => { event.accepted = true; processKey(event); }
                                            Keys.onEscapePressed: (event) => { captureTrap.focus = false; event.accepted = true; }
                                            Keys.onShortcutOverride: (event) => { event.accepted = true; }
                                            Keys.onReleased: (event) => { event.accepted = true; }
                                            Keys.onPressed: (event) => { event.accepted = true; processKey(event); }
                                            function processKey(event) {
                                                if (event.key === Qt.Key_Escape) return;
                                                let newMods = [];
                                                if (event.modifiers & Qt.MetaModifier) newMods.push("$mainMod");
                                                if (event.modifiers & Qt.ControlModifier) newMods.push("CTRL");
                                                if (event.modifiers & Qt.AltModifier) newMods.push("ALT");
                                                if (event.modifiers & Qt.ShiftModifier) newMods.push("SHIFT_L");
                                                let isModifierOnly = (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R ||
                                                                      event.key === Qt.Key_Meta || event.key === Qt.Key_Control ||
                                                                      event.key === Qt.Key_Alt || event.key === Qt.Key_Shift ||
                                                                      event.key === Qt.Key_CapsLock);
                                                if (isModifierOnly) {
                                                    let mergedMods = [...captureTrap.accumulatedMods];
                                                    for (let m of newMods) { if (!mergedMods.includes(m)) mergedMods.push(m); }
                                                    dynamicKeybindsModel.setProperty(outerIndex, "mods", mergedMods.join(" "));
                                                    captureTrap.accumulatedMods = mergedMods;
                                                    return;
                                                }
                                                let k = "";
                                                if (event.key === Qt.Key_Space) k = "SPACE";
                                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) k = "RETURN";
                                                else if (event.key === Qt.Key_Tab) k = "TAB";
                                                else if (event.key === Qt.Key_Print) k = "Print";
                                                else if (event.key === Qt.Key_Left) k = "left";
                                                else if (event.key === Qt.Key_Right) k = "right";
                                                else if (event.key === Qt.Key_Up) k = "up";
                                                else if (event.key === Qt.Key_Down) k = "down";
                                                else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35) { k = "F" + (event.key - Qt.Key_F1 + 1); }
                                                else if (event.text && event.text.length > 0) k = event.text.toUpperCase();
                                                else k = event.key.toString();
                                                if (captureTrap.accumulatedKey !== "") {
                                                    let prevMods = model.mods ? model.mods.split(" ").filter(x => x !== "") : [];
                                                    if (!prevMods.includes(captureTrap.accumulatedKey)) prevMods.push(captureTrap.accumulatedKey);
                                                    for (let m of newMods) { if (!prevMods.includes(m)) prevMods.push(m); }
                                                    dynamicKeybindsModel.setProperty(outerIndex, "mods", prevMods.join(" "));
                                                    captureTrap.accumulatedMods = prevMods;
                                                } else {
                                                    let allMods = [...captureTrap.accumulatedMods];
                                                    for (let m of newMods) { if (!allMods.includes(m)) allMods.push(m); }
                                                    captureTrap.accumulatedMods = allMods;
                                                    dynamicKeybindsModel.setProperty(outerIndex, "mods", allMods.join(" "));
                                                }
                                                captureTrap.accumulatedKey = k;
                                                dynamicKeybindsModel.setProperty(outerIndex, "key", k);
                                            }
                                            onActiveFocusChanged: {
                                                if (!activeFocus) { accumulatedMods = []; accumulatedKey = ""; Quickshell.execDetached(["hyprctl", "dispatch", "submap", "reset"]); }
                                                else { Quickshell.execDetached(["hyprctl", "dispatch", "submap", "passthru"]); }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; spacing: root.s(8); Layout.alignment: Qt.AlignTop; z: 2
                                        ColumnLayout {
                                            Layout.preferredWidth: (parent.width - root.s(8)) * 0.4; Layout.alignment: Qt.AlignTop; spacing: root.s(4)
                                            Rectangle {
                                                Layout.fillWidth: true; Layout.preferredHeight: root.s(30)
                                                radius: root.s(6)
                                                scale: kbRowRect.isTypeOpen ? 1.02 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                                color: kbRowRect.isTypeOpen
                                                    ? Qt.alpha(root.peach, 0.12)
                                                    : root.surface0
                                                border.color: kbRowRect.isTypeOpen ? root.peach : root.surface2
                                                border.width: kbRowRect.isTypeOpen ? 2 : 1
                                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                                Behavior on border.width { NumberAnimation { duration: 150 } }
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                RowLayout {
                                                    anchors.fill: parent; anchors.margins: root.s(7)
                                                    Text {
                                                        text: model.type; font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                                        color: kbRowRect.isTypeOpen ? root.peach : root.text; Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                    }
                                                    Text {
                                                        text: kbRowRect.isTypeOpen ? "▴" : "▾"; font.pixelSize: root.s(10)
                                                        color: kbRowRect.isTypeOpen ? root.peach : root.subtext0
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                    }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { kbRowRect.isTypeOpen = !kbRowRect.isTypeOpen; kbRowRect.isDispOpen = false; } }
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: kbRowRect.isTypeOpen ? root.bindTypes.length * root.s(26) : 0
                                                radius: root.s(6); color: root.surface0; clip: true
                                                border.color: root.surface1; border.width: kbRowRect.isTypeOpen ? 1 : 0
                                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                                ListView {
                                                    anchors.fill: parent; model: root.bindTypes; interactive: false
                                                    opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                                    delegate: Rectangle {
                                                        width: parent.width; height: root.s(26)
                                                        color: typeItemMa.containsMouse ? Qt.alpha(root.peach, 0.12) : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter; x: root.s(8); text: modelData
                                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                                            color: model.type === modelData ? root.peach : root.text
                                                        }
                                                        MouseArea { id: typeItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dynamicKeybindsModel.setProperty(outerIndex, "type", modelData); kbRowRect.isTypeOpen = false; } }
                                                    }
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.preferredWidth: (parent.width - root.s(8)) * 0.6; Layout.alignment: Qt.AlignTop; spacing: root.s(4)
                                            Rectangle {
                                                Layout.fillWidth: true; Layout.preferredHeight: root.s(30)
                                                radius: root.s(6)
                                                scale: kbRowRect.isDispOpen ? 1.02 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                                color: kbRowRect.isDispOpen
                                                    ? Qt.alpha(root.peach, 0.12)
                                                    : root.surface0
                                                border.color: kbRowRect.isDispOpen ? root.peach : root.surface2
                                                border.width: kbRowRect.isDispOpen ? 2 : 1
                                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                                Behavior on border.width { NumberAnimation { duration: 150 } }
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                RowLayout {
                                                    anchors.fill: parent; anchors.margins: root.s(7)
                                                    Text {
                                                        text: model.dispatcher; font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                                        color: kbRowRect.isDispOpen ? root.peach : root.text; Layout.fillWidth: true
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                    }
                                                    Text {
                                                        text: kbRowRect.isDispOpen ? "▴" : "▾"; font.pixelSize: root.s(10)
                                                        color: kbRowRect.isDispOpen ? root.peach : root.subtext0
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                    }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { kbRowRect.isDispOpen = !kbRowRect.isDispOpen; kbRowRect.isTypeOpen = false; } }
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: kbRowRect.isDispOpen ? Math.min(root.s(140), root.dispatchers.length * root.s(26)) : 0
                                                radius: root.s(6); color: root.surface0; clip: true
                                                border.color: root.surface1; border.width: kbRowRect.isDispOpen ? 1 : 0
                                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                                ListView {
                                                    anchors.fill: parent; model: root.dispatchers; interactive: true
                                                    opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                                    ScrollBar.vertical: ScrollBar { active: true; policy: ScrollBar.AsNeeded }
                                                    delegate: Rectangle {
                                                        width: parent.width; height: root.s(26)
                                                        color: dispItemMa.containsMouse ? Qt.alpha(root.peach, 0.12) : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter; x: root.s(8); text: modelData
                                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                                            color: model.dispatcher === modelData ? root.peach : root.text
                                                        }
                                                        MouseArea { id: dispItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dynamicKeybindsModel.setProperty(outerIndex, "dispatcher", modelData); kbRowRect.isDispOpen = false; } }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Command input
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                        radius: root.s(6)
                                        color: cmdInput.activeFocus ? Qt.alpha(root.peach, 0.08) : root.surface0
                                        border.color: cmdInput.activeFocus ? root.peach : root.surface2
                                        border.width: 1; z: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                        TextInput {
                                            id: cmdInput
                                            anchors.fill: parent; anchors.margins: root.s(9)
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: model.command
                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                            color: root.text; clip: true; selectByMouse: true
                                            onTextChanged: dynamicKeybindsModel.setProperty(outerIndex, "command", text)
                                            Text {
                                                text: "Command arguments..."
                                                color: root.subtext0
                                                visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; Layout.alignment: Qt.AlignRight; spacing: root.s(8); z: 0
                                        // Delete button
                                        Rectangle {
                                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(30); radius: root.s(7)
                                            color: delMa.containsMouse ? root.red : root.surface1
                                            border.color: delMa.containsMouse ? root.red : Qt.alpha(root.red, 0.4)
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                            Behavior on border.color { ColorAnimation { duration: 180 } }
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: root.s(6)
                                                Text {
                                                    text: "󰆴"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14)
                                                    color: delMa.containsMouse ? root.base : root.red
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                                Text {
                                                    text: "Delete"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); font.weight: Font.Medium
                                                    color: delMa.containsMouse ? root.base : root.red
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                            }
                                            MouseArea { 
                                                id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; 
                                                onClicked: { 
                                                    root.forceActiveFocus();
                                                    dynamicKeybindsModel.remove(outerIndex); 
                                                    root.saveAllKeybinds(); 
                                                } 
                                            }
                                        }
                                        // Save button
                                        Rectangle {
                                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(30); radius: root.s(7)
                                            color: rowSaveMa.containsMouse ? root.green : root.surface1
                                            border.color: rowSaveMa.containsMouse ? root.green : Qt.alpha(root.green, 0.4)
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                            Behavior on border.color { ColorAnimation { duration: 180 } }
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: root.s(6)
                                                Text {
                                                    text: "󰆓"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14)
                                                    color: rowSaveMa.containsMouse ? root.base : root.green
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                                Text {
                                                    text: "Save"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); font.weight: Font.Medium
                                                    color: rowSaveMa.containsMouse ? root.base : root.green
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                            }
                                            MouseArea {
                                                id: rowSaveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    let validationResult = root.validateKeybind(outerIndex, model.mods, model.key, model.dispatcher, model.command);
                                                    if (validationResult !== "VALID") { 
                                                        Quickshell.execDetached(["notify-send", "-u", "critical", "Keybind Error", validationResult]); 
                                                        return; 
                                                    }
                                                    dynamicKeybindsModel.setProperty(outerIndex, "isEditing", false);
                                                    root.forceActiveFocus();
                                                    root.saveAllKeybinds();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    } 


    // ── Main Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: sidebarPanel
        anchors.fill: parent
        color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.97)
        radius: root.s(16)
        border.width: 1
        border.color: Qt.rgba(root.surface1.r, root.surface1.g, root.surface1.b, 0.9)
        clip: true

        Rectangle {
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: root.s(16)
            color: sidebarPanel.color
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: sidebarPanel.border.color }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: sidebarPanel.border.color }
            Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: sidebarPanel.border.color }
        }

        Item {
            anchors.fill: parent
            opacity: introContent
            scale: 0.96 + (0.04 * introContent)
            transform: Translate { y: root.s(40) * (1.0 - introContent) }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.s(20)
                spacing: root.s(12)

                // ── Header ────────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(10)

                    Text { 
                        text: "Settings"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(24)
                        color: root.text; Layout.alignment: Qt.AlignVCenter 
                    }

                    Rectangle {
                        visible: root.isSearchMode
                        width: root.s(26); height: root.s(26); radius: root.s(6)
                        color: closeSearchMa.containsMouse ? Qt.alpha(root.red, 0.15) : "transparent"
                        border.color: closeSearchMa.containsMouse ? root.red : "transparent"; border.width: 1
                        opacity: root.isSearchMode ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "✕"; font.family: "Inter"; font.pixelSize: root.s(12); color: closeSearchMa.containsMouse ? root.red : root.subtext0; Behavior on color { ColorAnimation { duration: 150 } } }
                        MouseArea {
                            id: closeSearchMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.isSearchMode = false; root.globalSearchQuery = ""; globalSearchInput.text = ""; root.searchHighlightIndex = -1; }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Save button
                    Rectangle {
                        id: headerSaveBtn
                        visible: root.currentTab !== 2 && !root.isSearchMode
                        opacity: visible ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: root.s(34)
                        Layout.preferredWidth: saveBtnRow.implicitWidth + root.s(28)

                        radius: root.s(8)
                        scale: headerSaveMa.pressed ? 0.94 : (headerSaveMa.containsMouse ? 1.03 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                        color: headerSaveMa.pressed
                            ? Qt.darker(root.mauve, 1.15)
                            : (headerSaveMa.containsMouse ? root.mauve : root.surface1)
                        border.color: headerSaveMa.containsMouse ? root.mauve : Qt.alpha(root.mauve, 0.4)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                        Behavior on border.color { ColorAnimation { duration: 180 } }

                        RowLayout {
                            id: saveBtnRow
                            anchors.centerIn: parent
                            spacing: root.s(7)
                            Text { 
                                text: "󰆓"
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: root.s(15)
                                color: headerSaveMa.containsMouse ? root.base : root.mauve
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                            Text { 
                                text: "Save"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Bold
                                font.pixelSize: root.s(12)
                                color: headerSaveMa.containsMouse ? root.base : root.text
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                        }

                        MouseArea {
                            id: headerSaveMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.currentTab === 0) root.saveAppSettings();
                                else if (root.currentTab === 1) root.saveWeatherConfig();
                            }
                        }
                    }

                    // Add button
                    Rectangle {
                        id: headerAddBtn
                        visible: root.currentTab === 2 && !root.isSearchMode
                        opacity: visible ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: root.s(34)
                        Layout.preferredWidth: addBtnRow.implicitWidth + root.s(28)

                        radius: root.s(8)
                        scale: headerAddMa.pressed ? 0.94 : (headerAddMa.containsMouse ? 1.03 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                        color: headerAddMa.pressed
                            ? Qt.darker(root.peach, 1.15)
                            : (headerAddMa.containsMouse ? root.peach : root.surface1)
                        border.color: headerAddMa.containsMouse ? root.peach : Qt.alpha(root.peach, 0.4)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                        Behavior on border.color { ColorAnimation { duration: 180 } }

                        RowLayout {
                            id: addBtnRow
                            anchors.centerIn: parent
                            spacing: root.s(7)
                            Text { 
                                text: "+"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Bold
                                font.pixelSize: root.s(15)
                                color: headerAddMa.containsMouse ? root.base : root.peach
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                            Text { 
                                text: "Add"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Bold
                                font.pixelSize: root.s(12)
                                color: headerAddMa.containsMouse ? root.base : root.text
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                        }

                        MouseArea {
                            id: headerAddMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                dynamicKeybindsModel.append({ type: "bind", mods: "", key: "", dispatcher: "exec", command: "", isEditing: true });
                                scrollTimer.start();
                            }
                        }
                    }
                }

                // ── Search bar ────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: root.s(40); radius: root.s(10)
                    color: root.isSearchMode
                        ? Qt.alpha(root.sapphire, 0.06)
                        : (globalSearchBarMa.containsMouse ? Qt.alpha(root.surface1, 0.6) : Qt.alpha(root.surface0, 0.5))
                    border.color: root.isSearchMode ? root.sapphire : (globalSearchBarMa.containsMouse ? root.surface2 : root.surface1)
                    border.width: root.isSearchMode ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    Behavior on border.width { NumberAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: root.s(11); anchors.rightMargin: root.s(11); spacing: root.s(9)
                        Text {
                            text: "󰍉"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15)
                            color: root.isSearchMode ? root.sapphire : root.subtext0
                            Behavior on color { ColorAnimation { duration: 200 } }
                            MouseArea { anchors.fill: parent; anchors.margins: -root.s(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.isSearchMode = true; globalSearchInput.forceActiveFocus(); } }
                        }
                        TextInput {
                            id: globalSearchInput
                            Layout.fillWidth: true; Layout.fillHeight: true; verticalAlignment: TextInput.AlignVCenter
                            font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.text; clip: true; selectByMouse: true
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: root.isSearchMode ? "Search settings & keybinds..." : "Search"
                                color: Qt.alpha(root.subtext0, 0.45)
                                visible: !globalSearchInput.text && !globalSearchInput.activeFocus
                                font.family: "JetBrains Mono"; font.pixelSize: root.s(12)
                            }
                            onActiveFocusChanged: { if (activeFocus && !root.isSearchMode) root.isSearchMode = true; }
                            onTextChanged: { root.globalSearchQuery = text; if (!root.isSearchMode && text.length > 0) root.isSearchMode = true; }
                            Keys.onEscapePressed: { root.isSearchMode = false; root.globalSearchQuery = ""; text = ""; root.searchHighlightIndex = -1; root.forceActiveFocus(); }
                            Keys.onDownPressed: (event) => {
                                root.forceActiveFocus();
                                let total = root.searchResultItems.length;
                                if (total === 0) { event.accepted = true; return; }
                                root.searchHighlightIndex = root.searchHighlightIndex < total - 1 ? root.searchHighlightIndex + 1 : 0;
                                root.scrollSearchHighlightIntoView(root.searchHighlightIndex);
                                event.accepted = true;
                            }
                            Keys.onUpPressed: (event) => {
                                root.forceActiveFocus();
                                let total = root.searchResultItems.length;
                                if (total === 0) { event.accepted = true; return; }
                                root.searchHighlightIndex = root.searchHighlightIndex > 0 ? root.searchHighlightIndex - 1 : (root.searchHighlightIndex === 0 ? total - 1 : total - 1);
                                root.scrollSearchHighlightIntoView(root.searchHighlightIndex);
                                event.accepted = true;
                            }
                            Keys.onReturnPressed: (event) => {
                                if (root.searchHighlightIndex >= 0) { root.activateSearchHighlight(); event.accepted = true; }
                            }
                            Keys.onEnterPressed: (event) => {
                                if (root.searchHighlightIndex >= 0) { root.activateSearchHighlight(); event.accepted = true; }
                            }
                        }
                        Rectangle {
                            visible: root.isSearchMode && globalSearchInput.text.length > 0; width: root.s(20); height: root.s(20); radius: root.s(4)
                            color: clearSearchBtnMa.containsMouse ? Qt.alpha(root.red, 0.15) : "transparent"
                            border.color: clearSearchBtnMa.containsMouse ? root.red : "transparent"; border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: root.s(10); color: clearSearchBtnMa.containsMouse ? root.red : Qt.alpha(root.subtext0, 0.6); Behavior on color { ColorAnimation { duration: 150 } } }
                            MouseArea { id: clearSearchBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { globalSearchInput.text = ""; globalSearchInput.forceActiveFocus(); } }
                        }
                    }
                    MouseArea { id: globalSearchBarMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !root.isSearchMode; onClicked: { root.isSearchMode = true; globalSearchInput.forceActiveFocus(); } }
                }

                // ── Tab bar ───────────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(38)
                    visible: !root.isSearchMode
                    opacity: root.isSearchMode ? 0.0 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                    // Background track
                    Rectangle {
                        anchors.fill: parent; radius: root.s(10)
                        color: root.surface0; border.color: root.surface1; border.width: 1
                    }

                    // Morphing pill
                    Rectangle {
                        id: tabHighlightPill
                        y: root.s(3)
                        height: root.s(32)
                        radius: root.s(8)

                        property color c0: root.teal
                        property color c1: root.blue
                        property color c2: root.peach
                        property color targetColor: {
                            if (root.currentTab === 0) return c0;
                            if (root.currentTab === 1) return c1;
                            return c2;
                        }
                        color: targetColor
                        Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.OutExpo } }

                        property int prevTab: 0
                        property int curTab: root.currentTab

                        onCurTabChanged: {
                            if (curTab > prevTab) {
                                tabRightAnim.duration = 200; tabLeftAnim.duration = 350;
                            } else if (curTab < prevTab) {
                                tabLeftAnim.duration = 200; tabRightAnim.duration = 350;
                            }
                            prevTab = curTab;
                        }

                        property real tabW: (parent.width - root.s(6)) / 3
                        property real targetLeft: root.s(3) + curTab * tabW
                        property real targetRight: targetLeft + tabW

                        property real actualLeft: targetLeft
                        property real actualRight: targetRight

                        Behavior on actualLeft { NumberAnimation { id: tabLeftAnim; duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on actualRight { NumberAnimation { id: tabRightAnim; duration: 250; easing.type: Easing.OutExpo } }

                        x: actualLeft
                        width: actualRight - actualLeft
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: root.s(3)
                        spacing: 0

                        Repeater {
                            model: root.tabNames.length
                            Item {
                                width: (parent.width) / 3
                                height: parent.height

                                property bool isActive: root.currentTab === index

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: root.s(7)
                                    Text {
                                        text: root.tabIcons[index]
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: root.s(14)
                                        color: isActive ? root.base : root.subtext0
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                    }
                                    Text {
                                        text: root.tabNames[index]
                                        font.family: "JetBrains Mono"
                                        font.weight: isActive ? Font.Bold : Font.Medium
                                        font.pixelSize: root.s(12)
                                        color: isActive ? root.base : root.subtext0
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.currentTab = index; root.clearHighlight(); }
                                }
                            }
                        }
                    }
                }

                // ── Content area ──────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true

                    // Search results
                    Flickable {
                        id: searchResultsFlickable
                        anchors.fill: parent; contentWidth: width
                        contentHeight: searchResultsCol.implicitHeight + root.s(40)
                        boundsBehavior: Flickable.StopAtBounds; clip: true
                        visible: root.isSearchMode
                        opacity: root.isSearchMode ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250 } }

                        MouseArea { anchors.fill: parent; onClicked: root.clearHighlight(); z: -1 }

                        ColumnLayout {
                            id: searchResultsCol; width: parent.width; spacing: root.s(8)

                            Item {
                                Layout.fillWidth: true; Layout.preferredHeight: root.s(80)
                                visible: root.globalSearchQuery.trim() === ""
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: root.s(8)
                                    Text { Layout.alignment: Qt.AlignHCenter; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(30); color: Qt.alpha(root.subtext0, 0.25) }
                                    Text { Layout.alignment: Qt.AlignHCenter; text: "Type to search settings & keybinds..."; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: Qt.alpha(root.subtext0, 0.35) }
                                }
                            }

                            Repeater {
                                id: settingsCardRepeater
                                model: root.allSettingsCards.length
                                delegate: Item {
                                    property var card: root.allSettingsCards[index]
                                    property bool matches: root.globalSearchMatches(card, root.globalSearchQuery)
                                    property int searchListIndex: {
                                        let pos = 0;
                                        for (let i = 0; i < root.searchResultItems.length; i++) {
                                            if (root.searchResultItems[i].kind === "card" && root.searchResultItems[i].cardIndex === index) { pos = i; break; }
                                        }
                                        return pos;
                                    }
                                    property bool isSearchHighlighted: matches && root.searchHighlightIndex === searchListIndex && root.searchHighlightIndex >= 0
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: matches ? root.s(58) : 0
                                    visible: matches; opacity: matches ? 1.0 : 0.0; clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

                                    Rectangle {
                                        anchors.fill: parent; radius: root.s(10)
                                        // FIX 6: Search results — highlighted uses surface1 + colored border instead of full color fill
                                        color: isSearchHighlighted
                                            ? root.surface1
                                            : (searchCardMa.containsMouse ? root.surface1 : root.surface0)
                                        border.color: isSearchHighlighted ? root[card.color] : (searchCardMa.containsMouse ? root[card.color] : root.surface1)
                                        border.width: isSearchHighlighted ? 2 : 1
                                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }
                                        Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }

                                        RowLayout {
                                            anchors.fill: parent; anchors.margins: root.s(12); spacing: root.s(12)
                                            Rectangle {
                                                width: root.s(32); height: root.s(32); radius: root.s(8)
                                                color: Qt.alpha(root[card.color], 0.15)
                                                border.color: Qt.alpha(root[card.color], 0.3); border.width: 1
                                                Text {
                                                    anchors.centerIn: parent; text: card.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15)
                                                    color: root[card.color]
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: root.s(2)
                                                Text {
                                                    text: card.label; font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: root.s(13)
                                                    color: isSearchHighlighted ? root[card.color] : root.text; Layout.fillWidth: true
                                                    Behavior on color { ColorAnimation { duration: 200 } }
                                                }
                                                Text {
                                                    text: card.desc; font.family: "Inter"; font.pixelSize: root.s(10)
                                                    color: Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true
                                                }
                                            }
                                            Rectangle {
                                                height: root.s(20); width: tabBadgeText.implicitWidth + root.s(12); radius: root.s(10)
                                                color: Qt.alpha(root[root.tabColors[card.tab]], 0.15)
                                                border.color: Qt.alpha(root[root.tabColors[card.tab]], 0.4); border.width: 1
                                                Text {
                                                    id: tabBadgeText; anchors.centerIn: parent; text: root.tabNames[card.tab]
                                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(9)
                                                    color: root[root.tabColors[card.tab]]
                                                }
                                            }
                                            Text {
                                                text: "›"; font.family: "Inter"; font.pixelSize: root.s(18)
                                                color: isSearchHighlighted ? root[card.color] : (searchCardMa.containsMouse ? root[card.color] : root.subtext0)
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                        }
                                        MouseArea {
                                            id: searchCardMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                jumpToSettingTimer.targetTab = card.tab;
                                                jumpToSettingTimer.targetBox = card.boxIndex;
                                                jumpToSettingTimer.start();
                                                root.currentTab = card.tab;
                                                if (card.tab === 0) root.tab0Loaded = true;
                                                else if (card.tab === 1) root.tab1Loaded = true;
                                                else if (card.tab === 2) root.tab2Loaded = true;
                                                root.isSearchMode = false;
                                                root.forceActiveFocus();
                                                globalSearchInput.text = "";
                                                root.globalSearchQuery = "";
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: (root.globalSearchQuery.trim() !== "" && root.matchingKeybindIndices.length > 0) ? root.s(30) : 0
                                visible: root.globalSearchQuery.trim() !== "" && root.matchingKeybindIndices.length > 0
                                opacity: visible ? 1.0 : 0.0; clip: true
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: root.s(4); spacing: root.s(8)
                                    Rectangle { width: root.s(3); height: root.s(12); radius: root.s(2); color: root.peach }
                                    Text { text: "Keybinds (" + root.matchingKeybindIndices.length + " match" + (root.matchingKeybindIndices.length !== 1 ? "es" : "") + ")"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); color: root.peach }
                                }
                            }

                            Repeater {
                                id: keybindResultRepeater
                                model: root.matchingKeybindIndices.length
                                delegate: Item {
                                    property int kbIndex: root.matchingKeybindIndices[index]
                                    property var kbItem: dynamicKeybindsModel.get(kbIndex)
                                    property int searchListIndex: {
                                        let nCards = 0;
                                        for (let i = 0; i < root.allSettingsCards.length; i++) {
                                            if (root.globalSearchMatches(root.allSettingsCards[i], root.globalSearchQuery)) nCards++;
                                        }
                                        return nCards + index;
                                    }
                                    property bool isSearchHighlighted: root.searchHighlightIndex === searchListIndex && root.searchHighlightIndex >= 0
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.globalSearchQuery.trim() !== "" ? root.s(54) : 0
                                    visible: root.globalSearchQuery.trim() !== ""; opacity: visible ? 1.0 : 0.0; clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    Rectangle {
                                        anchors.fill: parent; radius: root.s(10)
                                        // FIX 6: Keybind search result — highlighted uses surface1 + peach border
                                        color: isSearchHighlighted ? root.surface1 : (kbResultMa.containsMouse ? root.surface1 : root.surface0)
                                        border.color: isSearchHighlighted ? root.peach : (kbResultMa.containsMouse ? root.peach : root.surface1)
                                        border.width: isSearchHighlighted ? 2 : 1
                                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }
                                        Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }

                                        RowLayout {
                                            anchors.fill: parent; anchors.margins: root.s(11); spacing: root.s(11)
                                            Rectangle {
                                                width: root.s(32); height: root.s(32); radius: root.s(8)
                                                color: Qt.alpha(root.peach, 0.12)
                                                border.color: Qt.alpha(root.peach, 0.25); border.width: 1
                                                Text {
                                                    anchors.centerIn: parent; text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15)
                                                    color: root.peach
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: root.s(3)
                                                Row {
                                                    spacing: root.s(4)
                                                    Rectangle {
                                                        width: modsT.implicitWidth + root.s(8); height: root.s(18); radius: root.s(4)
                                                        color: root.surface1
                                                        border.color: root.surface2; border.width: 1
                                                        visible: kbItem && kbItem.mods !== ""
                                                        Text {
                                                            id: modsT; anchors.centerIn: parent; text: kbItem ? kbItem.mods : ""
                                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(8)
                                                            color: root.peach
                                                        }
                                                    }
                                                    Text {
                                                        text: "+"; font.family: "JetBrains Mono"; font.pixelSize: root.s(9)
                                                        color: root.overlay0
                                                        visible: kbItem && kbItem.mods !== "" && kbItem.key !== ""; anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    Rectangle {
                                                        width: keyT.implicitWidth + root.s(8); height: root.s(18); radius: root.s(4)
                                                        color: root.surface1
                                                        border.color: root.surface2; border.width: 1
                                                        visible: kbItem && kbItem.key !== ""
                                                        Text {
                                                            id: keyT; anchors.centerIn: parent; text: kbItem ? kbItem.key : ""
                                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(8)
                                                            color: root.peach
                                                        }
                                                    }
                                                }
                                                Text {
                                                    text: kbItem ? (kbItem.dispatcher + " " + kbItem.command).trim() : ""
                                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(9)
                                                    color: isSearchHighlighted ? root.peach : Qt.alpha(root.subtext0, 0.7)
                                                    elide: Text.ElideRight; Layout.fillWidth: true
                                                    Behavior on color { ColorAnimation { duration: 200 } }
                                                }
                                            }
                                            Rectangle {
                                                height: root.s(20); width: kbBadgeText.implicitWidth + root.s(12); radius: root.s(10)
                                                color: Qt.alpha(root.peach, 0.12)
                                                border.color: Qt.alpha(root.peach, 0.35); border.width: 1
                                                Text {
                                                    id: kbBadgeText; anchors.centerIn: parent; text: "Keybinds"
                                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(9)
                                                    color: root.peach
                                                }
                                            }
                                            Text {
                                                text: "›"; font.family: "Inter"; font.pixelSize: root.s(18)
                                                color: isSearchHighlighted ? root.peach : (kbResultMa.containsMouse ? root.peach : root.subtext0)
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                        }
                                        MouseArea {
                                            id: kbResultMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                jumpToSettingTimer.targetTab = 2;
                                                jumpToSettingTimer.targetBox = kbIndex;
                                                jumpToSettingTimer.start();
                                                root.currentTab = 2;
                                                root.tab2Loaded = true;
                                                root.isSearchMode = false;
                                                root.forceActiveFocus();
                                                globalSearchInput.text = "";
                                                root.globalSearchQuery = "";
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        id: generalLoader
                        anchors.fill: parent
                        active: root.tab0Loaded && root.dataReady
                        sourceComponent: generalTabComponent
                        visible: root.currentTab === 0 && !root.isSearchMode
                        opacity: visible ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        function focusLangInput() { if (item) item.focusLangInput(); }
                        function focusWpDirInput() { if (item) item.focusWpDirInput(); }
                        function layoutListIncrementIndex() { if (item) item.layoutListIncrementIndex(); }
                        function layoutListDecrementIndex() { if (item) item.layoutListDecrementIndex(); }
                        function acceptLayoutSelection() { if (item) item.acceptLayoutSelection(); }
                        function scrollTo(y) { if (item) item.scrollTo(y); }
                        function scrollToBox(y) { if (item) item.scrollToBox(y); }
                    }

                    Loader {
                        id: weatherLoader
                        anchors.fill: parent
                        active: root.tab1Loaded && root.dataReady
                        sourceComponent: weatherTabComponent
                        visible: root.currentTab === 1 && !root.isSearchMode
                        opacity: visible ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        function focusApiKey() { if (item) item.focusApiKey(); }
                        function focusCityId() { if (item) item.focusCityId(); }
                        function scrollTo(y) { if (item) item.scrollTo(y); }
                        function scrollToBox(y) { if (item) item.scrollToBox(y); }
                    }

                    Loader {
                        id: keybindLoader
                        anchors.fill: parent
                        active: root.tab2Loaded && root.dataReady
                        sourceComponent: keybindTabComponent
                        visible: root.currentTab === 2 && !root.isSearchMode
                        opacity: visible ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        function scrollToBottom() { if (item) item.scrollToBottom(); }
                        function scrollTo(y) { if (item) item.scrollTo(y); }
                        function scrollToBox(y) { if (item) item.scrollToBox(y); }
                    }
                }
            }
        }
    }
}
