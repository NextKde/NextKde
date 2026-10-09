pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosWorkspaceDialog {
    id: root

    property string editingId: ""
    property string linkedEventId: ""
    property var availableLists: []

    signal saveRequested(string uid, var todo)
    signal deleteRequested(string uid)

    title: qsTr("Edit task")
    modal: true
    width: Math.min(560, parent ? parent.width - 48 : 560)
    height: Math.min(610, parent ? parent.height - 48 : 610)
    anchors.centerIn: parent
    standardButtons: Dialog.Save | Dialog.Cancel

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        const result = record[key]
        return result === undefined || result === null ? fallback : result
    }

    function datePart(encoded) {
        const match = String(encoded ?? "").match(/^(\d{4}-\d{2}-\d{2})/)
        return match ? match[1] : ""
    }

    function listIndex(id) {
        for (let index = 0; index < availableLists.length; index++) {
            if (String(value(availableLists[index], "id", "")) === String(id))
                return index
        }
        return 0
    }

    function priorityIndex(priority) {
        const number = Number(priority)
        if (number <= 0) return 0
        if (number <= 3) return 3
        if (number <= 6) return 2
        return 1
    }

    function openForTodo(todo) {
        editingId = String(value(todo, "seriesId", value(todo, "id", "")))
        linkedEventId = String(value(todo, "linkedEventId", ""))
        titleField.text = String(value(todo, "title", ""))
        notesField.text = String(value(todo, "description", ""))
        completedCheck.checked = Boolean(value(todo, "completed", false))
        listBox.currentIndex = listIndex(value(todo, "listId", "inbox"))
        const due = String(value(todo, "due", ""))
        dueDateField.text = datePart(due)
        const timeMatch = due.match(/T(\d{2}:\d{2})/)
        dueTimeField.text = timeMatch ? timeMatch[1] : "18:00"
        allDayCheck.checked = Boolean(value(todo, "allDay", false))
        priorityBox.currentIndex = priorityIndex(value(todo, "priority", 0))
        open()
        titleField.forceActiveFocus()
    }

    function payload() {
        const priorityValues = [0, 9, 5, 1]
        const list = availableLists.length > 0
            ? availableLists[Math.max(0, listBox.currentIndex)] : ({ id: "inbox" })
        const dueDate = dueDateField.text.trim()
        return {
            title: titleField.text.trim(),
            description: notesField.text.trim(),
            listId: String(value(list, "id", "inbox")),
            due: dueDate.length > 0 ? dueDate + "T"
                + (allDayCheck.checked ? "00:00" : dueTimeField.text.trim()) + ":00" : "",
            allDay: allDayCheck.checked,
            priority: priorityValues[priorityBox.currentIndex],
            completed: completedCheck.checked
        }
    }

    onAccepted: saveRequested(editingId, payload())

    contentItem: ScrollView {
        id: editorScroll
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        clip: true

        ColumnLayout {
            width: editorScroll.availableWidth
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: relationLabel.implicitHeight + 22
                radius: AppTheme.smallRadius
                visible: root.linkedEventId.length > 0
                color: AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.14 : 0.09)
                border.width: 1
                border.color: AppTheme.withAlpha(AppTheme.accent, 0.28)

                Label {
                    id: relationLabel
                    anchors.fill: parent
                    anchors.margins: 11
                    text: qsTr("Linked to this Calendar event. Editing the title or date updates the matching task in Todo.")
                    color: AppTheme.text
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Title"); color: AppTheme.mutedText }
                    KosTextField {
                        id: titleField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Task title")
                        Accessible.name: qsTr("Task title")
                    }
                }

                KosCheckBox {
                    id: completedCheck
                    text: qsTr("Completed")
                    Layout.alignment: Qt.AlignBottom
                }
            }

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("List"); color: AppTheme.mutedText }
                    KosComboBox {
                        id: listBox
                        Layout.fillWidth: true
                        model: root.availableLists
                        textRole: "name"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Priority"); color: AppTheme.mutedText }
                    KosComboBox {
                        id: priorityBox
                        Layout.fillWidth: true
                        model: [qsTr("None"), qsTr("Low"), qsTr("Medium"), qsTr("High")]
                    }
                }
            }

            Label { text: qsTr("Due date"); color: AppTheme.mutedText }
            RowLayout {
                Layout.fillWidth: true

                KosTextField {
                    id: dueDateField
                    Layout.fillWidth: true
                    placeholderText: "YYYY-MM-DD"
                    Accessible.name: qsTr("Task due date")
                }

                KosTextField {
                    id: dueTimeField
                    Layout.preferredWidth: 96
                    placeholderText: "HH:MM"
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("Task due time")
                }

                KosCheckBox {
                    id: allDayCheck
                    text: qsTr("All day")
                }
            }

            Label {
                Layout.fillWidth: true
                text: root.linkedEventId.length > 0
                    ? qsTr("A linked task must keep a due date because it defines the event time.")
                    : qsTr("Tasks without a due date do not appear in Calendar.")
                color: AppTheme.mutedText
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Label { text: qsTr("Notes"); color: AppTheme.mutedText }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 130

                KosTextArea {
                    id: notesField
                    placeholderText: qsTr("Optional notes")
                    wrapMode: TextEdit.Wrap
                }
            }

            KosButton {
                text: qsTr("Delete task")
                destructive: true
                onClicked: {
                    root.deleteRequested(root.editingId)
                    root.close()
                }
            }
        }
    }
}
