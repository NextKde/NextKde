import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform
import "ClipboardPlacement.mjs" as ClipboardPlacement

// Global controller for search and clipboard history. Clipboard placement uses
// a pre-focus snapshot on its containing output; other modes use the main one.
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
    property var clipboardAnchor: null
    property bool _opening: false
    property bool _anchorResolved: false
    property int _openSerial: 0
    readonly property var targetScreen: mode === "clipboard"
        ? ClipboardPlacement.screenForAnchor(ScreenLifecycle.usableScreens, clipboardAnchor,
            ScreenLifecycle.activeScreen) : ScreenLifecycle.activeScreen

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
        clipboardAnchor = null
        _anchorResolved = false
        _focusReturnId = WindowService.activeWindowId
    }

    function show(modeName) {
        if (!open && !_opening)
            prepareOpen()
        mode = normalizeMode(modeName)
        if (mode === "clipboard") {
            ClipboardService.refresh()
            locateClipboard()
        } else {
            cancelOpen()
            open = true
        }
    }
    function cancelOpen() {
        _openSerial++
        _opening = false
        anchorTimeout.stop()
    }
    function hide() {
        cancelOpen()
        open = false
    }
    function locateClipboard() {
        // Repeated show() while already open must not replace the captured
        // caret with the panel's own field or follow subsequent mouse motion.
        if (open && _anchorResolved)
            return
        cancelOpen()
        clipboardAnchor = null
        _opening = true
        const serial = _openSerial
        const target = WindowService.windowById(_focusReturnId)
        anchorTimeout.restart()
        PlatformClient.request("input.clipboard-anchor",
            { expectedWindowId: target?.handleId || "", serial: serial }, function(response) {
                if (!root._opening || serial !== root._openSerial || root.mode !== "clipboard")
                    return
                anchorTimeout.stop()
                root.clipboardAnchor = response?.ok && ClipboardPlacement.validAnchor(response.result)
                    ? response.result : null
                root._opening = false
                root._anchorResolved = true
                root.open = true
            })
    }
    function toggle(modeName) {
        const nextMode = normalizeMode(modeName)
        if ((open || _opening) && mode === nextMode)
            hide()
        else
            show(nextMode)
    }
    function cycleMode() {
        const modes = ["window", "app", "clipboard"]
        show(modes[(modes.indexOf(mode) + 1) % modes.length])
    }
    function toggleViewMode() {
        viewMode = viewMode === "list" ? "grid" : "list"
    }

    // A missing/older bridge keeps the old centered placement. Never let a
    // stalled request block the shortcut or a late reply reopen a closed panel.
    Timer {
        id: anchorTimeout
        interval: 180
        onTriggered: {
            root.cancelOpen()
            root._anchorResolved = true
            root.open = true
        }
    }

    Connections {
        target: ScreenLifecycle
        function onOutputAvailableChanged() {
            if (!ScreenLifecycle.outputAvailable)
                root.hide()
        }
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
        clipboardAnchor: root.clipboardAnchor
        onCloseRequested: root.hide()
        onModeCycleRequested: root.cycleMode()
        onViewModeToggleRequested: root.toggleViewMode()
        onPasteRequested: function (item, copyOnly) {
            root.beginPaste(item, copyOnly)
        }
    }
}
