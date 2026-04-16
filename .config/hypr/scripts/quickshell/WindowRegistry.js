.pragma library

function getScale(mw, userScale) {
    if (mw <= 0) return 1.0;
    let r = mw / 1920.0;
    let baseScale = 1.0;
    
    if (r <= 1.0) {
        baseScale = Math.max(0.35, Math.pow(r, 0.85));
    } else {
        // SCALING UP:
        baseScale = Math.pow(r, 0.5);
    }
    
    // Multiply the screen-calculated scale by the user's uiScale
    return baseScale * (userScale !== undefined ? userScale : 1.0);
}

// Helper to easily round scaled values
function s(val, scale) {
    return Math.round(val * scale);
}

// Centralized registry for all widget dimensions and positional mathematics.
function getLayout(name, mx, my, mw, mh, userScale) {
    let scale = getScale(mw, userScale);

    let base = {
        // Right-aligned: pinned 20px from the right edge dynamically
        "battery":   { w: s(801, scale), h: s(760, scale), rx: mw - s(821, scale), ry: s(70, scale), comp: "battery/BatteryPopup.qml" },
        "volume":    { w: s(480, scale), h: s(760, scale), rx: mw - s(500, scale), ry: s(70, scale), comp: "volume/VolumePopup.qml" },
        
        // Centered horizontally dynamically based on current screen width
        "calendar":  { w: s(1450, scale), h: s(750, scale), rx: Math.floor((mw/2)-(s(1450, scale)/2)), ry: s(70, scale), comp: "calendar/CalendarPopup.qml" },
        
        // Left-aligned: pinned 12px from the left edge
        "music":     { w: s(700, scale), h: s(620, scale), rx: s(12, scale), ry: s(70, scale), comp: "music/MusicPopup.qml" },
        
        // Right-aligned: pinned 20px from the right edge dynamically (Width: 900 + 20 margin = 920)
        "network":   { w: s(900, scale), h: s(700, scale), rx: mw - s(920, scale), ry: s(70, scale), comp: "network/NetworkPopup.qml" },
        
        // Centered both horizontally and vertically
        "stewart":   { w: s(800, scale), h: s(600, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(600, scale)/2)), comp: "stewart/stewart.qml" },
        "monitors":  { w: s(850, scale), h: s(580, scale), rx: Math.floor((mw/2)-(s(850, scale)/2)), ry: Math.floor((mh/2)-(s(580, scale)/2)), comp: "monitors/MonitorPopup.qml" },
        "focustime": { w: s(900, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(900, scale)/2)), ry: Math.floor((mh/2)-(s(720, scale)/2)), comp: "focustime/FocusTimePopup.qml" },
        
        // Guide Popup (Centered)
        "guide":     { w: s(1200, scale), h: s(750, scale), rx: Math.floor((mw/2)-(s(1200, scale)/2)), ry: Math.floor((mh/2)-(s(750, scale)/2)), comp: "guide/GuidePopup.qml" },

        // Settings Popup (Centered standalone)
        "settings":  { w: s(900, scale), h: s(750, scale), rx: Math.floor((mw/2)-(s(900, scale)/2)), ry: Math.floor((mh/2)-(s(750, scale)/2)), comp: "settings/SettingsPopup.qml" },

        // Updater Popup (Centered, small)
        "updater":   { w: s(450, scale), h: s(350, scale), rx: Math.floor((mw/2)-(s(450, scale)/2)), ry: Math.floor((mh/2)-(s(350, scale)/2)), comp: "updater/UpdaterPopup.qml" },

        // Notification Center (Centered)
        "notifications": { w: s(800, scale), h: s(700, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(700, scale)/2)), comp: "notifications/NotificationCenter.qml" },

        // Full width, centered vertically
        "wallpaper": { w: mw, h: s(650, scale), rx: 0, ry: Math.floor((mh/2)-(s(650, scale)/2)), comp: "wallpaper/WallpaperPicker.qml" },
        
        "hidden":    { w: 1, h: 1, rx: -5000 - mx, ry: -5000 - my, comp: "" } 
    };

    if (!base[name]) return null;
    
    let t = base[name];
    // Calculate final absolute coordinates based on active monitor offset
    t.x = mx + t.rx;
    t.y = my + t.ry;
    
    return t;
}

// -----------------------------------------------------------------------------
// Separate Layout function for the Notification OSD popups
// -----------------------------------------------------------------------------
function getPopupLayout(mw, userScale) {
    let scale = getScale(mw, userScale);
    return {
        // You can change dimensions and position here
        w: s(350, scale),
        marginTop: s(70, scale),
        marginRight: s(20, scale),
        
        // We can also centralize internal UI scaling sizes here if desired
        spacing: s(12, scale),
        radius: s(14, scale),
        padding: s(12, scale)
    };
}
