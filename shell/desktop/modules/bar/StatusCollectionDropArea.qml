import QtQuick

// Native Qt drag-and-drop crosses the PopupWindow boundary and keeps the
// compositor-owned drag image visible outside the small Bar/Dock surface.
DropArea {
    id: area
    required property var coordinator
    required property string section
    property bool disclosure: false
    onEntered: function(drag) {
        coordinator.updateDropTarget(area, drag, section, disclosure)
    }
    onPositionChanged: function(drag) {
        coordinator.updateDropTarget(area, drag, section, disclosure)
    }
    onExited: coordinator.leaveDropTarget(area)
    onDropped: function(drop) {
        if (coordinator.updateDropTarget(area, drop, section, disclosure)) {
            coordinator.stageDrop()
            drop.accept(Qt.MoveAction)
        }
    }
}
