import QtQuick
import QtQuick.Window

Item {
    id: root
    required property var targetWindow
    anchors.fill: parent
    z: 100
    enabled: targetWindow.visibility === Window.Windowed
    Repeater {
        model: [Qt.TopEdge, Qt.BottomEdge, Qt.LeftEdge, Qt.RightEdge,
                Qt.TopEdge | Qt.LeftEdge, Qt.TopEdge | Qt.RightEdge,
                Qt.BottomEdge | Qt.LeftEdge, Qt.BottomEdge | Qt.RightEdge]
        delegate: MouseArea {
            required property int modelData
            readonly property bool leftEdge: !!(modelData & Qt.LeftEdge)
            readonly property bool rightEdge: !!(modelData & Qt.RightEdge)
            readonly property bool topEdge: !!(modelData & Qt.TopEdge)
            readonly property bool bottomEdge: !!(modelData & Qt.BottomEdge)
            readonly property bool corner: (leftEdge || rightEdge) && (topEdge || bottomEdge)
            x: rightEdge ? root.width - width : leftEdge ? 0 : 18
            y: bottomEdge ? root.height - height : topEdge ? 0 : 18
            width: corner ? 18 : leftEdge || rightEdge ? 5 : Math.max(0, root.width - 36)
            height: corner ? 18 : topEdge || bottomEdge ? 5 : Math.max(0, root.height - 36)
            cursorShape: corner ? (leftEdge === topEdge ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                                : topEdge || bottomEdge ? Qt.SizeVerCursor : Qt.SizeHorCursor
            onPressed: root.targetWindow.startSystemResize(modelData)
        }
    }
}
