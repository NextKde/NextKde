import QtQuick
import "../../../Kos/Ui/foundation" as Foundation

// Shared macOS-style popup motion. Owners keep their PopupWindow mapped while
// `mapped` is true and gate all input with `interactive`.
QtObject {
    id: motion

    // The fade stays bounded; geometry retains velocity on reversal.
    property real progress: 0
    readonly property real geometryProgress: geometry.value
    property bool reduceMotion: AppearanceConfigService.reduceMotion
    property real springResponse: 0.28
    property bool requestedOpen: false
    property bool mapped: false
    property int openDuration: AppearanceTokens.motion.popupOpenDuration
    property int closeDuration: AppearanceTokens.motion.popupCloseDuration
    property int openEasing: AppearanceTokens.motion.enterCurve
    property int closeEasing: AppearanceTokens.motion.exitCurve
    readonly property bool interactive: requestedOpen && progress > 0.01
    signal closed()

    function open() {
        mapped = true
        requestedOpen = true
        animateTo(1)
    }

    function close() {
        requestedOpen = false
        if (!mapped || progress <= 0) {
            animation.stop()
            progress = 0
            mapped = false
            geometry.snap()
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
        geometry.snap()
    }

    property Foundation.SpringMotion geometry: Foundation.SpringMotion {
        target: motion.requestedOpen ? 1 : 0
        response: motion.springResponse
        enabled: motion.mapped && !motion.reduceMotion
            && (motion.requestedOpen ? motion.openDuration : motion.closeDuration) > 0
    }

    onReduceMotionChanged: {
        if (reduceMotion && mapped) {
            geometry.snap()
            animateTo(requestedOpen ? 1 : 0)
        }
    }

    function animateTo(targetProgress) {
        animation.stop()
        animation.from = progress
        animation.to = targetProgress
        const fullDuration = reduceMotion ? 0 : (targetProgress > progress
            ? openDuration : closeDuration)
        if (fullDuration <= 0) {
            progress = targetProgress
            geometry.snap()
            if (!requestedOpen && mapped) {
                mapped = false
                closed()
            }
            return
        }
        animation.duration = Math.max(1,
            Math.round(fullDuration * Math.abs(targetProgress - progress)))
        animation.easing.type = targetProgress > progress
            ? openEasing : closeEasing
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
