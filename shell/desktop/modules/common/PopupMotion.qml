import QtQuick

// Shared macOS-style popup motion. Owners keep their PopupWindow mapped while
// `mapped` is true and gate all input with `interactive`.
QtObject {
    id: motion

    property real progress: 0
    property bool requestedOpen: false
    property bool mapped: false
    readonly property bool interactive: requestedOpen && progress > 0.01
    signal closed()

    function open() {
        requestedOpen = true
        mapped = true
        animateTo(1)
    }

    function close() {
        requestedOpen = false
        if (!mapped || progress <= 0) {
            progress = 0
            mapped = false
            closed()
            return
        }
        animateTo(0)
    }

    function reset() {
        animation.stop()
        requestedOpen = false
        mapped = false
        progress = 0
    }

    function animateTo(targetProgress) {
        animation.stop()
        animation.from = progress
        animation.to = targetProgress
        const fullDuration = targetProgress > progress
            ? AppearanceTokens.motion.popupOpenDuration
            : AppearanceTokens.motion.popupCloseDuration
        animation.duration = Math.max(1,
            Math.round(fullDuration * Math.abs(targetProgress - progress)))
        animation.easing.type = targetProgress > progress
            ? Easing.OutCubic : Easing.InCubic
        animation.start()
    }

    property NumberAnimation animation: NumberAnimation {
        target: motion
        property: "progress"
        onFinished: {
            if (!motion.requestedOpen && motion.progress <= 0) {
                motion.mapped = false
                motion.closed()
            }
        }
    }
}
