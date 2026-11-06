import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../shared/qml/i18n"

Dialog {
    id: dialog
    property var targetWindow
    property var store
    property var colors: null
    SystemPalette { id: systemPalette }
    readonly property color surfaceColor: colors ? colors.contentSurface : systemPalette.window
    readonly property color textColor: colors ? colors.primaryText : systemPalette.windowText
    readonly property color detailColor: colors ? colors.secondaryText : systemPalette.text
    readonly property color accentColor: colors ? colors.selected : systemPalette.highlight
    property bool waitingForCancellation: false
    readonly property bool operationActive: !!store && !!store.hasActiveMutation
    objectName: "appOperationCloseDialog"
    modal: true
    anchors.centerIn: parent
    width: Math.min(400, targetWindow ? targetWindow.width - 32 : 400)
    padding: 24
    contentHeight: body.implicitHeight
    header: null
    footer: null
    focus: true
    onOpened: keepButton.forceActiveFocus()
    background: Rectangle {
        color: dialog.surfaceColor
        radius: 20
        border.width: 1
        border.color: dialog.colors ? dialog.colors.separator : systemPalette.mid
    }
    Overlay.modal: Rectangle { color: "#33000000" }
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
    component ActionButton: Button {
        id: action
        property bool primary: false
        implicitHeight: 38
        implicitWidth: label.implicitWidth + 28
        hoverEnabled: true
        contentItem: Label {
            id: label
            text: action.text
            font.pixelSize: 13
            font.weight: action.primary ? Font.DemiBold : Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: action.primary ? (dialog.colors ? dialog.colors.role("on_primary", "#ffffff") : systemPalette.highlightedText) : dialog.textColor
            opacity: action.enabled ? 1 : 0.45
        }
        background: Rectangle {
            radius: 9
            color: action.primary ? dialog.accentColor : (dialog.colors ? dialog.colors.searchField : systemPalette.button)
            opacity: action.down ? 0.7 : (action.hovered ? 0.88 : 1)
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: 12
                color: "transparent"
                border.width: 2
                border.color: dialog.accentColor
                visible: action.visualFocus
            }
        }
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
    }
    contentItem: ColumnLayout {
        id: body
        spacing: 14
        Label {
            Layout.fillWidth: true
            text: dialog.title
            color: dialog.textColor
            font.pixelSize: 18
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
        Label {
            id: message
            Layout.fillWidth: true
            text: dialog.waitingForCancellation
                ? I18n.tr("Finishing the task safely. Settings will close when it has stopped.")
                : I18n.tr("An application is being installed, updated or removed. Keep Settings open, or cancel the task and close after it has stopped.")
            color: dialog.detailColor
            font.pixelSize: 13
            lineHeight: 1.25
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Accessible.role: Accessible.StaticText
        }
        ProgressBar {
            Layout.fillWidth: true
            visible: dialog.waitingForCancellation
            indeterminate: true
            implicitHeight: 4
            Accessible.name: message.text
        }
        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            columns: cancelButton.implicitWidth + keepButton.implicitWidth + columnSpacing > width ? 1 : 2
            columnSpacing: 10
            rowSpacing: 10
            ActionButton {
                id: cancelButton
                Layout.fillWidth: true
                objectName: "cancelTaskAndClose"
                text: I18n.tr("Cancel task and close")
                enabled: !dialog.waitingForCancellation
                onClicked: dialog.cancelAndClose()
            }
            ActionButton {
                id: keepButton
                Layout.fillWidth: true
                objectName: "keepSettingsOpen"
                text: I18n.tr("Keep Settings open")
                primary: true
                onClicked: dialog.keepOpen()
            }
        }
    }
}
