import QtQuick
import QtQuick.Controls
import Kos.Ui

ComboBox {
    id: root
    implicitHeight: AppTheme.controlHeight
    leftPadding: 12
    rightPadding: 32
    background: Rectangle {
        radius: AppTheme.smallRadius
        color: root.down ? AppTheme.buttonPressed : root.hovered ? AppTheme.buttonHover : AppTheme.button
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? AppTheme.focusRing : AppTheme.border
    }
    contentItem: Label {
        text: root.displayText
        font: root.font
        color: root.enabled ? AppTheme.text : AppTheme.mutedText
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Label {
        x: root.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        text: "⌄"
        color: AppTheme.mutedText
    }
    delegate: MusicMenuItem {
        required property int index
        width: ListView.view.width
        text: root.textAt(index)
        highlighted: root.highlightedIndex === index
        checkable: true
        checked: root.currentIndex === index
    }
    popup: Popup {
        y: root.height + 4
        width: root.width
        padding: 6
        implicitHeight: Math.min(contentItem.implicitHeight + 12, 280)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle {
            radius: AppTheme.mediumRadius
            color: AppTheme.windowRaised
            border.color: AppTheme.border
        }
    }
}
