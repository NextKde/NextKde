import QtQuick

// Keep the outgoing model until it is transparent. The caller replaces the
// cards on commit, then both QML and compositor cards follow the same progress.
QtObject {
    id: motion

    property string desktopId: ""
    property bool enabled: true
    property bool hasCards: false
    property bool offscreen: false
    property bool rightSide: false
    property bool blocked: false
    property real progress: 1
    readonly property real offset: (rightSide ? 24 : -24) * (1 - progress)
    readonly property bool active: _phase !== 0
    property string _displayedDesktopId: ""
    property string _pendingDesktopId: ""
    property int _phase: 0 // 0 idle, 1 exiting, 2 entering
    property bool _ready: false

    signal commit()

    function deferSync(nextDesktopId: string): bool {
        if (!_ready || !enabled || _displayedDesktopId === "") {
            _displayedDesktopId = nextDesktopId
            return false
        }
        _pendingDesktopId = nextDesktopId
        if (_phase === 1)
            return true
        if (nextDesktopId === _displayedDesktopId)
            return false
        _startExit()
        return true
    }

    function _startExit() {
        _animation.stop()
        _phase = 1
        if (!hasCards || offscreen || blocked || progress <= 0) {
            progress = 0
            _commitTimer.restart()
        } else {
            _animation.to = 0
            _animation.duration = 120
            _animation.start()
        }
    }

    function _commitDesktop() {
        if (_phase !== 1 || !enabled)
            return
        _displayedDesktopId = _pendingDesktopId
        _phase = 2
        commit()
        // A commit may synchronously disable the sidebar or request another
        // desktop. Do not restart an entrance over that newer state.
        if (_phase !== 2 || !enabled)
            return
        _startEntrance()
    }

    function _startEntrance() {
        if (blocked || !enabled || _phase !== 2)
            return
        _animation.to = 1
        _animation.duration = 260
        _animation.start()
    }

    function _reset() {
        _animation.stop()
        _commitTimer.stop()
        _displayedDesktopId = desktopId
        _pendingDesktopId = desktopId
        _phase = 0
        progress = 1
        if (_ready)
            commit()
    }

    onDesktopIdChanged: {
        if (_ready && !deferSync(desktopId))
            commit()
    }
    onEnabledChanged: if (_ready) _reset()
    onBlockedChanged: {
        if (!_ready || !active)
            return
        if (blocked) {
            _animation.stop()
            progress = 0
            if (_phase === 1)
                _commitTimer.restart()
        } else {
            _startEntrance()
        }
    }
    Component.onCompleted: {
        _displayedDesktopId = desktopId
        _pendingDesktopId = desktopId
        _ready = true
    }

    property NumberAnimation _animation: NumberAnimation {
        target: motion
        property: "progress"
        easing.type: Easing.OutCubic
        onFinished: {
            if (motion._phase === 1)
                motion._commitTimer.restart()
            else if (motion._phase === 2)
                motion._phase = 0
        }
    }
    // Give the live-card publisher a frame to send fade=0 before old delegates
    // disappear. Otherwise the compositor's missing-card grace period keeps
    // their last nonzero alpha on screen after the model has been replaced.
    property Timer _commitTimer: Timer {
        interval: 16
        onTriggered: motion._commitDesktop()
    }
}
