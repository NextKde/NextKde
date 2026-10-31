import QtQuick
import Kos.Ui

KosButton {
    id: control
    CalendarStyle { id: design }
    implicitHeight: 28
    implicitWidth: Math.max(64, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: 12
    rightPadding: 12
    topPadding: 4
    bottomPadding: 4
    font.pixelSize: 11
    font.weight: Font.Medium
    lightLabel: true
    scale: 1
    background: Rectangle {
        radius: height / 2
        color: control.emphasized ? AppTheme.withAlpha(design.accent, control.enabled ? 1 : 0.45)
            : control.flat && !control.hovered && !control.down ? "transparent"
            : control.down ? design.selectionFill
            : control.hovered ? design.rowHoverFill : design.controlFill
    }
}
