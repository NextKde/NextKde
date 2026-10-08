import QtQuick

Item {
    id: root
    required property int index
    required property bool opened
    property real centerX: 0
    property real centerY: 0
    readonly property real offsetX: Math.max(-32, Math.min(32, (x + 32 - centerX) * 0.2))
    readonly property real offsetY: Math.max(-24, Math.min(24, (y + 32 - centerY) * 0.2))
    readonly property alias visualItem: visual
    readonly property bool animating: motion.running
    property bool ready: false
    width: 64
    height: 64

    function animateVisual() {
        // Stopping an Animator writes its current rendered value back, so
        // reversal continues from the frame the user was seeing.
        motion.stop();
        // Set endpoints explicitly: onOpenedChanged can run before bindings
        // on Animator.to have observed the new opened value.
        xJob.from = visual.x;
        xJob.to = opened ? 0 : -offsetX;
        yJob.from = visual.y;
        yJob.to = opened ? 0 : -offsetY;
        scaleJob.from = visual.scale;
        scaleJob.to = opened ? 1 : 0.8;
        opacityJob.from = visual.opacity;
        opacityJob.to = opened ? 1 : 0;
        // Build the paint subtree before the render-thread opacity job starts.
        if (opened)
            visual.opacity = 1;
        motion.start();
    }
    onOpenedChanged: if (ready) animateVisual()
    Component.onCompleted: {
        ready = true;
        if (opened) animateVisual();
    }

    Item {
        id: visual
        width: 64; height: 64
        x: -root.offsetX
        y: -root.offsetY
        scale: 0.8
        opacity: 0
        transformOrigin: Item.Center
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Qt.hsla((root.index % 10) / 10, 0.58, 0.53, 1)
            Text {
                anchors.centerIn: parent
                text: root.index + 1
                color: "white"
                font.pixelSize: 22
                font.weight: Font.Medium
            }
        }
    }

    property ParallelAnimation motion: ParallelAnimation {
        XAnimator {
            id: xJob
            target: visual
            duration: 300; easing.type: Easing.OutCubic
        }
        YAnimator {
            id: yJob
            target: visual
            duration: 300; easing.type: Easing.OutCubic
        }
        ScaleAnimator {
            id: scaleJob
            target: visual
            duration: 300; easing.type: Easing.OutCubic
        }
        OpacityAnimator {
            id: opacityJob
            target: visual
            duration: 200; easing.type: Easing.OutCubic
        }
    }
}
