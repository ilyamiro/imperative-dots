import QtQuick

QtObject {
    id: root

    // Bind this to the width of the window or screen in your widgets
    property real currentWidth: 1920.0
    // The baseline resolution you designed your UI around
    property real referenceWidth: 1920.0

    property real baseScale: {
        if (currentWidth <= 0) return 1.0;
        let r = currentWidth / referenceWidth; 
        
        if (r <= 1.0) {
            // SCALING DOWN:
            // Using Math.pow(r, 0.85) makes the bar shrink "slower" than the screen does.
            // On a 1280px screen (r=0.66), a linear scale is 0.66, 
            // but this power scale keeps it at ~0.70.
            return Math.max(0.35, Math.pow(r, 0.85));
        } else {
            // SCALING UP:
            // Keeps the existing progressive scaling for 2K/4K so it doesn't get huge.
            return Math.pow(r, 0.6);
        }
    }
    
    // Helper function to dynamically scale any pixel value
    function s(val) { 
        return Math.round(val * baseScale); 
    }
}

