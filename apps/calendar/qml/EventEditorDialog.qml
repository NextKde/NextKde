pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosWorkspaceDialog {
    id: root

    property string editingId: ""
    property string calendarId: "personal"
    property string linkedTodoId: ""
    property var availableLists: []
    readonly property bool editing: editingId.length > 0

    signal saveRequested(string uid, var event)
    signal deleteRequested(string uid)

    // P02: one consistent field height for every editor control.
    readonly property int fieldHeight: 30

    title: editing ? qsTr("Edit event") : qsTr("New event")
    modal: true
    // P02/P03: compact editor — 380 wide, and never taller than the client
    // viewport minus margins so the footer stays reachable at 760x540.
    width: Math.min(380, parent ? parent.width - 48 : 380)
    height: Math.min(620, parent ? parent.height - 64 : 620)
    anchors.centerIn: parent
    standardButtons: Dialog.Save | Dialog.Cancel
    // P02: calendar-local neutral surface — the shared blue-gray windowRaised
    // tint is replaced with a flat neutral panel; same elevation language.
    background: KosSurface {
        radius: AppTheme.smallRadius + 4
        fillColor: AppTheme.dark ? "#262626" : "#F7F7F7"
        elevation: 0.5
    }

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

    contentItem: Flickable {
        id: editorScroll
        clip: true
        // Non-interactive form (see task editor): the outer drag filter is
        // the last press competitor for the notes area; dragging the form is
        // not needed — it scrolls by wheel only. Explicit Flickable (not
        // ScrollView) because `interactive` is a real Flickable property and
        // ScrollView has none.
        interactive: false
        contentWidth: width
        contentHeight: formLayout.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) {
                const max = Math.max(0, editorScroll.contentHeight
                                         - editorScroll.height)
                const step = wheel.pixelDelta.y !== 0
                    ? wheel.pixelDelta.y
                    : wheel.angleDelta.y / 2
                editorScroll.contentY = Math.max(0, Math.min(
                    max, editorScroll.contentY - step))
                wheel.accepted = true
            }
        }

        // P02: aligned label-left rows with one field height; compact 380
        // editor keeps every existing field, just visually tamed.
        ColumnLayout {
            id: formLayout
            width: editorScroll.width
            spacing: 10

            Label {
                text: qsTr("Title")
                color: AppTheme.mutedText
                font.pixelSize: 11
            }

            KosTextField {
                id: titleField
                Layout.fillWidth: true
                Layout.preferredHeight: fieldHeight
                placeholderText: qsTr("Event title")
                Accessible.name: qsTr("Event title")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                KosCheckBox {
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
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 8
                rowSpacing: 8

                Label { text: qsTr("Start"); color: AppTheme.mutedText; font.pixelSize: 11 }
                KosTextField {
                    id: startDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: "YYYY-MM-DD"
                    Accessible.name: qsTr("Start date")
                }
                Label { text: qsTr("End"); color: AppTheme.mutedText; font.pixelSize: 11 }
                KosTextField {
                    id: endDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: "YYYY-MM-DD"
                    Accessible.name: qsTr("End date")
                }

                Item { Layout.fillWidth: true }
                KosTextField {
                    id: startTimeField
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: fieldHeight
                    placeholderText: "HH:MM"
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("Start time")
                }
                Item { Layout.fillWidth: true }
                KosTextField {
                    id: endTimeField
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: fieldHeight
                    placeholderText: "HH:MM"
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("End time")
                }
            }

            Label { text: qsTr("Location"); color: AppTheme.mutedText; font.pixelSize: 11 }
            KosTextField {
                id: locationField
                Layout.fillWidth: true
                Layout.preferredHeight: fieldHeight
                placeholderText: qsTr("Optional location")
                Accessible.name: qsTr("Event location")
            }

            // P02: subdued task link — same semantics, quiet neutral chip
            // instead of the large blue card. List/priority reveal only
            // while linked.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                KosCheckBox {
                    id: linkTodoCheck
                    text: qsTr("Also show this event as a task in Todo")
                    Accessible.description: qsTr("The title and schedule stay synchronized")
                }

                Label {
                    Layout.fillWidth: true
                    text: root.linkedTodoId.length > 0 && !linkTodoCheck.checked
                        ? qsTr("Saving will unlink the existing task but keep it in Todo.")
                        : qsTr("Changes to the title or date will be reflected in both apps.")
                    visible: linkTodoCheck.checked
                        || (root.linkedTodoId.length > 0 && !linkTodoCheck.checked)
                    color: root.linkedTodoId.length > 0 && !linkTodoCheck.checked
                        ? AppTheme.warning : AppTheme.mutedText
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: linkTodoCheck.checked
                    spacing: 8

                    Label { text: qsTr("Todo list"); color: AppTheme.mutedText; font.pixelSize: 11 }
                    KosComboBox {
                        id: todoListBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: fieldHeight
                        model: root.availableLists
                        textRole: "name"
                        Accessible.name: qsTr("Linked todo list")
                    }
                    Label { text: qsTr("Priority"); color: AppTheme.mutedText; font.pixelSize: 11 }
                    KosComboBox {
                        id: todoPriorityBox
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: fieldHeight
                        model: [qsTr("None"), qsTr("Low"), qsTr("Medium"),
                            qsTr("High")]
                        Accessible.name: qsTr("Linked todo priority")
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label { text: qsTr("Repeat"); color: AppTheme.mutedText; font.pixelSize: 11 }
                KosComboBox {
                    id: recurrenceBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    model: [qsTr("Does not repeat"), qsTr("Daily"), qsTr("Weekly"),
                        qsTr("Monthly"), qsTr("Yearly")]
                    Accessible.name: qsTr("Event recurrence")
                }
                Label { text: qsTr("Reminder"); color: AppTheme.mutedText; font.pixelSize: 11 }
                KosComboBox {
                    id: reminderBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    model: [qsTr("None"), qsTr("At start"), qsTr("5 minutes before"),
                        qsTr("15 minutes before"), qsTr("30 minutes before"),
                        qsTr("1 hour before"), qsTr("1 day before")]
                    Accessible.name: qsTr("Event reminder")
                }
            }

            Label { text: qsTr("Notes"); color: AppTheme.mutedText; font.pixelSize: 11 }
            // Canonical editable-notes scroller, same as the task editor.
            // P02: fixed neutral frame around the notes viewport — same
            // treatment as the task editor.
            Item {
                id: notesFrame
                Layout.fillWidth: true
                Layout.preferredHeight: 96

                KosSurface {
                    anchors.fill: parent
                    radius: AppTheme.smallRadius
                    fillColor: AppTheme.fieldSurface
                    elevation: 0
                    focused: descriptionField.activeFocus
                }

                Flickable {
                    id: notesScroll
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // Non-interactive (see task editor): wheel + scrollbar
                    // scrolling, presses always reach the editor.
                    interactive: false
                    // Native TextArea.flickable attached integration — the
                    // attached property is on the Flickable, its value is
                    // the TextArea; native pointer/cursor/selection ownership.
                    TextArea.flickable: KosTextArea {
                        id: descriptionField
                        width: notesScroll.width
                        placeholderText: qsTr("Optional notes")
                        wrapMode: TextEdit.Wrap
                        Accessible.name: qsTr("Event notes")
                        background: null
                        activeFocusOnPress: true
                        selectByMouse: true
                    }

                    ScrollBar.vertical: ScrollBar {}

                    // Wheel scrolling for the non-interactive flickable —
                    // same NoButton MouseArea pattern as the task editor:
                    // wheel-only, clicks/drag-selection pass through, and
                    // the outer form does not move.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: function(wheel) {
                            const max = Math.max(0, notesScroll.contentHeight
                                                     - notesScroll.height)
                            const step = wheel.pixelDelta.y !== 0
                                ? wheel.pixelDelta.y
                                : wheel.angleDelta.y / 2
                            notesScroll.contentY = Math.max(0, Math.min(
                                max, notesScroll.contentY - step))
                            wheel.accepted = true
                        }
                    }
                }
            }

            KosButton {
                Layout.alignment: Qt.AlignLeft
                text: qsTr("Delete event")
                visible: root.editing
                destructive: true
                onClicked: {
                    root.deleteRequested(root.editingId)
                    root.close()
                }
            }
        }
    }
}
