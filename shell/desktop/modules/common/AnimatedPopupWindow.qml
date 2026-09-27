import QtQuick
import Quickshell

PopupWindow {
    id: popup

    property bool requestedOpen: false
    property bool animationEnabled: true
    property int motionOrigin: Item.Top
    readonly property real revealProgress: animationEnabled ? motion.progress : 1
    readonly property bool interactive: effectiveOpen
        && (!animationEnabled || motion.interactive)
    readonly property bool effectiveOpen: requestedOpen && ScreenLifecycle.outputAvailable

    visible: motion.mapped
    contentItem.opacity: revealProgress
    contentItem.scale: AppearanceTokens.motion.popupStartScale
        + (1 - AppearanceTokens.motion.popupStartScale) * revealProgress
    contentItem.transformOrigin: motionOrigin
    contentItem.enabled: interactive
    mask: interactive ? null : emptyInputRegion

    function show() { requestedOpen = true }
    function hide() { requestedOpen = false }
    function setDockPopupVisible(shouldOpen) { requestedOpen = shouldOpen }
    function dismissDockPopupImmediately() {
        requestedOpen = false
        motion.reset()
    }

    onEffectiveOpenChanged: {
        if (effectiveOpen)
            motion.open()
        else if (!ScreenLifecycle.outputAvailable)
            motion.reset()
        else
            motion.close()
    }

    PopupMotion {
        id: motion
        openDuration: popup.animationEnabled ? AppearanceTokens.motion.popupOpenDuration : 0
        closeDuration: popup.animationEnabled ? AppearanceTokens.motion.popupCloseDuration : 0
    }
    Region { id: emptyInputRegion }
}
