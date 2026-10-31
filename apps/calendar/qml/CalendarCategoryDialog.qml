pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

Demo.LiquidDialog {
    id: root
    property string categoryId: ""
    property string selectedColor: "#1D9BF6"
    readonly property var presetColors: ["#FF453A", "#FB0055", "#FF6482", "#FB8208", "#FEC309", "#56D72B", "#39C487", "#30B0A0", "#64D2FF", "#1D9BF6", "#4F8CFF", "#5856D6", "#BF57DA", "#A2845E", "#90714C", "#8E8E93", "#636366", "#3A3A3C"]
    readonly property bool validColor: /^#[0-9a-fA-F]{6}$/.test(selectedColor)
    property bool removing: false
    property bool saving: false
    property string errorText: ""
    property bool writable: true
    signal saveRequested(string categoryId, var values)
    signal removeRequested(string categoryId)
    title: removing ? qsTr("Delete calendar") : categoryId ? qsTr("Edit calendar") : qsTr("Add calendar")
    width: Math.min(380, parent ? parent.width - 32 : 380)
    anchors.centerIn: parent
    closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape
    function edit(category, remove) {
        categoryId = category ? category.id : ""
        nameField.text = category ? category.name : ""
        selectedColor = category ? category.color : "#1D9BF6"
        removing = !!remove
        saving = false
        errorText = ""
        open()
        if (!removing) Qt.callLater(function() { nameField.forceActiveFocus(); nameField.selectAll() })
    }
    contentItem: ColumnLayout {
        id: form
        spacing: 12
        Label {
            visible: root.removing
            Layout.fillWidth: true
            text: qsTr('Delete “%1”? Its events and reminders will move to the default calendar.').arg(nameField.text)
            wrapMode: Text.WordWrap
            color: Demo.AppTheme.text
        }
        Label { visible: !root.removing; text: qsTr("Name"); color: Demo.AppTheme.text }
        CalendarTextField {
            id: nameField
            visible: !root.removing
            Layout.fillWidth: true
            maximumLength: 128
            enabled: !root.saving
        }
        Label { visible: !root.removing; text: qsTr("Color"); color: Demo.AppTheme.text }
        GridLayout {
            visible: !root.removing
            Layout.fillWidth: true
            columns: 9
            columnSpacing: Math.max(0, (form.width - columns * 24) / (columns - 1))
            rowSpacing: 6
            Repeater {
                model: root.presetColors
                delegate: ToolButton {
                    id: swatch
                    required property string modelData
                    implicitWidth: 24
                    implicitHeight: 24
                    padding: 6
                    enabled: !root.saving
                    Accessible.name: qsTr("Color %1").arg(modelData)
                    Accessible.checkable: true
                    Accessible.checked: root.selectedColor.toLowerCase() === modelData.toLowerCase()
                    background: Rectangle { radius: 12; color: swatch.modelData }
                    contentItem: Demo.VectorIcon {
                        name: "check"
                        color: ["#FEC309", "#56D72B"].includes(swatch.modelData) ? "#242424" : "white"
                        visible: root.selectedColor.toLowerCase() === swatch.modelData.toLowerCase()
                    }
                    onClicked: root.selectedColor = modelData
                }
            }
        }
        Label {
            visible: root.errorText !== ""
            Layout.fillWidth: true
            text: root.errorText
            color: Demo.AppTheme.destructive
            wrapMode: Text.WordWrap
        }
    }
    footer: Item {
        implicitHeight: 62
        RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8
        Item { Layout.fillWidth: true }
        Demo.LiquidDialogButton {
            text: qsTr("Cancel")
            enabled: !root.saving
            onClicked: root.close()
        }
        Demo.LiquidDialogButton {
            text: root.removing ? qsTr("Delete") : root.categoryId ? qsTr("Save") : qsTr("Add")
            primaryAction: !root.removing
            destructive: root.removing
            enabled: root.writable && !root.saving && (root.removing || (nameField.text.trim().length > 0 && root.validColor))
            onClicked: {
                root.saving = true
                root.errorText = ""
                if (root.removing) root.removeRequested(root.categoryId)
                else root.saveRequested(root.categoryId, { name: nameField.text.trim(), color: root.selectedColor })
            }
        }
        }
    }
}
