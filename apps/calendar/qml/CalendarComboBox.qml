import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Kos.Ui

KosComboBox {
    id: control
    CalendarStyle { id: design }
    property string colorRole: ""
    function entryColor(entry) {
        return colorRole && entry && entry[colorRole] ? entry[colorRole] : "transparent"
    }
    readonly property var selectedEntry: currentIndex >= 0 && model
        ? (typeof model.get === "function" ? model.get(currentIndex) : model[currentIndex]) : null
    contentItem: RowLayout {
        spacing: 6
        Rectangle {
            color: control.entryColor(control.selectedEntry)
            visible: color.a > 0
            implicitWidth: 8; implicitHeight: 8; radius: 4
        }
        Label {
            Layout.fillWidth: true
            text: control.displayText
            font: control.font
            color: control.enabled ? design.labelPrimary : design.labelSecondary
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
    implicitHeight: design.fieldHeight
    font.pixelSize: design.editorInputFontSize
    font.weight: Font.Normal
    leftPadding: 12
    topPadding: 4
    bottomPadding: 4
    background: Rectangle {
        color: control.down || control.visualFocus ? design.selectionFill
            : control.hovered ? design.rowHoverFill : design.controlFill
        radius: height / 2
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
        font.pixelSize: 13
        font.weight: Font.Normal
        contentItem: RowLayout {
            spacing: 6
            Label {
                Layout.preferredWidth: 12
                text: option.index === control.currentIndex ? "✓" : ""
                color: design.labelPrimary
                font.pixelSize: 12
                font.weight: Font.Normal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            Rectangle {
                color: control.entryColor(option.modelData)
                visible: color.a > 0
                implicitWidth: 8; implicitHeight: 8; radius: 4
            }
            Label {
                Layout.fillWidth: true
                text: option.text
                font: option.font
                color: design.labelPrimary
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
        background: Rectangle {
            radius: design.menuItemRadius
            color: option.highlighted || option.hovered ? design.rowHoverFill : "transparent"
        }
    }
    popup: Popup {
        popupType: Popup.Item
        y: control.height + 4
        width: control.width
        padding: 6
        implicitHeight: Math.min(contentItem.implicitHeight + 12, 248)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        // Form dropdowns are opaque ordinary panels, without glass sampling.
        background: Rectangle {
            radius: design.popupRadius
            color: AppTheme.dark ? "#303034" : "#F0F0F1"
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowOpacity: 0.14
                shadowBlur: 0.5
                shadowVerticalOffset: 0
                autoPaddingEnabled: true
            }
        }
    }
}
