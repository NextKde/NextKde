import QtQuick
import "MotionSpring.mjs" as Physics

// One channel of a frame-synchronised spring.
//
// The owner keeps a single FrameAnimation and calls advance(frameTime) for
// every channel it owns, so several properties move on one frame callback and
// an idle channel costs nothing (its host's FrameAnimation stops as soon as
// every channel has settled).
//
// The parameters are NOT Qt's SpringAnimation units. angularFrequency is in
// rad/s and dampingRatio is the dimensionless ratio: 0 is undamped, 1 is
// critically damped. The defaults are the fitted equivalent of Qt's
// SpringAnimation (spring 3.5, damping 0.30), which the desktop reviewed.
QtObject {
    id: spring

    // Where the spring is heading.
    property real target: 0
    // Natural frequency in rad/s, independent of the display refresh rate.
    property real angularFrequency: 18.25
    // Dimensionless damping: <1 overshoots, 1 is critically damped.
    property real dampingRatio: 0.71
    // Settle distance in the channel's unit, in pixels for geometry.
    property real epsilon: 0.25
    // While follow is true the value tracks the target one-to-one -- that is
    // how a held pointer moves a card. Velocity is still measured, so a
    // release hands its momentum to the spring instead of restarting at rest.
    property bool follow: false
    // Reduced motion, or a form that does not animate: snap to the target.
    property bool enabled: true

    // Spring state. Read `value` for display; advance() is called by the host.
    property real velocity: 0
    property real animatedValue: 0

    readonly property bool settled: Math.abs(target - animatedValue) <= epsilon
        && Math.abs(velocity) <= epsilon * Math.max(angularFrequency, 1)
    readonly property bool animating: enabled && (follow || !settled)
    readonly property real value: (!enabled || follow) ? target : animatedValue

    onTargetChanged: {
        if (!enabled) {
            animatedValue = target
            velocity = 0
        }
    }
    onEnabledChanged: {
        if (!enabled) {
            animatedValue = target
            velocity = 0
        }
    }
    // A release turns follow off with the pointer's last velocity still in
    // hand; nothing else is needed here, advance() springs from that state.

    // Advance by the time the compositor reported for this frame. The host
    // passes FrameAnimation.frameTime (seconds).
    function advance(deltaSeconds: real) {
        if (!enabled) {
            animatedValue = target
            velocity = 0
            return
        }
        const dt = Number(deltaSeconds) || 0
        if (follow) {
            // Track the pointer exactly; remember how fast it was moving so the
            // release can carry that momentum into the spring.
            if (dt > 0)
                velocity = Math.max(-20000, Math.min(20000, (target - animatedValue) / dt))
            animatedValue = target
            return
        }
        const next = Physics.step(animatedValue, velocity, target, dt,
            angularFrequency, dampingRatio, epsilon)
        animatedValue = next.value
        velocity = next.velocity
    }

    function snap() {
        animatedValue = target
        velocity = 0
    }

    Component.onCompleted: snap()
}
