import Quickshell
import Quickshell.Io
import qs.desktop.modules.dock

// Workspace overview controller.
// Delegates to KDE Plasma 6's native KWin Overview effect via WindowService.
Scope {
    id: root

    function show() { WindowService.setOverviewVisible(true) }
    function hide() { WindowService.setOverviewVisible(false) }
    function toggle() {
        WindowService.toggleOverview()
    }

    IpcHandler {
        target: "overview"
        function show(): void { root.show() }
        function hide(): void { root.hide() }
        function toggle(): void { root.toggle() }
    }
}
