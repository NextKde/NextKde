import QtQuick

// Coordinate tile motion without animating the glass or its content container.
// Keep the panel visible until the 300 ms tile Animator jobs have finished.
Item {
    id: motion

    required property Item target
    parent: target.parent
    property bool requestedOpen: false
    property bool mapped: false
    property bool settledOpen: false
    readonly property bool interactive: requestedOpen && settledOpen

    function open() {
        settleTimer.stop();
        settledOpen = false;
        mapped = true;
        requestedOpen = true;
        settleTimer.start();
    }

    function close() {
        settleTimer.stop();
        settledOpen = false;
        requestedOpen = false;
        if (mapped)
            settleTimer.start();
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
