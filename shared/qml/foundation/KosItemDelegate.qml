import QtQuick
import QtQuick.Controls

ItemDelegate {
    id: root
    leftPadding: 12; rightPadding: 12
    background: Rectangle {
        radius: AppTheme.smallRadius
        color: root.highlighted || root.down ? AppTheme.withAlpha(AppTheme.accent, 0.16)
             : root.hovered ? AppTheme.cardHover : "transparent"
        border.width: root.activeFocus ? 1 : 0
        border.color: AppTheme.focusRing
    }
}
