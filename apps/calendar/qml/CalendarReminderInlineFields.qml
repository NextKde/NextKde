pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Demo as Demo

ColumnLayout {
    id: root
    property alias notes: notesInput.text
    property alias tagsText: tagsInput.text
    property bool flagged: false
    signal detailsRequested()
    readonly property var tags: [...new Set(tagsText.split(/[\s,，]+/).map(tag => tag.replace(/^#+/, "")).filter(Boolean))]
    spacing: 2
    CalendarStyle { id: design }
    Demo.SettingsTextField {
        id: notesInput
        Layout.fillWidth: true
        implicitHeight: 22
        leftPadding: 0; rightPadding: 0
        placeholderText: qsTr("Notes")
        background: Item {}
    }
    Demo.SettingsTextField {
        id: tagsInput
        objectName: "inlineReminderTags"
        Layout.fillWidth: true
        implicitHeight: 22
        leftPadding: 0; rightPadding: 0
        placeholderText: qsTr("Add tags")
        background: Item {}
    }
    RowLayout {
        spacing: 4
        CalendarButton {
            text: "#"
            Accessible.name: qsTr("Add tags")
            implicitWidth: 26; implicitHeight: 24
            leftPadding: 6; rightPadding: 6
            onClicked: tagsInput.forceActiveFocus()
        }
        ToolButton {
            id: flagButton
            Accessible.name: qsTr("Flag reminder")
            implicitWidth: 26; implicitHeight: 24; padding: 5
            contentItem: Demo.VectorIcon { name: "flag"; size: 14; filled: root.flagged; color: root.flagged ? "#FB8208" : design.labelSecondary }
            background: Rectangle { radius: 6; color: flagButton.hovered ? design.rowHoverFill : design.controlFill }
            onClicked: root.flagged = !root.flagged
        }
    }
}
