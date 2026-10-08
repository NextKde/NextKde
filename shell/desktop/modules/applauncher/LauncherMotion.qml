import QtQuick

// The backdrop has its own GUI-thread geometry timeline. Content keeps a
// fixed layout and a separate, pure-Animator render-thread timeline.
Item {
    id: motion

    required property Item target
    // Animation groups need an item/window context in addition to their
    // individual targets. This zero-sized helper draws nothing.
    parent: target.parent
    property real restingY: 24
    property int openDuration: 320
    property int closeDuration: 320
    property bool requestedOpen: false
    property bool mapped: false
    property bool settledOpen: false
    readonly property bool interactive: requestedOpen && settledOpen
    property real backdropProgress: 0
    property bool contentFinished: false
    property bool backdropFinished: false
    property real startY: restingY
    property real startOpacity: 0

    function captureStart() {
        // stop() writes the current render-thread values back to the item,
        // allowing a reversal to continue from the visible intermediate frame.
        animation.stop();
        backdropAnimation.stop();
        startY = mapped ? target.y : restingY;
        startOpacity = mapped ? target.opacity : 0;
    }

    function open() {
        captureStart();
        settledOpen = false;
        contentFinished = false;
        backdropFinished = false;
        // Qt must build the subtree before OpacityAnimator takes ownership.
        // A QML opacity of zero otherwise prunes its child paint nodes. The
        // animator applies startOpacity in the same render synchronization.
        target.scale = 1;
        target.opacity = 1;
        mapped = true;
        requestedOpen = true;
        configureJobs();
        backdropAnimation.start();
        animation.start();
    }

    function close() {
        captureStart();
        requestedOpen = false;
        settledOpen = false;
        contentFinished = false;
        backdropFinished = false;
        if (mapped) {
            configureJobs();
            backdropAnimation.start();
            animation.start();
        }
    }

    function configureJobs() {
        yJob.from = startY;
        yJob.to = requestedOpen ? 0 : restingY;
        yJob.duration = requestedOpen ? openDuration : closeDuration;
        opacityJob.from = startOpacity;
        opacityJob.to = requestedOpen ? 1 : 0;
        opacityJob.duration = requestedOpen ? Math.min(80, openDuration) : closeDuration;
        backdropAnimation.to = requestedOpen ? 1 : 0;
        backdropAnimation.duration = requestedOpen ? openDuration : closeDuration;
    }

    property ParallelAnimation animation: ParallelAnimation {
        YAnimator {
            id: yJob
            target: motion.target
            easing.type: Easing.OutCubic
        }
        OpacityAnimator {
            id: opacityJob
            target: motion.target
            // Reach full opacity early so tile motion stays visible while
            // the backdrop continues expanding.
            easing.type: Easing.OutCubic
        }
        onFinished: {
            motion.contentFinished = true;
            motion.finishIfSettled();
        }
    }

    // Keep this outside the Animator group; mixing NumberAnimation into that
    // group would prevent the content timeline from remaining render-thread-only.
    property NumberAnimation backdropAnimation: NumberAnimation {
        target: motion
        property: "backdropProgress"
        easing.type: Easing.OutCubic
        onFinished: {
            motion.backdropFinished = true;
            motion.finishIfSettled();
        }
    }

    function finishIfSettled() {
        if (!contentFinished || !backdropFinished)
            return;
        settledOpen = requestedOpen;
        if (!requestedOpen) {
            mapped = false;
        }
    }
}
