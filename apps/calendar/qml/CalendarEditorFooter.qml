import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

Item {
    id: footer
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
    implicitHeight: (confirmingDelete ? confirmation.implicitHeight : actions.implicitHeight) + 32
    onConfirmingDeleteChanged: {
        if (confirmingDelete) Qt.callLater(function() { confirmCancel.forceActiveFocus() })
        else Qt.callLater(function() { cancelButton.forceActiveFocus() })
    }
    readonly property string saveText: qsTr("Save")
    readonly property string cancelText: qsTr("Cancel")
    RowLayout {
        id: actions
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        spacing: 8
        visible: !footer.confirmingDelete
        CalendarButton {
            visible: footer.editing
            text: footer.deleteLabel
            destructive: true
            onClicked: footer.deleteArmed()
        }
        Item { Layout.fillWidth: true }
        CalendarButton { id: cancelButton; text: footer.cancelText; onClicked: footer.rejected() }
        CalendarButton { objectName: "editorSave"; text: footer.saveText; highlighted: true; onClicked: footer.accepted() }
    }
    ColumnLayout {
        id: confirmation
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        spacing: 8
        visible: footer.confirmingDelete
        Label { Layout.fillWidth: true; text: footer.deleteTitle; font.pixelSize: 13; font.bold: true; color: design.labelPrimary; wrapMode: Text.WordWrap }
        Label { Layout.fillWidth: true; text: footer.deleteMessage; font.pixelSize: 11; color: design.labelSecondary; wrapMode: Text.WordWrap }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            CalendarButton { text: footer.deleteLabel; destructive: true; onClicked: footer.deleteConfirmed() }
            CalendarButton { id: confirmCancel; text: footer.cancelText; highlighted: true; onClicked: footer.deleteCanceled() }
        }
    }
}
