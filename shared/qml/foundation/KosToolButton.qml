import QtQuick
import QtQuick.Controls

ToolButton {
    id: root

    property bool destructive: false

    implicitWidth: AppTheme.controlHeight
    implicitHeight: AppTheme.controlHeight
    padding: 7

    contentItem: Label {
        text: root.text
        font: root.font
        color: root.enabled
            ? ((root.checkable && root.checked) ? AppTheme.accent
               : (root.destructive ? AppTheme.destructive : AppTheme.text))
            : AppTheme.withAlpha(AppTheme.text, 0.38)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: Math.min(AppTheme.smallRadius, height / 2)
        color: root.destructive && (root.hovered || root.down)
            ? AppTheme.withAlpha(AppTheme.destructive, root.down ? 0.20 : 0.11)
            : (root.down ? AppTheme.buttonPressed
               : (root.hovered || (root.checkable && root.checked)
                  ? AppTheme.buttonHover : "transparent"))
        border.width: root.activeFocus ? 2 : 0
        border.color: AppTheme.withAlpha(AppTheme.accent, 0.70)

        Behavior on color { ColorAnimation { duration: AppTheme.motionFast } }
    }
}
