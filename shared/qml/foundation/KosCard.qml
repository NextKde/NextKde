import QtQuick
import QtQuick.Controls

Pane {
    id: root

    padding: Math.round(18 * AppTheme.densityScale)

    background: Rectangle {
        radius: AppTheme.mediumRadius
        color: AppTheme.cardSurface
        border.width: 1
        border.color: AppTheme.border

        Behavior on color { ColorAnimation { duration: AppTheme.motionFast } }
        Behavior on border.color { ColorAnimation { duration: AppTheme.motionFast } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: "transparent"
            border.width: 1
            border.color: AppTheme.dark
                ? Qt.rgba(1, 1, 1, 0.035)
                : Qt.rgba(1, 1, 1, 0.52)
        }
    }
}
