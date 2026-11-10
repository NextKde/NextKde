import QtQuick
import qs.desktop.modules.common
import "WidgetLayout.mjs" as WidgetLayout

// Keep pointer coordinates in the scene: the handle itself moves as its card
// previews the snapped size. Local mouse deltas would jump between two sizes.
Item {
    id: handle
    objectName: "widget-resize-handle"
    width: 36
    height: 36
    property real cellSize: 180
    property real gap: 10
    property real cardWidth: parent.width
    property real cardHeight: parent.height
    property color ink: "white"
    property bool resizing: false
    property bool previewAllowed: true
    property int previewColumns: 1
    property int previewRows: 1
    // Widgets exist only at one or two cells per axis; the magnet never
    // previews a span the commit would reject.
    readonly property int maximumSpan: 2
    // The corner position the drag actually shows: the pointer, bent by the
    // magnetic mapping so the card is held near whole-cell sizes.
    property real previewWidth: 0
    property real previewHeight: 0
    // Grab feedback is decorative, so reduced-motion hosts switch it off.
    property bool animate: true
    property point startPoint: Qt.point(0, 0)
    property real startWidth: 0
    property real startHeight: 0
    signal committed(int columns, int rows)

    // Grabbing the corner is a physical hold: the grip acknowledges the press
    // before the card itself starts changing size. Frame-synchronised, so the
    // grip follows the display instead of Qt's fixed 16 ms spring step.
    MotionSpring {
        id: gripScale
        target: pointer.pressed ? 1.14 : 1.0
        enabled: handle.animate
        angularFrequency: AppearanceTokens.motion.widgetGripAngularFrequency
        dampingRatio: AppearanceTokens.motion.widgetGripDampingRatio
        epsilon: AppearanceTokens.motion.widgetGripEpsilon
    }
    FrameAnimation {
        running: gripScale.animating
        onTriggered: gripScale.advance(frameTime)
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: pointer.pressed ? "#a0000000" : "#66000000"
        scale: gripScale.value
    }
    BundledIcon {
        anchors.centerIn: parent
        name: "desktop.widget.resize"
        size: 16
        color: handle.ink
    }
    MouseArea {
        id: pointer
        objectName: "widget-resize-pointer"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SizeFDiagCursor
        preventStealing: true
        onPressed: function(mouse) {
            handle.startPoint = mapToItem(null, mouse.x, mouse.y)
            handle.startWidth = handle.cardWidth
            handle.startHeight = handle.cardHeight
            const span = WidgetLayout.snappedSpan(handle.startWidth, handle.startHeight,
                handle.cellSize, handle.gap)
            handle.previewColumns = span[0]
            handle.previewRows = span[1]
            handle.previewWidth = handle.startWidth
            handle.previewHeight = handle.startHeight
            handle.resizing = true
        }
        onPositionChanged: function(mouse) {
            if (!pressed) return
            // The pointer is mapped to the scene, so the preview keeps tracking
            // while the card's own spring animation moves this handle around.
            const point = mapToItem(null, mouse.x, mouse.y)
            const width = handle.startWidth + point.x - handle.startPoint.x
            const height = handle.startHeight + point.y - handle.startPoint.y
            const span = WidgetLayout.snappedSpan(width, height, handle.cellSize, handle.gap)
            handle.previewColumns = span[0]
            handle.previewRows = span[1]
            handle.previewWidth = WidgetLayout.magnetizedSize(width,
                handle.cellSize, handle.gap, handle.maximumSpan)
            handle.previewHeight = WidgetLayout.magnetizedSize(height,
                handle.cellSize, handle.gap, handle.maximumSpan)
        }
        onReleased: {
            if (handle.previewAllowed)
                handle.committed(handle.previewColumns, handle.previewRows)
            handle.resizing = false
        }
        onCanceled: handle.resizing = false
    }
}
