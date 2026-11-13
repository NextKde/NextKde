import QtQuick

// A self-clocked channel for interruptible UI geometry. Changing target keeps
// both position and velocity; colour and opacity use their own short fades.
QtObject {
    id: motion

    property real target: 0
    property bool enabled: true
    // Natural period in seconds, not a fixed animation deadline.
    property real response: 0.28
    property real dampingRatio: 1.0
    property real epsilon: 0.001
    readonly property real value: spring.value
    readonly property real velocity: spring.velocity
    readonly property bool animating: spring.animating

    function snap() { spring.snap() }

    property MotionSpring spring: MotionSpring {
        target: motion.target
        enabled: motion.enabled
        angularFrequency: 2 * Math.PI / Math.max(0.01, motion.response)
        dampingRatio: motion.dampingRatio
        epsilon: motion.epsilon
    }
    property FrameAnimation clock: FrameAnimation {
        running: spring.animating
        onTriggered: spring.advance(frameTime)
    }
}
