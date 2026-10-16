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
    readonly property int labelColumnWidth: 56

    title: editing ? qsTr("Edit event") : qsTr("New event")
    modal: true
    // P02/P03: compact editor — 380 wide, and never taller than the client
    // viewport minus margins so the footer stays reachable at 760x540.
    width: Math.min(380, parent ? parent.width - 48 : 380)
    height: Math.min(620, parent ? parent.height - 32 : 620)
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

    // D05: the dialog's actions are stacked, not a row — one full-width bar
    // per action, all the same width and height with a hairline gap, primary
    // (Save) on top, secondary (Cancel) under it, destructive (Delete) last,
    // per the macOS 26 alert reference. KosButton supplies the 34px control
    // height and the pill radius; nothing here restyles surface or shape.
    // The footer stays fixed (only the form above it scrolls), so Delete can
    // never scroll out of reach; the 16px insets match the shared footer.
    //
    // Labels are not hardcoded: standardButtons is still declared on the
    // dialog, and the never-rendered DialogButtonBox below instantiates Qt's
    // platform-localized Save/Cancel buttons, so the bars read exactly as the
    // standard buttons did. A DialogButtonBox nested inside a footer Item is
    // not auto-wired to the dialog (only a DialogButtonBox used directly *as*
    // the footer is), so accept/reject are called explicitly here — and the
    // button texts, which do not exist until the tree is complete, are copied
    // in onCompleted rather than bound.
    property string saveLabel: qsTr("Save")
    property string cancelLabel: qsTr("Cancel")

    Component.onCompleted: {
        const save = labelSource.standardButton(Dialog.Save)
        const cancel = labelSource.standardButton(Dialog.Cancel)
        if (save)
            saveLabel = save.text
        if (cancel)
            cancelLabel = cancel.text
    }

    footer: Item {
        implicitHeight: 16 + footerCol.implicitHeight + 16

        // Label source only. Invisible and disabled so it neither paints over
        // the stack nor joins the focus chain — Esc stays with the dialog.
        DialogButtonBox {
            id: labelSource
            visible: false
            enabled: false
            padding: 0
            standardButtons: root.standardButtons
        }

        ColumnLayout {
            id: footerCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6

            // Primary: the AcceptRole standard button of the shared footer.
            KosButton {
                Layout.fillWidth: true
                text: root.saveLabel
                highlighted: true
                onClicked: root.accept()
            }

            // Secondary: the RejectRole standard button of the shared footer.
            KosButton {
                Layout.fillWidth: true
                text: root.cancelLabel
                secondary: true
                onClicked: root.reject()
            }

            KosButton {
                Layout.fillWidth: true
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

        // P03: macOS overlay scrollbar — floats over the form, no track, so a
        // clipped form reads as scrollable instead of as a rendering fault.
        ScrollBar.vertical: ScrollBar {
            id: formScrollBar
            policy: ScrollBar.AsNeeded
            width: 6
            background: Item {}
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: AppTheme.withAlpha(AppTheme.blackSeed,
                                          AppTheme.dark ? 0.40 : 0.30)
            }
        }

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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("Title")
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("Start")
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                }
                KosTextField {
                    id: startDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: "YYYY-MM-DD"
                    Accessible.name: qsTr("Start date")
                }
                KosTextField {
                    id: startTimeField
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: fieldHeight
                    placeholderText: "HH:MM"
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("Start time")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("End")
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                }
                KosTextField {
                    id: endDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: "YYYY-MM-DD"
                    Accessible.name: qsTr("End date")
                }
                KosTextField {
                    id: endTimeField
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: fieldHeight
                    placeholderText: "HH:MM"
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("End time")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("Location")
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                }
                KosTextField {
                    id: locationField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: qsTr("Optional location")
                    Accessible.name: qsTr("Event location")
                }
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

                Label {
                    text: qsTr("Repeat")
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                }
                KosComboBox {
                    id: recurrenceBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    model: [qsTr("Does not repeat"), qsTr("Daily"), qsTr("Weekly"),
                        qsTr("Monthly"), qsTr("Yearly")]
                    Accessible.name: qsTr("Event recurrence")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("Reminder")
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                }
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("Notes")
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignTop
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                }

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
            }
        }
    }
}
