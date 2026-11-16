import QtQuick

Item {
    id: root
    property bool opened: false
    readonly property int columns: 10
    readonly property int rows: 5
    readonly property int iconSize: 64
    readonly property int spacing: 24
    readonly property int cellSize: iconSize + spacing
    readonly property alias delegates: icons
    width: columns * cellSize - spacing
    height: rows * cellSize - spacing

    Repeater {
        id: icons
        model: root.columns * root.rows
        delegate: LauncherIcon {
            x: (index % root.columns) * root.cellSize
            y: Math.floor(index / root.columns) * root.cellSize
            opened: root.opened
            centerX: root.width / 2
            centerY: root.height / 2
        }
    }
}
