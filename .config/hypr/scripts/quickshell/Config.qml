pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: config

    // =========================================================================
    // Core Paths & Environment
    // =========================================================================
    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string hyprDir: homeDir + "/.config/hypr"
    readonly property string qsScriptsDir: hyprDir + "/scripts/quickshell"
    readonly property string cacheDir: homeDir + "/.cache/quickshell"
    
    readonly property string settingsJsonPath: hyprDir + "/settings.json"
    readonly property string weatherEnvPath: qsScriptsDir + "/calendar/.env"

    // State Tracking
    property bool dataReady: false
    property var rawSettings: ({})
    property var rawEnvs: ({})

    // =========================================================================
    // Generic Utilities (Use these in ANY widget!)
    // =========================================================================

    // Execute a background bash command easily
    function sh(cmd) {
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    // --- JSON Operations ---
    function getSetting(key, fallbackValue) {
        return rawSettings.hasOwnProperty(key) ? rawSettings[key] : fallbackValue;
    }

    function setSetting(key, value) {
        rawSettings[key] = value;
        let safeValue = typeof value === "string" ? `"${value}"` : value;
        if (typeof value === "object") safeValue = JSON.stringify(value).replace(/'/g, "'\\''");

        let cmd = `mkdir -p "$(dirname '${settingsJsonPath}')" && ` +
                  `[ ! -f '${settingsJsonPath}' ] && echo '{}' > '${settingsJsonPath}'; ` +
                  `jq '. + {"${key}": ${safeValue}}' '${settingsJsonPath}' > '${settingsJsonPath}.tmp' && ` +
                  `mv '${settingsJsonPath}.tmp' '${settingsJsonPath}'`;
        sh(cmd);
    }

    function updateJsonBulk(dataObj) {
        let jsonStr = JSON.stringify(dataObj).replace(/'/g, "'\\''");
        let cmd = `mkdir -p "$(dirname '${settingsJsonPath}')" && ` +
                  `[ ! -f '${settingsJsonPath}' ] && echo '{}' > '${settingsJsonPath}'; ` +
                  `jq '. + ${jsonStr}' '${settingsJsonPath}' > '${settingsJsonPath}.tmp' && ` +
                  `mv '${settingsJsonPath}.tmp' '${settingsJsonPath}'`;
        sh(cmd);
        
        for (let key in dataObj) rawSettings[key] = dataObj[key];
    }

    // --- Env Operations ---
    function getEnv(key, fallbackValue) {
        return rawEnvs.hasOwnProperty(key) ? rawEnvs[key] : fallbackValue;
    }

    function updateEnvBulk(filePath, envDict) {
        let cmds = [`mkdir -p "$(dirname '${filePath}')"`, `touch '${filePath}'`];
        for (let key in envDict) {
            rawEnvs[key] = envDict[key];
            let safeVal = envDict[key].toString().replace(/'/g, "'\\''");
            cmds.push(`if grep -q "^${key}=" '${filePath}'; then ` +
                      `sed -i "s|^${key}=.*|${key}='${safeVal}'|" '${filePath}'; ` +
                      `else echo "${key}='${safeVal}'" >> '${filePath}'; fi`);
        }
        sh(cmds.join(" && "));
    }

    // =========================================================================
    // Legacy Specific Properties (Bound to Settings.qml)
    // =========================================================================
    property real uiScale: 1.0
    property bool openGuideAtStartup: true
    property bool topbarHelpIcon: true
    property int workspaceCount: 8
    property int initialWorkspaceCount: 8
    property string wallpaperDir: Quickshell.env("WALLPAPER_DIR") || (homeDir + "/Pictures/Wallpapers")
    property string language: ""
    property string kbOptions: "grp:alt_shift_toggle"

    property string weatherUnit: "metric"
    property string weatherApiKey: ""
    property string weatherCityId: ""

    property string dateFormat: "dddd, MMMM dd"
    property string timeFormat: "HH:mm:ss"

    property var keybindsData: []
    signal keybindsLoaded()

    property var startupData: []
    signal startupLoaded()

    // =========================================================================
    // Settings Save Functions
    // =========================================================================
    function saveAppSettings() {
        let configObj = {
            "uiScale": config.uiScale,
            "openGuideAtStartup": config.openGuideAtStartup,
            "topbarHelpIcon": config.topbarHelpIcon,
            "wallpaperDir": config.wallpaperDir,
            "language": config.language,
            "kbOptions": config.kbOptions,
            "workspaceCount": config.workspaceCount,
            "dateFormat": config.dateFormat,
            "timeFormat": config.timeFormat
        };

        config.updateJsonBulk(configObj);
        sh("notify-send 'Quickshell' 'Settings Applied Successfully!'");

        if (config.workspaceCount !== config.initialWorkspaceCount) {
            sh(`qs -p "${qsScriptsDir}/TopBar.qml" ipc call topbar queueReload`);
            config.initialWorkspaceCount = config.workspaceCount;
        }
    }

    function saveWeatherConfig() {
        let envs = {
            "OPENWEATHER_KEY": config.weatherApiKey,
            "OPENWEATHER_CITY_ID": config.weatherCityId,
            "OPENWEATHER_UNIT": config.weatherUnit
        };
        
        config.updateEnvBulk(config.weatherEnvPath, envs);
        sh(`rm -rf "${cacheDir}/weather"`);
        sh("notify-send 'Weather' 'API configuration saved successfully!'");
    }

    function saveAllKeybinds(bindsArray) {
        config.keybindsData = bindsArray;
        config.setSetting("keybinds", bindsArray);
        sh("notify-send 'Quickshell' 'Keybinds Saved Successfully!'");
    }

    function saveAllStartup(startupArray) {
        config.startupData = startupArray;
        config.setSetting("startup", startupArray);
        sh("notify-send 'Quickshell' 'Startup entries saved!'");
    }

    // =========================================================================
    // Boot Initialization (Runs once on start)
    // =========================================================================
    Component.onCompleted: {
        settingsReader.running = true;
        envReader.running = true;
    }

    Process {
        id: envReader
        command: ["bash", "-c", `cat "${config.weatherEnvPath}" 2>/dev/null || echo ''`]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text ? this.text.trim().split('\n') : [];
                for (let line of lines) {
                    line = line.trim();
                    let parts = line.split("=");
                    if (parts.length >= 2) {
                        let key = parts[0].trim();
                        let val = parts.slice(1).join("=").replace(/^['"]|['"]$/g, '').trim();
                        config.rawEnvs[key] = val;
                        
                        if (key === "OPENWEATHER_KEY") config.weatherApiKey = val;
                        else if (key === "OPENWEATHER_CITY_ID") config.weatherCityId = val;
                        else if (key === "OPENWEATHER_UNIT") config.weatherUnit = val;
                    }
                }
            }
        }
    }

    Process {
        id: settingsReader
        command: ["bash", "-c", `cat "${config.settingsJsonPath}" 2>/dev/null || echo '{}'`]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        config.rawSettings = JSON.parse(this.text);
                        
                        // Map explicitly defined properties
                        if (config.rawSettings.uiScale !== undefined) config.uiScale = config.rawSettings.uiScale;
                        if (config.rawSettings.openGuideAtStartup !== undefined) config.openGuideAtStartup = config.rawSettings.openGuideAtStartup;
                        if (config.rawSettings.topbarHelpIcon !== undefined) config.topbarHelpIcon = config.rawSettings.topbarHelpIcon;
                        if (config.rawSettings.wallpaperDir !== undefined) config.wallpaperDir = config.rawSettings.wallpaperDir;
                        if (config.rawSettings.language !== undefined && config.rawSettings.language !== "") config.language = config.rawSettings.language;
                        if (config.rawSettings.kbOptions !== undefined) config.kbOptions = config.rawSettings.kbOptions;
                        if (config.rawSettings.dateFormat !== undefined) config.dateFormat = config.rawSettings.dateFormat;
                        if (config.rawSettings.timeFormat !== undefined) config.timeFormat = config.rawSettings.timeFormat;
                        if (config.rawSettings.workspaceCount !== undefined) {
                            config.workspaceCount = config.rawSettings.workspaceCount;
                            config.initialWorkspaceCount = config.rawSettings.workspaceCount; 
                        }
                        
                        // Map Keybinds
                        if (config.rawSettings.keybinds !== undefined && Array.isArray(config.rawSettings.keybinds)) {
                            let tempBinds = [];
                            for (let k of config.rawSettings.keybinds) {
                                tempBinds.push({
                                    type: k.type || "bind",
                                    mods: k.mods || "",
                                    key: k.key || "",
                                    dispatcher: k.dispatcher || "exec",
                                    command: k.command || "",
                                    isEditing: false
                                });
                            }
                            config.keybindsData = tempBinds;
                        } else {
                            config.keybindsData = [];
                        }

                        // Map Startups
                        if (config.rawSettings.startup !== undefined && Array.isArray(config.rawSettings.startup)) {
                            let tempStartup = [];
                            for (let s of config.rawSettings.startup) {
                                tempStartup.push({ command: s.command || "" });
                            }
                            config.startupData = tempStartup;
                        } else {
                            config.startupData = [];
                        }
                    } else {
                        config.saveAppSettings();
                        config.keybindsData = [];
                        config.saveAllKeybinds([]);
                        config.startupData = [];
                    }
                } catch (e) {
                    console.log("Error parsing global settings:", e);
                    config.keybindsData = [];
                    config.startupData = [];
                }
                config.keybindsLoaded();
                config.startupLoaded();
                config.dataReady = true;
            }
        }
    }
}
