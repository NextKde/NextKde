import Quickshell
import Quickshell.Io
import qs.desktop.modules.common

// Workspace overview controller. KWin owns the actual virtual-desktop
// switching; this module reads WindowService's desktop/window model and shows
// a Stage-Manager-style grid for the current desktop.
Scope {
    id: root

    property bool open: false
    readonly property var targetScreen: ScreenLifecycle.activeScreen

    function show() { open = true }
    function hide() { open = false }
    function toggle() { open = !open }

    IpcHandler {
        target: "overview"
        function show(): void { root.show() }
        function hide(): void { root.hide() }
        function toggle(): void { root.toggle() }
    }

    OverviewWindow {
        screen: root.targetScreen
        open: root.open && ScreenLifecycle.outputAvailable
            && root.targetScreen !== null
        onCloseRequested: root.hide()
    }
}
