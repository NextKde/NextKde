import QtQuick
import Kos.Ui

KosTextField {
    id: control
    property bool invalid: false
    CalendarStyle { id: design }
    implicitHeight: design.fieldHeight
    font.pixelSize: design.controlFontSize
    topPadding: 4
    bottomPadding: 4
    leftPadding: 12
    rightPadding: 12
    glassColor: design.controlFill
    outlineColor: "transparent"
    textColor: design.labelPrimary
    mutedTextColor: design.labelSecondary
    background: Rectangle {
        radius: control.cornerRadius
        color: control.glassColor
        border.width: control.activeFocus ? 2 : control.outlineColor.a > 0 ? 1 : 0
        border.color: control.invalid ? control.outlineColor
            : control.activeFocus ? design.accent : control.outlineColor
    }
    cornerRadius: height < 28 ? 6 : height / 2
}
