pragma Singleton
import QtQuick
import Quickshell

// Keeps output-bound windows away from Qt's synthetic placeholder screen.
// During suspend/resume the compositor may briefly publish no real outputs;
// retain the last real screen reference and hide surfaces until a valid output
// is available again instead of rebinding every PanelWindow to the placeholder.
QtObject {
    id: service

    property var activeScreen: null
    property bool outputAvailable: false

    function _isUsableScreen(screen) {
        return screen !== null
            && screen !== undefined
            && String(screen.name || "").length > 0
            && Number(screen.width) > 0
            && Number(screen.height) > 0
    }

    function _usableScreens() {
        const result = []
        const screens = Quickshell.screens
        for (let index = 0; index < screens.length; ++index) {
            if (_isUsableScreen(screens[index]))
                result.push(screens[index])
        }
        return result
    }

    function refresh() {
        const screens = _usableScreens()
        const nextScreen = screens.length > 1
            ? screens[1]
            : (screens.length > 0 ? screens[0] : null)

        outputAvailable = nextScreen !== null
        if (nextScreen !== null)
            activeScreen = nextScreen
    }

    function refreshAndSettle() {
        // Hide all output-bound surfaces before Qt tears down/recreates its
        // QScreen objects, then drop the wrapper before its QObject destructor
        // can notify bindings that still reach into a QQuickWindow item tree.
        outputAvailable = false
        activeScreen = null
        settleTimer.restart()
    }

    property Connections screenConnections: Connections {
        target: Quickshell
        function onScreensChanged() { service.refreshAndSettle() }
    }

    property Timer settleTimer: Timer {
        interval: 300
        repeat: false
        onTriggered: service.refresh()
    }

    Component.onCompleted: refresh()
}
