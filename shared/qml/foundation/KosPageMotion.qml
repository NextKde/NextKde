import QtQuick

QtObject {
    id: motion

    property var page: ""
    property var displayedPage: ""
    property bool enabled: true
    property real progress: 1
    property int exitDuration: AppTheme.motionFast
    property int enterDuration: AppTheme.motionNormal
    readonly property bool interactive: enabled && page === displayedPage
        && progress > 0.5

    function reset(nextPage) {
        animation.stop()
        displayedPage = nextPage
        progress = 1
    }

    function reconcile() {
        animation.stop()
        if (!enabled)
            return
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
