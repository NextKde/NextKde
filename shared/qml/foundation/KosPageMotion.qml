import QtQuick

QtObject {
    id: motion

    property var page: ""
    property var displayedPage: ""
    property bool enabled: true
    property real progress: 1
    property int exitDuration: AppTheme.motionFast
    property int enterDuration: AppTheme.motionNormal
    // Crossfade mode: on a page change the new page becomes `displayedPage`
    // immediately and `progress` animates 0→1 once. The previous page is kept
    // in `outgoingPage` for the duration of the animation so the host can fade
    // it out in parallel instead of running a serial exit-then-enter that
    // leaves a visible empty frame between the two pages.
    property bool crossfade: false
    readonly property var outgoingPage: _outgoingPage
    property var _outgoingPage: ""
    readonly property bool interactive: enabled && page === displayedPage
        && progress > 0.5

    function reset(nextPage) {
        animation.stop()
        _outgoingPage = ""
        displayedPage = nextPage
        progress = 1
    }

    function reconcile() {
        animation.stop()
        if (!enabled)
            return
        if (crossfade) {
            // The incoming page is displayed from the first frame; the
            // outgoing one keeps rendering through `outgoingPage` and fades
            // with (1 - progress). Keeping `progress` continuous across a
            // re-targeted navigation means a page interrupted mid-fade hands
            // its exact visibility to the next transition -- no snap, no
            // empty frame.
            if (page !== displayedPage) {
                _outgoingPage = displayedPage
                displayedPage = page
                if (progress >= 1)
                    progress = 0
            }
            if (progress === 1) {
                _outgoingPage = ""
                return
            }
            animation.from = progress
            animation.to = 1
            animation.duration = Math.max(1,
                Math.round(enterDuration * (1 - progress)))
            animation.easing.type = Easing.OutCubic
            animation.start()
            return
        }
        const target = page === displayedPage ? 1 : 0
        if (progress === target) {
            if (target === 0) {
                displayedPage = page
                reconcile()
            }
            return
        }
        animation.from = progress
        animation.to = target
        animation.duration = Math.max(1, Math.round(
            (target === 1 ? enterDuration : exitDuration)
            * Math.abs(target - progress)))
        animation.easing.type = target === 1 ? Easing.OutCubic : Easing.InCubic
        animation.start()
    }

    onPageChanged: reconcile()
    onEnabledChanged: reconcile()
    Component.onCompleted: reset(page)

    property NumberAnimation animation: NumberAnimation {
        target: motion
        property: "progress"
        onFinished: motion.reconcile()
    }
}
