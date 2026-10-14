import QtQuick
import QtQuick.Window

// Eight invisible edge/corner zones for a frameless window, delegating the
// actual resize to the Wayland compositor via startSystemResize. Copied from
// apps/listenfree/music_player_desktop/components/WindowResizeHandles.qml.
// Only active while the window is windowed and the frameless CSD form is on
// (see the `csd` property on the root window in main.qml).
Item {
    id: root
    required property var targetWindow
    anchors.fill: parent
    z: 100
    enabled: targetWindow.csd && targetWindow.visibility === Window.Windowed
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
