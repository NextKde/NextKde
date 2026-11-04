import QtQuick

// Keep the displayed desktop's cards in place until KWin finishes switching.
// Commit the latest model once; desktop navigation never changes opacity/offset.
QtObject {
    id: transition

    property string desktopId: ""
    property bool enabled: true
    property bool blocked: false
    readonly property bool active: enabled && (blocked || _holding)
    property string _displayedDesktopId: ""
    property string _pendingDesktopId: ""
    property bool _holding: false
    property bool _ready: false

    signal commit()

    function deferSync(nextDesktopId: string): bool {
        _pendingDesktopId = nextDesktopId
        if (!_ready || !enabled || _displayedDesktopId === "") {
            _displayedDesktopId = nextDesktopId
            return false
        }
        if (blocked) {
            _holding = true
            return true
        }
        if (_holding)
            return true
        if (nextDesktopId === _displayedDesktopId)
            return false
        _holding = true
        _commitTimer.restart()
        return true
    }

    function _reset() {
        _commitTimer.stop()
        _holding = false
        _displayedDesktopId = desktopId
        _pendingDesktopId = desktopId
        if (_ready)
            commit()
    }

    onDesktopIdChanged: {
        if (_ready && !deferSync(desktopId))
            commit()
    }
    onEnabledChanged: if (_ready) _reset()
    onBlockedChanged: {
        if (!_ready || !enabled)
            return
        _pendingDesktopId = desktopId
        _holding = true
        if (blocked)
            _commitTimer.stop()
        else
            _commitTimer.restart()
    }
    Component.onCompleted: {
        _displayedDesktopId = desktopId
        _pendingDesktopId = desktopId
        _ready = true
    }

    property Timer _commitTimer: Timer {
        interval: 0
        onTriggered: {
            if (!transition.enabled || transition.blocked)
                return
            transition._displayedDesktopId = transition._pendingDesktopId
            transition._holding = false
            transition.commit()
        }
    }
}
