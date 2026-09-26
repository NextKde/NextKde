import QtQuick
import QtQuick.Controls
import Kos.Ui

Menu {
    id: root
    padding: 6
    implicitWidth: 228
    background: Rectangle {
        implicitWidth: 228
        radius: AppTheme.mediumRadius
        color: AppTheme.windowRaised
        border.color: AppTheme.border
        antialiasing: true
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: AppTheme.motionFast }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: AppTheme.motionFast }
    }
}
