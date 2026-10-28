import QtQuick
import QtQuick.Controls
import Kos.Ui

KosComboBox {
    id: control
    CalendarStyle { id: design }
    property Item popupScene: null
    implicitHeight: design.fieldHeight
    font.pixelSize: design.controlFontSize
    font.weight: Font.Medium
    leftPadding: 12
    topPadding: 4
    bottomPadding: 4
    background: Rectangle {
        color: control.down ? design.selectionFill
            : control.hovered ? design.rowHoverFill : design.controlFill
        radius: height / 2
        border.width: control.activeFocus ? 2 : 0
        border.color: design.accent
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: control.popup.availableWidth
        height: 24
        topPadding: 4
        bottomPadding: 4
        leftPadding: 8
        rightPadding: 8
        text: control.textRole ? modelData[control.textRole] : modelData
        highlighted: control.highlightedIndex === index
        font.pixelSize: 11
        contentItem: Label {
            text: option.text
            font: option.font
            color: option.highlighted ? "white" : design.labelPrimary
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 4
            color: option.highlighted ? design.accent : "transparent"
        }
    }
    popup: Popup {
        popupType: Popup.Item
        y: control.height + 4
        width: control.width
        padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 248)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: CalendarPopupSurface { scene: control.popupScene; radius: 12 }
    }
}
