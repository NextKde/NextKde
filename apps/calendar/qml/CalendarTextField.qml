import QtQuick
import Kos.Ui

KosTextField {
    id: control
    property bool invalid: false
    CalendarStyle { id: design }
    implicitHeight: design.fieldHeight
    font.pixelSize: design.editorInputFontSize
    font.weight: Font.Normal
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
        color: control.activeFocus ? design.selectionFill : control.glassColor
        border.width: control.invalid ? 1 : 0
        border.color: AppTheme.destructive
    }
    cornerRadius: height / 2
}
