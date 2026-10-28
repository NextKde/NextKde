import QtQuick
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
    property point startPoint: Qt.point(0, 0)
    property real startWidth: 0
    property real startHeight: 0
    signal committed(int columns, int rows)

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: pointer.pressed ? "#a0000000" : "#66000000"
    }
    Repeater {
        model: 2
        delegate: Rectangle {
            required property int index
            x: 13 + index * 6
            y: 19 + index * 3
            width: 15 - index * 6
            height: 2
            radius: 1
            rotation: -45
            color: handle.ink
        }
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
            handle.resizing = true
        }
        onPositionChanged: function(mouse) {
            if (!pressed) return
            const point = mapToItem(null, mouse.x, mouse.y)
            const span = WidgetLayout.snappedSpan(
                handle.startWidth + point.x - handle.startPoint.x,
                handle.startHeight + point.y - handle.startPoint.y,
                handle.cellSize, handle.gap)
            handle.previewColumns = span[0]
            handle.previewRows = span[1]
        }
        onReleased: {
            if (handle.previewAllowed)
                handle.committed(handle.previewColumns, handle.previewRows)
            handle.resizing = false
        }
        onCanceled: handle.resizing = false
    }
}
