import QtQuick

// Coordinate tile motion and a stationary glass fade; content layout stays fixed.
// Keep the panel visible until the 300 ms tile Animator jobs have finished.
Item {
    id: motion

    required property Item target
    parent: target.parent
    property bool requestedOpen: false
    property bool mapped: false
    property bool settledOpen: false
    readonly property bool interactive: requestedOpen && settledOpen
    property real glassOpacity: 0

    function open() {
        settleTimer.stop();
        glassFade.stop();
        settledOpen = false;
        mapped = true;
        requestedOpen = true;
        startGlassFade(1, 180, Easing.OutCubic);
        settleTimer.start();
    }

    function close() {
        settleTimer.stop();
        glassFade.stop();
        settledOpen = false;
        requestedOpen = false;
        if (mapped) {
            startGlassFade(0, 260, Easing.InCubic);
            settleTimer.start();
        }
    }

    function startGlassFade(value, duration, curve) {
        glassFade.from = glassOpacity;
        glassFade.to = value;
        glassFade.duration = duration;
        glassFade.easing.type = curve;
        glassFade.start();
    }

    // Protocol metadata needs GUI-thread updates; only this scalar animates.
    // Capture geometry, tile layout and all tile Animator jobs remain unchanged.
    property NumberAnimation glassFade: NumberAnimation {
        target: motion
        property: "glassOpacity"
    }

    Timer {
        id: settleTimer
        interval: 300
        repeat: false
        onTriggered: {
            motion.settledOpen = motion.requestedOpen;
            if (!motion.requestedOpen)
                motion.mapped = false;
        }
    }
}
