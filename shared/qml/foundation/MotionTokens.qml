import QtQuick

// Ordinary UI transitions only. Physical response, loops and business timers
// keep their own clocks; see docs/MotionTokens.zh-CN.md.
QtObject {
    id: motion
    property bool isMaterial: false
    readonly property int enterCurve: isMaterial ? Easing.OutQuart : Easing.OutCubic
    readonly property int exitCurve: isMaterial ? Easing.InQuart : Easing.InCubic
    readonly property int settleCurve: isMaterial ? Easing.InOutQuart : Easing.InOutCubic

    readonly property QtObject instant: QtObject {
        readonly property int duration: 100
        readonly property int enterCurve: motion.enterCurve
        readonly property int exitCurve: motion.exitCurve
    }
    readonly property QtObject fast: QtObject {
        readonly property int duration: 120
        readonly property int enterCurve: motion.enterCurve
        readonly property int exitCurve: motion.exitCurve
    }
    readonly property QtObject base: QtObject {
        readonly property int duration: 160
        readonly property int enterCurve: motion.enterCurve
        readonly property int exitCurve: motion.exitCurve
    }
    readonly property QtObject slow: QtObject {
        readonly property int duration: 220
        readonly property int enterCurve: motion.enterCurve
        readonly property int exitCurve: motion.exitCurve
    }
    readonly property QtObject page: QtObject {
        readonly property int duration: 300
        readonly property int enterCurve: motion.enterCurve
        readonly property int exitCurve: motion.exitCurve
    }
}
