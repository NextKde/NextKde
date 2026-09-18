import Quickshell
import Quickshell.Io
import qs.desktop.modules.common

// Global controller for the Spotlight-like window switcher. Its window stays
// bound to ScreenLifecycle's last real output across suspend/resume churn.
//
// 剪贴板不归这里管：它已经拆成独立面板（Meta+V → qs.desktop.modules.clipboard），
// 因为它的尺寸、分类页签和「单击即粘贴」语义都和窗口切换差得太远。
// 本面板现在只在「窗口」和「应用」之间循环。
Scope {
    id: root

    property bool open: false
    property string mode: "window"
    property string viewMode: "list"
    readonly property var targetScreen: ScreenLifecycle.activeScreen

    function normalizeMode(value) {
        return value === "app" ? value : "window"
    }
    function show(modeName) {
        mode = normalizeMode(modeName)
        open = true
    }
    function hide() { open = false }
    function toggle(modeName) {
        const nextMode = normalizeMode(modeName)
        if (!open) {
            mode = nextMode
            open = true
        } else if (mode === nextMode) {
            open = false
        } else {
            mode = nextMode
        }
    }
    function cycleMode() {
        const modes = ["window", "app"]
        mode = modes[(modes.indexOf(mode) + 1) % modes.length]
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
