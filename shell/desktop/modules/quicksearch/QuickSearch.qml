import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform

// Global controller for the Spotlight-like window switcher. Its window stays
// bound to ScreenLifecycle's last real output across suspend/resume churn.
//
// It also owns the clipboard "click to paste" lifecycle. Ctrl+V is delivered by
// the compositor to whichever window holds keyboard focus, and that focus only
// comes back asynchronously after this focusable layer surface unmaps. A fixed
// delay is wrong at both ends (too short loses the paste, too long feels
// stuck), so the controller remembers the pre-panel window and injects the
// chord as soon as focus returns to it.
Scope {
    id: root

    property bool open: false
    property string mode: "window"
    property string viewMode: "list"
    readonly property var targetScreen: ScreenLifecycle.activeScreen

    // Window that was active before the panel took keyboard focus. Empty means
    // there was nothing to paste into (for example the desktop itself).
    property string _focusReturnId: ""
    // A paste is waiting for the clipboard write, then for focus to return.
    property bool _pastePending: false
    property int _pasteSerial: 0
    property string _pasteTargetId: ""
    property string _pasteHandleId: ""

    function normalizeMode(value) {
        return value === "app" || value === "clipboard" ? value : "window"
    }

    // Both open paths must sample the focus target before the surface becomes
    // visible: the panel itself is focusable, so anything sampled afterwards is
    // already empty.
    function prepareOpen() {
        cancelPaste()
        _focusReturnId = WindowService.activeWindowId
    }

    function show(modeName) {
        prepareOpen()
        mode = normalizeMode(modeName)
        if (mode === "clipboard")
            ClipboardService.refresh()
        open = true
    }
    function hide() { open = false }
    function toggle(modeName) {
        const nextMode = normalizeMode(modeName)
        if (!open) {
            prepareOpen()
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
        if (!open)
            prepareOpen()
        const modes = ["window", "app", "clipboard"]
        mode = modes[(modes.indexOf(mode) + 1) % modes.length]
        if (mode === "clipboard")
            ClipboardService.refresh()
        open = true
    }
    function toggleViewMode() {
        viewMode = viewMode === "list" ? "grid" : "list"
    }

    function cancelPaste() {
        _pasteSerial++
        _pastePending = false
        focusPollTimer.stop()
        focusPollTimer.elapsed = 0
    }

    // The panel picked an entry. copyOnly stops after the clipboard write;
    // otherwise the chord is injected once the write settled and the previous
    // window has keyboard focus again. The item carries whichever store it came
    // from, so a pinned row takes the exact same path as a history row.
    function beginPaste(item, copyOnly) {
        cancelPaste()
        if (!item)
            return
        const target = WindowService.windowById(_focusReturnId)
        if (copyOnly === true || !ClipboardService.pasteEnabled || !target?.handleId) {
            ClipboardService.copyEntry(item)
            return
        }
        const serial = _pasteSerial
        _pasteTargetId = _focusReturnId
        _pasteHandleId = target.handleId
        _pastePending = true
        ClipboardService.copyEntry(item, function(ok) {
            if (serial !== root._pasteSerial)
                return
            // The platform only reports success after wl-copy exited, so this
            // is the "content is in place" edge.
            if (!ok || !root._pastePending) {
                root._pastePending = false
                return
            }
            focusPollTimer.elapsed = 0
            focusPollTimer.restart()
        })
    }

    function injectPaste() {
        // Recheck immediately before dispatch; KWin checks the same identity
        // against its actual keyboard focus when it receives this request.
        const target = WindowService.windowById(_pasteTargetId)
        if (open || !target || !target.handleId || target.handleId !== _pasteHandleId
                || WindowService.activeWindowId !== _pasteTargetId)
            return
        PlatformClient.request("input.paste", { expectedWindowId: _pasteHandleId }, function(response) {
            if (!response?.ok)
                console.warn("[QuickSearch] paste injection failed: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    // Poll only for the remembered target. Timeout, a closed target or a
    // different active application cancels injection; the content stays copied.
    Timer {
        id: focusPollTimer
        interval: 40
        repeat: true
        property int elapsed: 0
        onTriggered: {
            elapsed += interval
            const target = WindowService.windowById(root._pasteTargetId)
            const active = WindowService.activeWindowId
            if (!root._pastePending || root.open || !target
                    || (active && active !== root._pasteTargetId)
                    || elapsed >= 1200) {
                root.cancelPaste()
            } else if (active === root._pasteTargetId) {
                root.cancelPaste()
                root.injectPaste()
            }
        }
    }

    IpcHandler {
        target: "quicksearch"

        function show(mode: string): void { root.show(mode) }
        function hide(): void { root.hide() }
        function toggle(mode: string): void { root.toggle(mode) }
    }

    QuickSearchWindow {
        screen: root.targetScreen
        open: root.open && ScreenLifecycle.outputAvailable
            && root.targetScreen !== null
        mode: root.mode
        viewMode: root.viewMode
        onCloseRequested: root.hide()
        onModeCycleRequested: root.cycleMode()
        onViewModeToggleRequested: root.toggleViewMode()
        onPasteRequested: function (item, copyOnly) {
            root.beginPaste(item, copyOnly)
        }
    }
}
