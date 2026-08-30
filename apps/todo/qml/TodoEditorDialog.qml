pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

Dialog {
    id: root

    property string editingId: ""
    property var availableLists: []
    property string defaultListId: "inbox"
    readonly property bool editing: editingId.length > 0

    signal saveRequested(string uid, var todo)
    signal deleteRequested(string uid)

    title: editing ? qsTr("Edit task") : qsTr("New task")
    modal: true
    width: Math.min(600, parent ? parent.width - 48 : 600)
    height: Math.min(650, parent ? parent.height - 48 : 650)
    anchors.centerIn: parent
    standardButtons: Dialog.Save | Dialog.Cancel

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        return record[key] === undefined || record[key] === null ? fallback : record[key]
    }

    function listIndex(id) {
        for (let index = 0; index < availableLists.length; index++) {
            if (String(value(availableLists[index], "id", "")) === String(id))
                return index
        }
        return 0
    }

    function recurrenceIndex(preset) {
        const values = ["none", "daily", "weekly", "monthly", "yearly"]
        const index = values.indexOf(String(preset ?? "none"))
        return index >= 0 ? index : 0
    }

    function reminderIndex(minutes) {
        const values = [-1, 0, 5, 15, 30, 60, 1440]
        const index = values.indexOf(Number(minutes))
        return index >= 0 ? index : 0
    }

    function datePart(value) {
        const match = String(value ?? "").match(/^(\d{4}-\d{2}-\d{2})/)
        return match ? match[1] : ""
    }

    function openNew() {
        editingId = ""
        titleField.text = ""
        descriptionField.text = ""
        listBox.currentIndex = listIndex(defaultListId)
        dueDateField.text = ""
        dueTimeField.text = "18:00"
        allDayCheck.checked = true
        priorityBox.currentIndex = 0
        recurrenceBox.currentIndex = 0
        reminderBox.currentIndex = 0
        open()
        titleField.forceActiveFocus()
    }

    function openForTodo(todo) {
        editingId = String(value(todo, "id", ""))
        titleField.text = String(value(todo, "title", ""))
        descriptionField.text = String(value(todo, "description", ""))
        listBox.currentIndex = listIndex(value(todo, "listId", "inbox"))
        dueDateField.text = datePart(value(todo, "due", ""))
        const timeMatch = String(value(todo, "due", "")).match(/T(\d{2}:\d{2})/)
        dueTimeField.text = timeMatch ? timeMatch[1] : "18:00"
        allDayCheck.checked = Boolean(value(todo, "allDay", false))
        priorityBox.currentIndex = Math.max(0, Math.min(3, Number(value(todo, "priority", 0))))
        recurrenceBox.currentIndex = recurrenceIndex(value(todo, "recurrence", "none"))
        reminderBox.currentIndex = reminderIndex(value(todo, "reminderMinutes", -1))
        open()
        titleField.forceActiveFocus()
    }

    function todoPayload() {
        const recurrenceValues = ["none", "daily", "weekly", "monthly", "yearly"]
        const reminderValues = [-1, 0, 5, 15, 30, 60, 1440]
        const list = availableLists.length > 0
            ? availableLists[Math.max(0, listBox.currentIndex)] : ({ id: "inbox" })
        const date = dueDateField.text.trim()
        return {
            title: titleField.text.trim(),
            description: descriptionField.text.trim(),
            listId: String(value(list, "id", "inbox")),
            due: date.length > 0 ? date + "T"
                + (allDayCheck.checked ? "00:00" : dueTimeField.text.trim()) + ":00" : "",
            allDay: allDayCheck.checked,
            priority: priorityBox.currentIndex,
            recurrence: recurrenceBox.currentIndex > 0 && date.length === 0
                ? "none" : recurrenceValues[recurrenceBox.currentIndex],
            reminderMinutes: reminderValues[reminderBox.currentIndex]
        }
    }

    onAccepted: saveRequested(editingId, todoPayload())

    contentItem: ScrollView {
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 12

            Label { text: qsTr("Title"); color: AppTheme.mutedText }
            LiquidTextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: qsTr("Task title")
                Accessible.name: qsTr("Task title")
            }

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("List"); color: AppTheme.mutedText }
                    ComboBox {
                        id: listBox
                        Layout.fillWidth: true
                        model: root.availableLists
                        textRole: "name"
                        Accessible.name: qsTr("Task list")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Priority"); color: AppTheme.mutedText }
                    ComboBox {
                        id: priorityBox
                        Layout.fillWidth: true
                        model: [qsTr("None"), qsTr("Low"), qsTr("Medium"), qsTr("High")]
                        Accessible.name: qsTr("Task priority")
                    }
                }
            }

            Label { text: qsTr("Due date"); color: AppTheme.mutedText }
            RowLayout {
                Layout.fillWidth: true

                LiquidTextField {
                    id: dueDateField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Optional YYYY-MM-DD")
                    Accessible.name: qsTr("Task due date")
                }

                LiquidTextField {
                    id: dueTimeField
                    Layout.preferredWidth: 96
                    placeholderText: "HH:MM"
                    enabled: dueDateField.text.trim().length > 0 && !allDayCheck.checked
                    Accessible.name: qsTr("Task due time")
                }

                CheckBox {
                    id: allDayCheck
                    text: qsTr("All day")
                }
            }

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Repeat"); color: AppTheme.mutedText }
                    ComboBox {
                        id: recurrenceBox
                        Layout.fillWidth: true
                        model: [qsTr("Does not repeat"), qsTr("Daily"), qsTr("Weekly"),
                            qsTr("Monthly"), qsTr("Yearly")]
                        Accessible.name: qsTr("Task recurrence")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Reminder"); color: AppTheme.mutedText }
                    ComboBox {
                        id: reminderBox
                        Layout.fillWidth: true
                        model: [qsTr("None"), qsTr("At due time"), qsTr("5 minutes before"),
                            qsTr("15 minutes before"), qsTr("30 minutes before"),
                            qsTr("1 hour before"), qsTr("1 day before")]
                        Accessible.name: qsTr("Task reminder")
                    }
                }
            }

            Label { text: qsTr("Notes"); color: AppTheme.mutedText }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 150

                TextArea {
                    id: descriptionField
                    placeholderText: qsTr("Optional notes")
                    wrapMode: TextEdit.Wrap
                    Accessible.name: qsTr("Task notes")
                }
            }

            Button {
                Layout.alignment: Qt.AlignLeft
                text: qsTr("Delete task")
                visible: root.editing
                palette.buttonText: AppTheme.destructive
                onClicked: {
                    root.deleteRequested(root.editingId)
                    root.close()
                }
            }
        }
    }
}
