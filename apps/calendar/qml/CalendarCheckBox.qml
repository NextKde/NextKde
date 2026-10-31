import QtQuick
import QtQuick.Controls
import Kos.Ui

CheckBox {
    id: control
    CalendarStyle { id: design }
    property bool roundIndicator: false
    property color accentColor: design.accent
    implicitHeight: 28
    spacing: 8
    padding: 0
    font.pixelSize: 13
    indicator: Rectangle {
        implicitWidth: control.roundIndicator ? 18 : 16
        implicitHeight: control.roundIndicator ? 18 : 16
        x: control.leftPadding
        y: (control.height - height) / 2
        radius: control.roundIndicator ? height / 2 : 4
        color: control.checked ? (control.enabled ? control.accentColor : design.labelSecondary) : (control.roundIndicator ? "transparent" : (control.visualFocus || control.hovered ? design.selectionFill : design.controlFill))
        border.width: !control.checked && control.roundIndicator ? 1 : 0
        border.color: design.labelSecondary
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
        leftPadding: control.text.length > 0 ? control.indicator.width + control.spacing : 0
        verticalAlignment: Text.AlignVCenter
        color: control.enabled ? design.labelPrimary : design.labelSecondary
        elide: Text.ElideRight
    }
}
