pragma Singleton
import QtQuick

// Only decorative properties used by the real DockAnimation singleton.
// Its auto-hide timings and easing remain the shipping implementation.
QtObject {
    readonly property MotionTokens motion: MotionTokens {
        readonly property int fastDuration: fast.duration
        readonly property int normalDuration: slow.duration
        readonly property int standardEasing: enterCurve
    }
    readonly property QtObject dock: QtObject {
        readonly property real hoverScale: 1.1
    }
}
