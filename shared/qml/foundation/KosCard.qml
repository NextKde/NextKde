import QtQuick
import QtQuick.Controls

Pane {
    id: root

    padding: 18

    background: Rectangle {
        radius: AppTheme.mediumRadius
        color: AppTheme.card
        border.width: 1
        border.color: AppTheme.border

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, AppTheme.dark ? 0.035 : 0.30)
        }
    }
}
