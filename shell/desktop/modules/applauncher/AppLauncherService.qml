pragma Singleton
import QtQuick
import Quickshell

// AppLauncherService — public control and geometry contract for the launcher.
//
// The launcher is intentionally independent from Dock. Dock only publishes
// its already-calculated geometry here; keyboard shortcuts, IPC, search and
// app-grid state can all toggle this service without importing Dock visuals.
QtObject {
    id: service

    Component.onCompleted: console.log("[AppLauncherService] instantiated")

    property bool open: false
    property real dockWidth: 0
    property real dockHeight: 0
    // The top bar reserves space that the launcher must also clear so the
    // launcher's vertical centre lines up with the Dock's vertical centre
    // (the Dock is positioned inside the bar-cleared available area).
    property real barHeight: 0
    // Which screen edge the Dock is docked to; the launcher card anchors to
    // the same side (bottom dock: centered above it; side docks: vertically
    // centered beside it).
    property string dockPosition: "bottom"
    // Dock publishes material values as data rather than making this module
    // import qs.desktop.modules.dock. That prevents a circular QML module dependency.
    property color dockBackgroundColor: Qt.rgba(0.08, 0.09, 0.12, 0.92)
    property color dockAmbientPrimary: "transparent"
    property color dockAmbientSecondary: "transparent"
    property color dockForegroundColor: "white"

    function setDockPresentation(width, height, position, background, primary, secondary, foreground, barHeight) {
        service.dockWidth = width
        service.dockHeight = height
        service.dockPosition = position
        service.barHeight = barHeight
        service.dockBackgroundColor = background
        service.dockAmbientPrimary = primary
        service.dockAmbientSecondary = secondary
        service.dockForegroundColor = foreground
        console.log("[AppLauncherService] presentation " + width + "x" + height)
    }

    onOpenChanged: console.log("[AppLauncherService] open=" + open)

    function show() {
        service.open = true
        console.log("[AppLauncher] show width=" + dockWidth
            + " height=" + dockHeight)
    }
    function hide() { service.open = false }
    function toggle() {
        service.open = !service.open
        console.log("[AppLauncher] toggle open=" + service.open
            + " width=" + dockWidth + " height=" + dockHeight)
    }

}
