import QtQuick

// Apply the prototype's transform-only motion to a real application tile.
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
    parent: target.parent

    function snap() {
        animation.stop();
        target.x = opened ? 0 : -offsetX;
        target.y = opened ? 0 : -offsetY;
        target.scale = opened ? 1 : 0.8;
        target.opacity = opened ? 1 : 0;
        release();
    }
    function animate() {
        // Neighbor pages stay preloaded for paging, but their hidden tiles
        // must not submit four Animator jobs or hold up the open controller.
        if (!target.visible) {
            snap();
            return;
        }
        const wasRunning = animation.running;
        animation.stop();
        // GridView can position a delegate after Component.onCompleted.
        // Resolve the contracted pose again once its final cell is known.
        if (opened && !wasRunning && target.opacity <= 0.0001) {
            target.x = -offsetX;
            target.y = -offsetY;
            target.scale = 0.8;
        }
        xJob.from = target.x;
        xJob.to = opened ? 0 : -offsetX;
        yJob.from = target.y;
        yJob.to = opened ? 0 : -offsetY;
        scaleJob.from = target.scale;
        scaleJob.to = opened ? 1 : 0.8;
        opacityJob.from = target.opacity;
        opacityJob.to = opened ? 1 : 0;
        if (opened) target.opacity = 1;
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
            target.x = -offsetX;
            target.y = -offsetY;
            target.scale = 0.8;
            target.opacity = 0;
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
        XAnimator { id: xJob; target: motion.target; duration: 300; easing.type: Easing.OutCubic }
        YAnimator { id: yJob; target: motion.target; duration: 300; easing.type: Easing.OutCubic }
        ScaleAnimator { id: scaleJob; target: motion.target; duration: 300; easing.type: Easing.OutCubic }
        OpacityAnimator { id: opacityJob; target: motion.target; duration: 200; easing.type: Easing.OutCubic }
    }
}
