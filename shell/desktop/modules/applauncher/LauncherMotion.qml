import QtQuick

// Tile Animator jobs keep the original spread effect. The stationary glass
// fades independently and reaches full opacity before the tiles settle.
Item {
    id: motion
    required property Item target
    parent: target.parent
    property bool requestedOpen: false
    property bool mapped: false
    property bool settledOpen: false
    readonly property bool interactive: requestedOpen && settledOpen
    property real glassOpacity: 0
    property int pendingIcons: 0
    property bool changing: false
    property bool glassFinished: false

    function prepare() {
        changing = true;
        glassFade.stop();
        glassFinished = false;
        settledOpen = false;
    }

    function open() {
        prepare();
        mapped = true;
        requestedOpen = true;
        startGlassFade(1, 100, Easing.OutCubic);
        changing = false;
        finishIfSettled();
    }

    function close() {
        prepare();
        requestedOpen = false;
        if (mapped)
            startGlassFade(0, 200, Easing.OutCubic);
        else
            glassFinished = true;
        changing = false;
        finishIfSettled();
    }

    function startGlassFade(value, duration, curve) {
        glassFade.from = glassOpacity;
        glassFade.to = value;
        glassFade.duration = duration;
        glassFade.easing.type = curve;
        glassFade.start();
    }

    function iconStarted() { pendingIcons += 1; }
    function iconFinished() {
        pendingIcons = Math.max(0, pendingIcons - 1);
        finishIfSettled();
    }
    function finishIfSettled() {
        if (changing || !glassFinished || pendingIcons !== 0)
            return;
        settledOpen = requestedOpen;
        if (!requestedOpen) mapped = false;
    }

    property NumberAnimation glassFade: NumberAnimation {
        target: motion
        property: "glassOpacity"
        onFinished: {
            motion.glassFinished = true;
            motion.finishIfSettled();
        }
    }
}
