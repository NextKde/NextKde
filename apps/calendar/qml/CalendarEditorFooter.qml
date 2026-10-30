import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

Item {
    id: footer
    property Item sourceItem: null
    property bool editing: false
    property bool confirmingDelete: false
    property string deleteLabel
    property string deleteTitle
    property string deleteMessage
    signal accepted()
    signal rejected()
    signal deleteArmed()
    signal deleteCanceled()
    signal deleteConfirmed()
    CalendarStyle { id: design }
    implicitHeight: actions.implicitHeight + 14
    onConfirmingDeleteChanged: {
        if (confirmingDelete) confirmation.open()
        else confirmation.close()
    }
    onVisibleChanged: if (!visible && confirmation.visible) confirmation.close()
    readonly property string saveText: qsTr("Save")
    readonly property string cancelText: qsTr("Cancel")
    RowLayout {
        id: actions
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 10
        spacing: 8
        Demo.LiquidDialogButton {
            visible: footer.editing
            text: footer.deleteLabel
            destructive: true
            onClicked: footer.deleteArmed()
        }
        Item { Layout.fillWidth: true }
        Demo.LiquidDialogButton { id: cancelButton; text: footer.cancelText; onClicked: footer.rejected() }
        Demo.LiquidDialogButton { objectName: "editorSave"; text: footer.saveText; primaryAction: true; onClicked: footer.accepted() }
    }
    Demo.LiquidDialog {
        id: confirmation
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(360, parent ? parent.width - 32 : 360)
        implicitHeight: header.implicitHeight + deleteText.implicitHeight + topPadding + bottomPadding + 62
        sourceItem: footer.sourceItem
        title: footer.deleteTitle
        modal: true
        dim: true
        closePolicy: Popup.CloseOnEscape
        onOpened: confirmCancel.forceActiveFocus()
        onClosed: if (footer.confirmingDelete) footer.deleteCanceled()
        contentItem: Label {
            id: deleteText
            width: confirmation.width - confirmation.leftPadding - confirmation.rightPadding
            text: footer.deleteMessage
            color: design.labelPrimary
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }
        footer: Item {
            implicitHeight: 62
            RowLayout {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                spacing: 8
            Item { Layout.fillWidth: true }
            Demo.LiquidDialogButton {
                id: confirmCancel
                text: footer.cancelText
                onClicked: confirmation.close()
            }
            Demo.LiquidDialogButton {
                text: footer.deleteLabel
                destructive: true
                onClicked: {
                    // Close before the owner deletes/closes the editor.
                    confirmation.close()
                    footer.deleteConfirmed()
                }
            }
            }
        }
    }
}
