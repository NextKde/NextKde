import QtQuick
import "../../Icons" as Symbols
import QtQuick.Controls

ComboBox {
    id: root
    implicitHeight: AppTheme.controlHeight
    leftPadding: 14; rightPadding: 30
    contentItem: Label {
        text: root.displayText; font: root.font
        color: root.enabled ? AppTheme.text : AppTheme.mutedText
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
    }
    indicator: Symbols.Icon {
        x: root.width - 24; y: (root.height - height) / 2
        name: "chevron_down"; color: AppTheme.mutedText; size: 16
    }
    background: KosSurface {
        radius: AppTheme.smallRadius
        fillColor: AppTheme.fieldSurface
        elevation: 0; focused: root.activeFocus; hovered: root.hovered
    }
    delegate: ItemDelegate {
        id: choice
        required property int index
        required property var modelData
        width: root.width
        text: root.textRole ? modelData[root.textRole] : modelData
        highlighted: root.highlightedIndex === index
        contentItem: Label { text: choice.text; color: AppTheme.text; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: AppTheme.smallRadius; color: choice.highlighted ? AppTheme.cardHover : "transparent" }
    }
    popup: Popup {
        y: root.height + 6; width: root.width
        implicitHeight: Math.min(contentItem.implicitHeight + 12, 300)
        padding: 6
        contentItem: ListView {
            clip: true; implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: KosSurface { fillColor: AppTheme.windowRaised; radius: AppTheme.mediumRadius; elevation: 0.4 }
    }
}
