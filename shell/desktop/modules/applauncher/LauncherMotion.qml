import QtQuick

// Native mode sends only an endpoint request: KWin advances one surface timeline
// and reports completion. Older compositors use one whole-content Animator group.
Item {
    id: motion
    required property Item target
    required property var surface
    parent: target.parent
    property bool requestedOpen: false
    property bool mapped: false
    property bool settledOpen: false
    readonly property bool interactive: requestedOpen && settledOpen
    readonly property bool compositorSupported: surface.compositorRevealEnabled
        && surface.compositorRevealSupported
    property real glassOpacity: 0
    property bool contentFinished: false
    property bool glassFinished: false

    function prepare() {
        contentAnimation.stop();
        glassFade.stop();
        settledOpen = false;
        contentFinished = false;
        glassFinished = false;
    }

    function open() {
        prepare();
        mapped = true;
        requestedOpen = true;
        if (!compositorSupported)
            startFallback();
    }

    function close() {
        prepare();
        requestedOpen = false;
        if (mapped && !compositorSupported)
            startFallback();
    }

    function startFallback() {
        scaleJob.from = target.scale;
        scaleJob.to = requestedOpen ? 1 : 0.8;
        opacityJob.from = target.opacity;
        opacityJob.to = requestedOpen ? 1 : 0;
        if (requestedOpen) target.opacity = 1;
        glassFade.from = glassOpacity;
        glassFade.to = requestedOpen ? 1 : 0;
        contentAnimation.start();
        glassFade.start();
    }

    function finish(opened) {
        if (opened !== requestedOpen)
            return;
        settledOpen = opened;
        if (!opened) mapped = false;
    }

    function finishCompositorReveal(opened) {
        if (compositorSupported) finish(opened);
    }

    function finishFallback() {
        if (!compositorSupported && contentFinished && glassFinished)
            finish(requestedOpen);
    }

    onCompositorSupportedChanged: {
        if (compositorSupported) {
            // The protocol can become available after creating the surface.
            // Keep client content fully drawn; KWin now owns its transform.
            prepare();
            target.scale = 1;
            target.opacity = 1;
        } else if (mapped) {
            prepare();
            startFallback();
        }
    }

    property ParallelAnimation contentAnimation: ParallelAnimation {
        ScaleAnimator { id: scaleJob; target: motion.target; duration: 320; easing.type: Easing.OutCubic }
        OpacityAnimator { id: opacityJob; target: motion.target; duration: 320; easing.type: Easing.OutCubic }
        onFinished: {
            motion.contentFinished = true;
            motion.finishFallback();
        }
    }
    property NumberAnimation glassFade: NumberAnimation {
        target: motion
        property: "glassOpacity"
        duration: 320
        easing.type: Easing.OutCubic
        onFinished: {
            motion.glassFinished = true;
            motion.finishFallback();
        }
    }
}
