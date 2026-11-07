import QtQuick
import qs.desktop.modules.common

// Keep the last complete panel alive until its exit finishes. Kimpanel sends
// content, visibility and caret updates separately; commit a settled snapshot.
QtObject {
    id: presentation

    property var state: ({ candidates: [], lookupVisible: false,
        preeditVisible: false, auxVisible: false, preeditText: "", auxText: "" })
    property var anchor: null
    readonly property bool isOnlyTip: !state.lookupVisible || state.candidates.length === 0
    readonly property bool mapped: motion.mapped
    readonly property bool interactive: motion.interactive
    readonly property real progress: motion.progress
    readonly property real scale: (isOnlyTip ? 0.92 : 0.975)
        + (isOnlyTip ? 0.08 : 0.025) * progress

    property var _pendingState: ({})
    property var _pendingAnchor: null
    property bool _pendingTarget: false

    function update(nextState, nextAnchor, onTargetScreen) {
        _pendingState = nextState
        _pendingAnchor = nextAnchor
        _pendingTarget = onTargetScreen
        Qt.callLater(commit)
    }

    function commit() {
        const next = _pendingState
        const hasContent = (next.lookupVisible && next.candidates?.length > 0)
            || (next.preeditVisible && String(next.preeditText || "").trim().length > 0)
            || (next.auxVisible && String(next.auxText || "").trim().length > 0)
        if (!_pendingTarget || !next.enabled || !next.visible || !hasContent) {
            // Do not replace state/anchor with the empty or moved live panel.
            if (motion.requestedOpen)
                motion.close()
            return
        }

        state = next
        anchor = _pendingAnchor
        // Typing, paging and caret updates must not restart the entrance.
        if (!motion.requestedOpen)
            motion.open()
    }

    property PopupMotion motion: PopupMotion {
        openDuration: presentation.isOnlyTip ? 180 : 150
        closeDuration: presentation.isOnlyTip ? 140 : 120
        openEasing: Easing.OutCubic
        closeEasing: Easing.InOutCubic
    }
}
