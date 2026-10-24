import QtQuick

// Keep the tile pose and opacity on the same GUI-thread animation timeline as
// the glass. The previous render-thread Animators used an opaque prewarm that
// could expose a tile for a frame before taking over (or when reversing).
// The GridView cell and all layout inside the target remain fixed.
Item {
    id: motion
    required property Item target
    required property bool opened
    required property var controller
    property bool counted: false
    property bool animateOnCompleted: true
    property real offsetX: 0
    property real offsetY: 0
    property bool ready: false
    property real progress: 0
    property real fadeProgress: 0
    parent: target.parent

    Binding { target: motion.target; property: "x"; value: -motion.offsetX * (1 - motion.progress) }
    Binding { target: motion.target; property: "y"; value: -motion.offsetY * (1 - motion.progress) }
    Binding { target: motion.target; property: "scale"; value: 0.8 + 0.2 * motion.progress }
    Binding { target: motion.target; property: "opacity"; value: motion.fadeProgress }

    function snap() {
        animation.stop();
        progress = opened ? 1 : 0;
        fadeProgress = opened ? 1 : 0;
        release();
    }
    function animate() {
        // Neighbor pages stay preloaded for paging, but their hidden tiles
        // must not run animations or hold up the open controller.
        if (!target.visible) {
            snap();
            return;
        }
        animation.stop();
        const destination = opened ? 1 : 0;
        poseJob.from = progress;
        poseJob.to = destination;
        poseJob.duration = Math.max(1, Math.round(300 * Math.abs(destination - progress)));
        opacityJob.from = fadeProgress;
        opacityJob.to = destination;
        opacityJob.duration = Math.max(1, Math.round(200 * Math.abs(destination - fadeProgress)));
        if (!counted) {
            counted = true;
            controller.iconStarted();
        }
        animation.start();
    }
    onOpenedChanged: if (ready) animate()
    Connections {
        target: motion.target
        function onVisibleChanged() {
            if (motion.ready && !motion.target.visible)
                motion.snap();
        }
    }
    Component.onCompleted: {
        ready = true;
        if (opened && animateOnCompleted) {
            animate();
        } else {
            snap();
        }
    }
    function release() {
        if (counted) {
            counted = false;
            if (controller) controller.iconFinished();
        }
    }
    Component.onDestruction: release()
    property ParallelAnimation animation: ParallelAnimation {
        onFinished: motion.release()
        NumberAnimation { id: poseJob; target: motion; property: "progress"; easing.type: Easing.OutCubic }
        NumberAnimation { id: opacityJob; target: motion; property: "fadeProgress"; easing.type: Easing.OutCubic }
    }
}
