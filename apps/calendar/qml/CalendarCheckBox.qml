import QtQuick
import QtQuick.Controls
import Kos.Ui

CheckBox {
    id: control
    CalendarStyle { id: design }
    implicitHeight: 28
    spacing: 8
    padding: 0
    font.pixelSize: 13
    indicator: Rectangle {
        implicitWidth: 16
        implicitHeight: 16
        x: control.leftPadding
        y: (control.height - height) / 2
        radius: 4
        color: control.checked ? design.accent : design.controlFill
        border.width: control.activeFocus ? 2 : 1
        border.color: control.checked || control.activeFocus ? design.accent : design.separator
        Text {
            anchors.centerIn: parent
            text: control.checkState === Qt.PartiallyChecked ? "−" : "✓"
            visible: control.checkState !== Qt.Unchecked
            color: "white"
            font.pixelSize: 12
        }
    }
    contentItem: Label {
        text: control.text
        font: control.font
        leftPadding: control.indicator.width + control.spacing
        verticalAlignment: Text.AlignVCenter
        color: control.enabled ? design.labelPrimary : design.labelSecondary
        elide: Text.ElideRight
    }
}
