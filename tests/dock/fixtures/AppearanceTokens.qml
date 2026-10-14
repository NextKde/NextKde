pragma Singleton
import QtQuick

// Only decorative properties used by the real DockAnimation singleton.
// Its auto-hide timings and easing remain the shipping implementation.
QtObject {
    readonly property QtObject motion: QtObject {
        readonly property int fastDuration: 120
        readonly property int normalDuration: 180
        readonly property int standardEasing: Easing.OutCubic
    }
    readonly property QtObject dock: QtObject {
        readonly property real hoverScale: 1.1
    }
}
