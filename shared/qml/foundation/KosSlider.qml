import QtQuick
import QtQuick.Controls

Slider {
    id: root

    implicitWidth: 220
    implicitHeight: AppTheme.controlHeight
    leftPadding: 2
    rightPadding: 2
    topPadding: 8
    bottomPadding: 8
    opacity: enabled ? 1 : 0.48

    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.availableWidth
        height: 6
        radius: 3
        color: AppTheme.mix(AppTheme.button, AppTheme.mutedText, 0.12)

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: parent.radius
            color: AppTheme.accent
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 20
        implicitHeight: 20
        radius: width / 2
        color: AppTheme.windowRaised
        border.width: root.activeFocus ? 3 : 1
        border.color: root.activeFocus ? AppTheme.accent : AppTheme.border
        scale: root.pressed ? 1.08 : 1

        Behavior on scale {
            NumberAnimation { duration: AppTheme.motionFast }
        }
    }
}
