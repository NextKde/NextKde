import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../shared/qml/i18n"

Dialog {
    id: dialog
    property var targetWindow
    property var store
    property bool waitingForCancellation: false
    readonly property bool operationActive: !!store && !!store.hasActiveMutation
    objectName: "appOperationCloseDialog"
    modal: true
    anchors.centerIn: parent
    width: Math.min(460, targetWindow ? Math.max(280, targetWindow.width - 32) : 460)
    contentHeight: message.contentHeight
    closePolicy: waitingForCancellation ? Popup.NoAutoClose : Popup.CloseOnEscape
    title: I18n.tr("An application task is still running")

    function cancelAndClose() {
        waitingForCancellation = true
        store.cancelActiveMutations()
    }
    function keepOpen() {
        waitingForCancellation = false
        close()
    }
    onOperationActiveChanged: {
        if (operationActive) return
        const shouldClose = waitingForCancellation
        waitingForCancellation = false
        close()
        if (shouldClose && targetWindow) targetWindow.close()
    }
    onRejected: waitingForCancellation = false
    Connections {
        target: dialog.targetWindow
        function onClosing(event) {
            if (!dialog.operationActive) return
            event.accepted = false
            dialog.open()
        }
    }
    contentItem: Label {
        id: message
        width: dialog.availableWidth
        text: dialog.waitingForCancellation
            ? I18n.tr("Finishing the task safely. Settings will close when it has stopped.")
            : I18n.tr("An application is being installed, updated or removed. Keep Settings open, or cancel the task and close after it has stopped.")
        wrapMode: Text.Wrap
    }
    footer: DialogButtonBox {
        Button {
            objectName: "keepSettingsOpen"
            text: I18n.tr("Keep Settings open")
            onClicked: dialog.keepOpen()
        }
        Button {
            objectName: "cancelTaskAndClose"
            text: I18n.tr("Cancel task and close")
            enabled: !dialog.waitingForCancellation
            onClicked: dialog.cancelAndClose()
        }
    }
}
