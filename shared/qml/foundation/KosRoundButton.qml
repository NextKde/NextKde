import QtQuick
import QtQuick.Controls

RoundButton {
    id: root

    implicitWidth: 46
    implicitHeight: 46
    padding: 8

    contentItem: Label {
        text: root.text
        font: root.font
        color: root.enabled
            ? (root.highlighted ? AppTheme.accentText : AppTheme.text)
            : AppTheme.withAlpha(AppTheme.text, 0.38)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: width / 2
        color: root.highlighted
            ? (root.down ? AppTheme.accentPressed
                         : (root.hovered ? AppTheme.accentHover : AppTheme.accent))
            : (root.down ? AppTheme.buttonPressed
                         : (root.hovered ? AppTheme.buttonHover : AppTheme.button))
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus
            ? AppTheme.withAlpha(AppTheme.accent, 0.72)
            : (root.highlighted
               ? AppTheme.withAlpha(AppTheme.accentText, 0.16)
               : AppTheme.border)
        opacity: root.enabled ? 1 : 0.64

        Behavior on color { ColorAnimation { duration: AppTheme.motionFast } }
    }
}
