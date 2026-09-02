import Quickshell
import Quickshell.Io
import qs.desktop.modules.common

// Global controller for the Spotlight-like window switcher. Its window stays
// bound to ScreenLifecycle's last real output across suspend/resume churn.
Scope {
    id: root

    property bool open: false
    property string mode: "window"
    property string viewMode: "list"
    readonly property var targetScreen: ScreenLifecycle.activeScreen

    function normalizeMode(value) {
        return value === "app" || value === "clipboard" ? value : "window"
    }
    function show(modeName) {
        mode = normalizeMode(modeName)
        if (mode === "clipboard")
            ClipboardService.refresh()
        open = true
    }
    function hide() { open = false }
    function toggle(modeName) {
        const nextMode = normalizeMode(modeName)
        if (!open) {
            mode = nextMode
            if (mode === "clipboard")
                ClipboardService.refresh()
            open = true
        } else if (mode === nextMode) {
            open = false
        } else {
            mode = nextMode
            if (mode === "clipboard")
                ClipboardService.refresh()
        }
    }
    function cycleMode() {
        const modes = ["window", "app", "clipboard"]
        mode = modes[(modes.indexOf(mode) + 1) % modes.length]
        if (mode === "clipboard")
            ClipboardService.refresh()
        open = true
    }
    function toggleViewMode() {
        viewMode = viewMode === "list" ? "grid" : "list"
    }

    IpcHandler {
        target: "quicksearch"

        function show(mode: string): void { root.show(mode) }
        function hide(): void { root.hide() }
        function toggle(mode: string): void { root.toggle(mode) }
    }

    QuickSearchWindow {
        screen: root.targetScreen
        visible: root.open && ScreenLifecycle.outputAvailable
            && root.targetScreen !== null
        open: root.open
        mode: root.mode
        viewMode: root.viewMode
        onCloseRequested: root.hide()
        onModeCycleRequested: root.cycleMode()
        onViewModeToggleRequested: root.toggleViewMode()
    }
}
