pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

Dialog {
    id: root

    property string editingId: ""
    property string calendarId: "personal"
    property string linkedTodoId: ""
    property var availableLists: []
    readonly property bool editing: editingId.length > 0

    signal saveRequested(string uid, var event)
    signal deleteRequested(string uid)

    title: editing ? qsTr("Edit event") : qsTr("New event")
    modal: true
    width: Math.min(620, parent ? parent.width - 48 : 620)
    height: Math.min(730, parent ? parent.height - 48 : 730)
    anchors.centerIn: parent
    standardButtons: Dialog.Save | Dialog.Cancel

    function twoDigits(value) {
        return value < 10 ? "0" + value : String(value)
    }

    function dateText(date) {
        return date.getFullYear() + "-" + twoDigits(date.getMonth() + 1)
            + "-" + twoDigits(date.getDate())
    }

    function nextDateText(date) {
        const next = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1)
        return dateText(next)
    }

    function nextDateFromText(value) {
        const parsed = new Date(String(value) + "T12:00:00")
        return Number.isNaN(parsed.getTime()) ? String(value) : nextDateText(parsed)
    }

    function isoDatePart(value, fallback) {
        const match = String(value ?? "").match(/^(\d{4}-\d{2}-\d{2})/)
        return match ? match[1] : fallback
    }

    function isoTimePart(value, fallback) {
        const match = String(value ?? "").match(/T(\d{2}:\d{2})/)
        return match ? match[1] : fallback
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

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        const result = record[key]
        return result === undefined || result === null ? fallback : result
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

    function openForDate(date, hour) {
        const startHour = hour === undefined ? 9 : Math.max(0, Math.min(22, Number(hour)))
        editingId = ""
        calendarId = "personal"
        linkedTodoId = ""
        titleField.text = ""
        descriptionField.text = ""
        locationField.text = ""
        startDateField.text = dateText(date)
        endDateField.text = dateText(date)
        startTimeField.text = twoDigits(startHour) + ":00"
        endTimeField.text = twoDigits(startHour + 1) + ":00"
        allDayCheck.checked = false
        recurrenceBox.currentIndex = 0
        reminderBox.currentIndex = 0
        linkTodoCheck.checked = false
        todoListBox.currentIndex = listIndex("personal")
        todoPriorityBox.currentIndex = 0
        open()
        titleField.forceActiveFocus()
    }

    function openForEvent(event) {
        const now = new Date()
        const fallbackDate = dateText(now)
        editingId = String(event?.seriesId ?? event?.id ?? "")
        calendarId = String(event?.calendarId ?? "personal")
        linkedTodoId = String(event?.linkedTodoId ?? "")
        titleField.text = String(event?.title ?? "")
        descriptionField.text = String(event?.description ?? "")
        locationField.text = String(event?.location ?? "")
        startDateField.text = isoDatePart(event?.start, fallbackDate)
        endDateField.text = isoDatePart(event?.end, startDateField.text)
        startTimeField.text = isoTimePart(event?.start, "09:00")
        endTimeField.text = isoTimePart(event?.end, "10:00")
        allDayCheck.checked = Boolean(event?.allDay)
        recurrenceBox.currentIndex = recurrenceIndex(event?.recurrence)
        reminderBox.currentIndex = reminderIndex(event?.reminderMinutes)
        linkTodoCheck.checked = linkedTodoId.length > 0
        todoListBox.currentIndex = listIndex(event?.linkedTodoListId ?? "personal")
        todoPriorityBox.currentIndex = priorityIndex(event?.linkedTodoPriority ?? 0)
        open()
        titleField.forceActiveFocus()
    }

    function eventPayload() {
        const recurrenceValues = ["none", "daily", "weekly", "monthly", "yearly"]
        const reminderValues = [-1, 0, 5, 15, 30, 60, 1440]
        const priorityValues = [0, 9, 5, 1]
        const list = availableLists.length > 0
            ? availableLists[Math.max(0, todoListBox.currentIndex)] : ({ id: "inbox" })
        return {
            title: titleField.text.trim(),
            description: descriptionField.text.trim(),
            location: locationField.text.trim(),
            start: startDateField.text.trim() + "T"
                + (allDayCheck.checked ? "00:00" : startTimeField.text.trim()) + ":00",
            end: endDateField.text.trim() + "T"
                + (allDayCheck.checked ? "00:00" : endTimeField.text.trim()) + ":00",
            allDay: allDayCheck.checked,
            calendarId: calendarId,
            recurrence: recurrenceValues[recurrenceBox.currentIndex],
            reminderMinutes: reminderValues[reminderBox.currentIndex],
            linkedTodo: linkTodoCheck.checked,
            todoListId: String(value(list, "id", "inbox")),
            todoPriority: priorityValues[todoPriorityBox.currentIndex]
        }
    }

    onAccepted: saveRequested(editingId, eventPayload())

    contentItem: ScrollView {
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 12

            Label {
                text: qsTr("Title")
                color: AppTheme.mutedText
            }

            LiquidTextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: qsTr("Event title")
                Accessible.name: qsTr("Event title")
            }

            RowLayout {
                Layout.fillWidth: true

                CheckBox {
                    id: allDayCheck
                    text: qsTr("All day")
                    onToggled: {
                        const next = root.nextDateFromText(startDateField.text.trim())
                        if (checked && endDateField.text.trim() === startDateField.text.trim())
                            endDateField.text = next
                        else if (!checked && endDateField.text.trim() === next)
                            endDateField.text = startDateField.text.trim()
                    }
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: qsTr("Use YYYY-MM-DD and 24-hour time")
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 10
                rowSpacing: 8

                Label { text: qsTr("Start"); color: AppTheme.mutedText }
                LiquidTextField {
                    id: startDateField
                    Layout.fillWidth: true
                    placeholderText: "YYYY-MM-DD"
                    Accessible.name: qsTr("Start date")
                }
                LiquidTextField {
                    id: startTimeField
                    Layout.preferredWidth: 96
                    placeholderText: "HH:MM"
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("Start time")
                }

                Label { text: qsTr("End"); color: AppTheme.mutedText }
                LiquidTextField {
                    id: endDateField
                    Layout.fillWidth: true
                    placeholderText: "YYYY-MM-DD"
                    Accessible.name: qsTr("End date")
                }
                LiquidTextField {
                    id: endTimeField
                    Layout.preferredWidth: 96
                    placeholderText: "HH:MM"
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("End time")
                }
            }

            Label { text: qsTr("Location"); color: AppTheme.mutedText }
            LiquidTextField {
                id: locationField
                Layout.fillWidth: true
                placeholderText: qsTr("Optional location")
                Accessible.name: qsTr("Event location")
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: todoLinkLayout.implicitHeight + 24
                radius: AppTheme.smallRadius
                color: AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.13 : 0.08)
                border.width: 1
                border.color: AppTheme.withAlpha(AppTheme.accent, 0.24)

                ColumnLayout {
                    id: todoLinkLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    CheckBox {
                        id: linkTodoCheck
                        text: qsTr("Also show this event as a task in Todo")
                        font.weight: Font.DemiBold
                        Accessible.description: qsTr("The title and schedule stay synchronized")
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.linkedTodoId.length > 0 && !linkTodoCheck.checked
                            ? qsTr("Saving will unlink the existing task but keep it in Todo.")
                            : qsTr("Changes to the title or date will be reflected in both apps.")
                        color: root.linkedTodoId.length > 0 && !linkTodoCheck.checked
                            ? AppTheme.warning : AppTheme.mutedText
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: linkTodoCheck.checked

                        ColumnLayout {
                            Layout.fillWidth: true
                            Label { text: qsTr("Todo list"); color: AppTheme.mutedText }
                            ComboBox {
                                id: todoListBox
                                Layout.fillWidth: true
                                model: root.availableLists
                                textRole: "name"
                                Accessible.name: qsTr("Linked todo list")
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Label { text: qsTr("Priority"); color: AppTheme.mutedText }
                            ComboBox {
                                id: todoPriorityBox
                                Layout.fillWidth: true
                                model: [qsTr("None"), qsTr("Low"), qsTr("Medium"),
                                    qsTr("High")]
                                Accessible.name: qsTr("Linked todo priority")
                            }
                        }
                    }
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
                        Accessible.name: qsTr("Event recurrence")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Reminder"); color: AppTheme.mutedText }
                    ComboBox {
                        id: reminderBox
                        Layout.fillWidth: true
                        model: [qsTr("None"), qsTr("At start"), qsTr("5 minutes before"),
                            qsTr("15 minutes before"), qsTr("30 minutes before"),
                            qsTr("1 hour before"), qsTr("1 day before")]
                        Accessible.name: qsTr("Event reminder")
                    }
                }
            }

            Label { text: qsTr("Notes"); color: AppTheme.mutedText }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 130

                TextArea {
                    id: descriptionField
                    placeholderText: qsTr("Optional notes")
                    wrapMode: TextEdit.Wrap
                    Accessible.name: qsTr("Event notes")
                }
            }

            Button {
                Layout.alignment: Qt.AlignLeft
                text: qsTr("Delete event")
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
