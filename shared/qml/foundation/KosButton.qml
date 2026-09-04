import QtQuick
import QtQuick.Controls

Button {
    id: root

    property bool destructive: false
    readonly property bool emphasized: highlighted || (checkable && checked)

    implicitHeight: AppTheme.controlHeight
    implicitWidth: Math.max(72, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: 16
    rightPadding: 16
    topPadding: 7
    bottomPadding: 7

    contentItem: Label {
        text: root.text
        font: root.font
        color: !root.enabled
            ? AppTheme.withAlpha(AppTheme.text, 0.42)
            : (root.emphasized ? AppTheme.accentText
                               : (root.destructive ? AppTheme.destructive : AppTheme.text))
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight

        Behavior on color { ColorAnimation { duration: AppTheme.motionFast } }
    }

    background: Rectangle {
        implicitWidth: 72
        implicitHeight: AppTheme.controlHeight
        radius: Math.min(AppTheme.smallRadius, height / 2)
        color: {
            if (root.emphasized)
                return root.down ? AppTheme.accentPressed
                    : (root.hovered ? AppTheme.accentHover : AppTheme.accent)
            if (root.flat && !root.hovered && !root.down)
                return "transparent"
            if (root.down)
                return AppTheme.buttonPressed
            return root.hovered ? AppTheme.buttonHover : AppTheme.button
        }
        border.width: root.activeFocus ? 2 : (root.flat && !root.hovered ? 0 : 1)
        border.color: root.activeFocus
            ? AppTheme.withAlpha(AppTheme.accent, 0.72)
            : (root.emphasized
               ? AppTheme.withAlpha(AppTheme.accentText, 0.16)
               : AppTheme.border)
        opacity: root.enabled ? 1 : 0.68

        Behavior on color { ColorAnimation { duration: AppTheme.motionFast } }
        Behavior on border.color { ColorAnimation { duration: AppTheme.motionFast } }
    }
}
