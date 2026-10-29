pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

Demo.LiquidContentPopover {
    id: root
    borderWidth: 0.5
    borderColor: AppTheme.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)
    materialOpacity: 0.99
    // Tall editors keep the floating material without a misleading pointer.
    arrowEnabled: false
    // Suppress background lettering while retaining sampled colour and refraction.
    backdropBlur: 1.0
    blurStrength: 1.0
    tintStrength: 0.42
    CalendarStyle { id: design }

    property string editingId: ""
    // Retain imported/existing locations while the location editor is unavailable.
    property string savedLocation: ""
    property bool saving: false
    property bool scheduleExpanded: false
    closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    property string calendarId: "default"
    property string linkedTodoId: ""
    property var availableLists: []
    property var availableCategories: []
    property int originalRecurrenceIndex: 0
    property int originalReminderIndex: 0
    property bool customRecurrence: false
    property int savedReminderMinutes: -1
    readonly property bool customReminder: ![-1, 0, 5, 15, 30, 60, 1440].includes(savedReminderMinutes)
    readonly property bool editing: editingId.length > 0

    signal saveRequested(string uid, var event)
    signal deleteRequested(string uid)

    // P02: one consistent field height for every editor control.
    readonly property int fieldHeight: design.fieldHeight
    readonly property int labelColumnWidth: 56

    title: editing ? qsTr("Edit event") : qsTr("New event")
    modal: false
    popupType: Popup.Item
    // P02/P03: compact editor — 420 wide, and never taller than the client
    // viewport minus margins so the footer stays reachable at 760x540.
    width: Math.min(360, parent ? parent.width - 16 : 360)
    height: Math.min((header ? header.implicitHeight : 0) + (footer ? footer.implicitHeight : 0)
        + formLayout.implicitHeight + topPadding + bottomPadding, parent ? parent.height - 16 : 560)
    standardButtons: Dialog.Save | Dialog.Cancel
    padding: 16
    signal switchTypeRequested()
    header: CalendarEditorTabs {
        visible: root.editingId.length === 0
        implicitHeight: visible ? 82 : 0
        leftInset: root.leftPadding
        // Match the form width, including its 8px scrollbar gutter.
        rightInset: root.rightPadding + 8
        currentIndex: 0
        switchingEnabled: root.editingId.length === 0 && !root.saving
        onSwitchRequested: root.switchTypeRequested()
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
        return Qt.formatDate(next, inputDateFormat)
    }

    function nextDateFromText(value) {
        const parsed = parseDateText(value)
        return parsed === null ? String(value) : nextDateText(parsed)
    }

    function isoDatePart(value, fallback) {
        const match = String(value ?? "").match(/^(\d{4}-\d{2}-\d{2})/)
        return match ? match[1] : fallback
    }

    function isoTimePart(value, fallback) {
        const match = String(value ?? "").match(/T(\d{2}:\d{2})/)
        return match ? match[1] : fallback
    }

    // I7 (REVIEW): date/time fields speak the locale's short format — the
    // placeholder shows the locale's field order, seeds and parsing use it,
    // and plain ISO stays accepted (copy/paste). Records are still assembled
    // as ISO at payload time; unparsable input must block accept (I4)
    // instead of storing a broken record.
    readonly property var inputLocale: Qt.locale()
    readonly property string inputDateFormat: {
        const fmt = String(inputLocale.dateFormat(Locale.ShortFormat))
        // Upgrade a 2-digit short-format year so the year stays unambiguous.
        return /yyyy/.test(fmt) ? fmt : fmt.replace(/yy/, "yyyy")
    }
    readonly property string inputTimeFormat: inputLocale.timeFormat(Locale.ShortFormat)
    readonly property string datePattern: inputPattern(inputDateFormat)
    readonly property string timePattern: inputPattern(inputTimeFormat)

    function inputPattern(format) {
        return String(format).replace(
            /yyyy|yy|MM|M|dd|d|mm|m|HH|H|h|AP|ap/g,
            function (token) {
                if (token === "yyyy" || token === "yy") return "YYYY"
                if (token === "MM" || token === "M"
                        || token === "mm" || token === "m") return "MM"
                if (token === "dd" || token === "d") return "DD"
                if (token === "HH") return "HH"
                if (token === "H" || token === "h") return "H"
                if (token === "AP") return "AM/PM"
                if (token === "ap") return "am/pm"
                return token
            })
    }

    function parseDateText(value) {
        const text = String(value ?? "").trim()
        if (text.length === 0)
            return null
        const match = text.match(/^(\d{4})-(\d{2})-(\d{2})$/)
        if (match) {
            const date = new Date(Number(match[1]), Number(match[2]) - 1,
                Number(match[3]))
            // Reject calendar rollovers (2026-02-30 → Mar 2) via round-trip.
            return date.getFullYear() === Number(match[1])
                && date.getMonth() === Number(match[2]) - 1
                && date.getDate() === Number(match[3]) ? date : null
        }
        const parsed = Date.fromLocaleDateString(inputLocale, text, inputDateFormat)
        return Number.isNaN(parsed.getTime()) ? null : parsed
    }

    function parseTimeText(value) {
        const text = String(value ?? "").trim()
        if (text.length === 0)
            return null
        const match = text.match(/^(\d{2}):(\d{2})$/)
        if (match) {
            const hours = Number(match[1])
            const minutes = Number(match[2])
            return hours <= 23 && minutes <= 59 ? hours * 60 + minutes : null
        }
        const parsed = Date.fromLocaleTimeString(inputLocale, text, inputTimeFormat)
        return Number.isNaN(parsed.getTime())
            ? null : parsed.getHours() * 60 + parsed.getMinutes()
    }

    // I7: seeds are shown in the locale format, payloads store ISO.
    function formatDateInput(value) {
        const parsed = parseDateText(value)
        return parsed === null ? String(value ?? "").trim()
            : Qt.formatDate(parsed, inputDateFormat)
    }

    function formatTimeInput(value) {
        const minutes = parseTimeText(value)
        return minutes === null ? String(value ?? "").trim()
            : Qt.formatTime(new Date(2000, 0, 1, Math.floor(minutes / 60),
                minutes % 60), inputTimeFormat)
    }

    function isoFromDateText(value) {
        const parsed = parseDateText(value)
        return parsed === null ? String(value ?? "").trim()
            : Qt.formatDate(parsed, "yyyy-MM-dd")
    }

    function isoFromTimeText(value) {
        const minutes = parseTimeText(value)
        return minutes === null ? String(value ?? "").trim()
            : twoDigits(Math.floor(minutes / 60)) + ":" + twoDigits(minutes % 60)
    }

    // I4: last validation problem, kept until the offending field is edited
    // or the dialog reopens. null = clean.
    property string errorText: ""
    property var errorFields: []

    // P1-6: delete is a two-step destructive action — the Delete bar only
    // arms the inline confirmation (below); the actual deleteRequested fires
    // from the confirmation step. Reset on every open.
    property bool confirmingDelete: false

    // Inline error copy sits at 11px non-bold → needs 4.5:1. AppTheme
    // .destructive is 4.25:1 on the light panel (#F7F7F7); #d23636 is the
    // minimal darkening that passes (4.54:1, measured per WCAG formula).
    // Dark #ff6961 on #262626 = 5.37:1, so dark keeps the token.
    readonly property color errorColor: AppTheme.dark
        ? AppTheme.destructive : "#d23636"

    function hasError(name) {
        return errorFields.includes(name)
    }

    function clearError(name) {
        if (!errorFields.includes(name))
            return
        const rest = errorFields.filter(function(field) { return field !== name })
        errorFields = rest
        if (rest.length === 0)
            errorText = ""
    }

    function validationProblem() {
        if (titleField.text.trim().length === 0)
            return { message: qsTr("Title is required."), fields: ["title"] }
        const startDate = parseDateText(startDateField.text)
        if (startDate === null)
            return { message: qsTr("Start date must be %1.").arg(datePattern),
                fields: ["startDate"] }
        const endDate = parseDateText(endDateField.text)
        if (endDate === null)
            return { message: qsTr("End date must be %1.").arg(datePattern),
                fields: ["endDate"] }
        let startMinutes = 0
        let endMinutes = 0
        if (!allDayCheck.checked) {
            startMinutes = parseTimeText(startTimeField.text)
            if (startMinutes === null)
                return { message: qsTr("Start time must be %1.").arg(timePattern),
                    fields: ["startTime"] }
            endMinutes = parseTimeText(endTimeField.text)
            if (endMinutes === null)
                return { message: qsTr("End time must be %1.").arg(timePattern),
                    fields: ["endTime"] }
        }
        if (endDate < startDate)
            return { message: qsTr("End must not be before start."),
                fields: ["endDate"] }
        if (!allDayCheck.checked
                && endDate.getTime() === startDate.getTime()
                && endMinutes <= startMinutes)
            return { message: qsTr("End time must be after start time."),
                fields: ["endTime"] }
        return null
    }

    function recurrenceIndex(preset) {
        const values = ["none", "daily", "weekly", "monthly", "yearly"]
        const index = values.indexOf(String(preset ?? "none"))
        return index >= 0 ? index : 5
    }

    function reminderIndex(minutes) {
        const values = [-1, 0, 5, 15, 30, 60, 1440]
        const index = values.indexOf(Number(minutes))
        return index >= 0 ? index : 7
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

    function setTimeRange(start, end) {
        startDateField.text = formatDateInput(dateText(start))
        endDateField.text = formatDateInput(dateText(end))
        startTimeField.text = formatTimeInput(twoDigits(start.getHours()) + ":" + twoDigits(start.getMinutes()))
        endTimeField.text = formatTimeInput(twoDigits(end.getHours()) + ":" + twoDigits(end.getMinutes()))
    }
    function setQuickTitle(text) { titleField.text = text }
    function applyReminderDraft(draft) {
        titleField.text = draft.title
        descriptionField.text = draft.description
        calendarId = draft.calendarId
        categoryBox.currentIndex = Math.max(0, availableCategories.findIndex(item => item.id === calendarId))
        allDayCheck.checked = draft.allDay
        if (draft.allDay) endDateField.text = nextDateFromText(startDateField.text)
    }
    function openForDate(date, hour) {
        const startHour = hour === undefined ? 9 : Math.max(0, Math.min(22, Number(hour)))
        scheduleExpanded = false
        editingId = ""
        calendarId = "default"
        categoryBox.currentIndex = 0
        linkedTodoId = ""
        errorText = ""
        errorFields = []
        confirmingDelete = false
        titleField.text = ""
        descriptionField.text = ""
        savedLocation = ""
        startDateField.text = formatDateInput(dateText(date))
        endDateField.text = formatDateInput(dateText(date))
        startTimeField.text = formatTimeInput(twoDigits(startHour) + ":00")
        endTimeField.text = formatTimeInput(twoDigits(startHour + 1) + ":00")
        allDayCheck.checked = false
        customRecurrence = false
        savedReminderMinutes = -1
        recurrenceBox.currentIndex = 0
        reminderBox.currentIndex = 0
        originalRecurrenceIndex = 0
        originalReminderIndex = 0
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
        categoryBox.currentIndex = Math.max(0, availableCategories.findIndex(item => item.id === calendarId))
        confirmingDelete = false
        linkedTodoId = String(event?.linkedTodoId ?? "")
        errorText = ""
        errorFields = []
        titleField.text = String(event?.title ?? "")
        descriptionField.text = String(event?.description ?? "")
        savedLocation = String(event?.location ?? "")
        startDateField.text = formatDateInput(isoDatePart(event?.start, fallbackDate))
        endDateField.text = formatDateInput(isoDatePart(event?.end, startDateField.text))
        startTimeField.text = formatTimeInput(isoTimePart(event?.start, "09:00"))
        endTimeField.text = formatTimeInput(isoTimePart(event?.end, "10:00"))
        allDayCheck.checked = Boolean(event?.allDay)
        customRecurrence = String(event?.recurrence ?? "none") === "custom"
        savedReminderMinutes = Number(event?.reminderMinutes ?? -1)
        recurrenceBox.currentIndex = recurrenceIndex(event?.recurrence)
        reminderBox.currentIndex = reminderIndex(event?.reminderMinutes)
        originalRecurrenceIndex = recurrenceBox.currentIndex
        originalReminderIndex = reminderBox.currentIndex
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
        const payload = {
            title: titleField.text.trim(),
            description: descriptionField.text.trim(),
            location: savedLocation,
            start: isoFromDateText(startDateField.text) + "T"
                + (allDayCheck.checked ? "00:00" : isoFromTimeText(startTimeField.text)) + ":00",
            end: isoFromDateText(endDateField.text) + "T"
                + (allDayCheck.checked ? "00:00" : isoFromTimeText(endTimeField.text)) + ":00",
            allDay: allDayCheck.checked,
            calendarId: calendarId,
            recurrence: recurrenceValues[recurrenceBox.currentIndex],
            reminderMinutes: reminderValues[reminderBox.currentIndex],
            linkedTodo: linkTodoCheck.checked,
            todoListId: String(value(list, "id", "inbox")),
            todoPriority: priorityValues[todoPriorityBox.currentIndex]
        }
        // Preserve imported custom rules, repeat limits and alarm offsets when
        // editing an unrelated field. The backend supports partial updates.
        if (editing && recurrenceBox.currentIndex === originalRecurrenceIndex)
            delete payload.recurrence
        if (editing && reminderBox.currentIndex === originalReminderIndex)
            delete payload.reminderMinutes
        return payload
    }

    // I4: every accept path runs validation first — invalid input keeps the
    // dialog open and reports inline instead of storing a broken record.
    function accept() {
        const problem = validationProblem()
        if (problem !== null) {
            errorText = problem.message
            errorFields = problem.fields
            scheduleExpanded = true
            return
        }
        errorText = ""
        errorFields = []
        accepted()
    }

    onAccepted: saveRequested(editingId, eventPayload())

    // Fixed compact action row; the form scrolls independently.
    footer: CalendarEditorFooter {
        sourceItem: root.sourceItem
        enabled: !root.saving
        editing: root.editingId.length > 0
        confirmingDelete: root.confirmingDelete
        deleteLabel: qsTr("Delete event")
        deleteTitle: qsTr("Delete this event?")
        deleteMessage: qsTr("The event is removed from every view. This cannot be undone.")
        onAccepted: root.accept()
        onRejected: root.reject()
        onDeleteArmed: root.confirmingDelete = true
        onDeleteCanceled: root.confirmingDelete = false
        onDeleteConfirmed: {
            root.deleteRequested(root.editingId)
            root.close()
        }
    }

    contentItem: Flickable {
        id: editorScroll
        enabled: !root.saving
        objectName: "calendarEventEditorScroll"
        clip: true
        // P1-18/A7: the custom footer hides the standard DialogButtonBox
        // that would normally wire a default button, so Return used to do
        // nothing in the form. Return bubbles up here from every field, so
        // submit the form from the dialog's own content item. The multiline
        // notes TextArea consumes Return for newlines and never reaches
        // this; while the delete confirmation is up, Save must not fire
        // (Cancel is the focused default there).
        Keys.onReturnPressed: function(event) {
            if (root.confirmingDelete)
                return
            root.accept()
            event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
            if (root.confirmingDelete)
                return
            root.accept()
            event.accepted = true
        }
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

        // P02: aligned label-left rows with one field height; compact 420
        // editor keeps every existing field, just visually tamed.
        ColumnLayout {
            id: formLayout
            width: editorScroll.width - 8
            spacing: 8

            // I4: inline validation error — pinned to the top of the form so
            // it is visible without scrolling; offending fields also get a
            // destructive outline until they are edited.
            Label {
                Layout.fillWidth: true
                visible: root.errorText.length > 0
                text: root.errorText
                color: root.errorColor
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Pane {
                Layout.fillWidth: true
                padding: 0
                background: Item {}
                contentItem: RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: qsTr("Category") + ":"; Layout.preferredWidth: root.labelColumnWidth; color: AppTheme.mutedText; font.pixelSize: 13; font.weight: Font.Bold }
                            CalendarComboBox {
                    id: categoryBox
                    objectName: "eventCategory"
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldHeight
                    model: root.availableCategories
                    textRole: "name"
                    colorRole: "color"
                    Accessible.name: qsTr("Category")
                    onActivated: root.calendarId = root.availableCategories[currentIndex].id
                }
            }
            }

            Pane {
                Layout.fillWidth: true
                padding: 0
                background: Item {}
                contentItem: ColumnLayout { spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 8



                Label { text: qsTr("Title") + ":"; Layout.preferredWidth: root.labelColumnWidth; color: AppTheme.mutedText; font.pixelSize: 13; font.weight: Font.Bold }
                CalendarTextField {
                    font.pixelSize: design.editorInputFontSize
                    font.weight: Font.Normal
                    id: titleField
                    objectName: "eventTitle"
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: qsTr("Event title")
                    Accessible.name: qsTr("Event title")
                    invalid: root.hasError("title")
                    outlineColor: root.hasError("title")
                        ? AppTheme.destructive : "transparent"
                    onTextChanged: root.clearError("title")
                }
            }


                }
            }
            Pane {
                Layout.fillWidth: true
                padding: 0
                background: Item {}
                contentItem: ColumnLayout { spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label { text: qsTr("Time") + ":"; Layout.preferredWidth: root.labelColumnWidth; color: AppTheme.mutedText; font.pixelSize: 13; font.weight: Font.Bold }
                Button {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    background: Rectangle { radius: design.formGroupRadius; color: design.controlFill }
                    leftPadding: 12
                    rightPadding: 12
                    contentItem: ColumnLayout {
                        Label { text: startDateField.text + "  " + startTimeField.text + " – " + endTimeField.text; color: design.labelPrimary; font.pixelSize: 11 }
                        Label { text: root.scheduleExpanded ? qsTr("Hide date and notification options") : qsTr("Date, repeat and notification options"); color: design.labelSecondary; font.pixelSize: 11 }
                    }
                    onClicked: root.scheduleExpanded = !root.scheduleExpanded
                }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.scheduleExpanded
                    spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                CalendarCheckBox {
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
                    text: qsTr("Start") + ":"
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
                    color: AppTheme.mutedText
                    font.pixelSize: 13; font.weight: Font.Bold
                }
                CalendarDateField {
                    parseDate: root.parseDateText
                    formatDate: date => Qt.formatDate(date, root.inputDateFormat)
                    calendarLocale: root.inputLocale
                    font.pixelSize: design.editorInputFontSize
                    font.weight: Font.Normal
                    id: startDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: root.datePattern
                    Accessible.name: qsTr("Start date")
                    invalid: root.hasError("startDate")
                    outlineColor: root.hasError("startDate")
                        ? AppTheme.destructive : "transparent"
                    onTextChanged: root.clearError("startDate")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label {
                    text: qsTr("Start time") + ":"
                    Layout.preferredWidth: root.labelColumnWidth
                    color: AppTheme.mutedText
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
                CalendarTimeField {
                    parseTime: root.parseTimeText
                    formatTime: date => Qt.formatTime(date, root.inputTimeFormat)
                    font.pixelSize: design.editorInputFontSize
                    font.weight: Font.Normal
                    id: startTimeField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: root.timePattern
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("Start time")
                    invalid: root.hasError("startTime")
                    outlineColor: root.hasError("startTime")
                        ? AppTheme.destructive : "transparent"
                    onTextChanged: root.clearError("startTime")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("End") + ":"
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
                    color: AppTheme.mutedText
                    font.pixelSize: 13; font.weight: Font.Bold
                }
                CalendarDateField {
                    parseDate: root.parseDateText
                    formatDate: date => Qt.formatDate(date, root.inputDateFormat)
                    calendarLocale: root.inputLocale
                    font.pixelSize: design.editorInputFontSize
                    font.weight: Font.Normal
                    id: endDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: root.datePattern
                    Accessible.name: qsTr("End date")
                    invalid: root.hasError("endDate")
                    outlineColor: root.hasError("endDate")
                        ? AppTheme.destructive : "transparent"
                    onTextChanged: root.clearError("endDate")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label {
                    text: qsTr("End time") + ":"
                    Layout.preferredWidth: root.labelColumnWidth
                    color: AppTheme.mutedText
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
                CalendarTimeField {
                    parseTime: root.parseTimeText
                    formatTime: date => Qt.formatTime(date, root.inputTimeFormat)
                    font.pixelSize: design.editorInputFontSize
                    font.weight: Font.Normal
                    id: endTimeField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    placeholderText: root.timePattern
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("End time")
                    invalid: root.hasError("endTime")
                    outlineColor: root.hasError("endTime")
                        ? AppTheme.destructive : "transparent"
                    onTextChanged: root.clearError("endTime")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("Repeat") + ":"
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
                    color: AppTheme.mutedText
                    font.pixelSize: 13; font.weight: Font.Bold
                }
                CalendarComboBox {
                    id: recurrenceBox
                    objectName: "eventRecurrenceSelect"
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    model: [qsTr("Does not repeat"), qsTr("Daily"), qsTr("Weekly"),
                        qsTr("Monthly"), qsTr("Yearly")].concat(root.customRecurrence ? [qsTr("Custom (keep existing rule)")] : [])
                    Accessible.name: qsTr("Event recurrence")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("Reminder") + ":"
                    Layout.preferredWidth: root.labelColumnWidth
                    Layout.alignment: Qt.AlignVCenter
                    color: AppTheme.mutedText
                    font.pixelSize: 13; font.weight: Font.Bold
                }
                CalendarComboBox {
                    id: reminderBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    model: [qsTr("None"), qsTr("At start"), qsTr("5 minutes before"),
                        qsTr("15 minutes before"), qsTr("30 minutes before"),
                        qsTr("1 hour before"), qsTr("1 day before")].concat(root.customReminder ? [qsTr("%1 minutes before").arg(root.savedReminderMinutes)] : [])
                    Accessible.name: qsTr("Event reminder")
                }
            }
                }
                }
            }
            Pane {
                Layout.fillWidth: true
                padding: 0
                background: Item {}
                contentItem: ColumnLayout { spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 8



                // Canonical editable-notes scroller, same as the task editor.
                // P02: fixed neutral frame around the notes viewport — same
                // treatment as the task editor.
                Label { text: qsTr("Notes") + ":"; Layout.preferredWidth: root.labelColumnWidth; Layout.alignment: Qt.AlignTop; topPadding: 6; color: AppTheme.mutedText; font.pixelSize: 13; font.weight: Font.Bold }
                Item {
                    id: notesFrame
                    Rectangle { anchors.fill: parent; radius: design.formGroupRadius; color: design.controlFill }
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68



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
                            font.pixelSize: design.editorInputFontSize
                            font.weight: Font.Normal
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

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                // Keep legacy linked pairs editable; new entries use the two
                // explicit event/reminder flows instead of a third hybrid type.
                visible: root.linkedTodoId.length > 0

                CalendarCheckBox {
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
                    // C5: shared AppTheme.warning is 3.89:1 on the light
                    // #F7F7F7 surface; darken only the light leg to #a85c00
                    // (4.67:1). Shared token untouched — weather/todo/music
                    // also read it.
                    color: root.linkedTodoId.length > 0 && !linkTodoCheck.checked
                        ? (AppTheme.dark ? AppTheme.warning : "#a85c00")
                        : AppTheme.mutedText
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: linkTodoCheck.checked
                    spacing: 8

                    Label { text: qsTr("Todo list") + ":"; Layout.preferredWidth: root.labelColumnWidth; color: AppTheme.mutedText; font.pixelSize: 13; font.weight: Font.Bold }
                    CalendarComboBox {
                        id: todoListBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: fieldHeight
                        model: root.availableLists
                        textRole: "name"
                        Accessible.name: qsTr("Linked todo list")
                    }
                    Label { text: qsTr("Priority") + ":"; Layout.preferredWidth: root.labelColumnWidth; color: AppTheme.mutedText; font.pixelSize: 13; font.weight: Font.Bold }
                    CalendarComboBox {
                        id: todoPriorityBox
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: fieldHeight
                        model: [qsTr("None"), qsTr("Low"), qsTr("Medium"),
                            qsTr("High")]
                        Accessible.name: qsTr("Linked todo priority")
                    }
                }
            }
        }
    }
}
