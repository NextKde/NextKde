pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

LiquidDialog {
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
    // LQ18c: plain combo field surface — same tokens as the liquid text fields
    // beside them (α .06, r10, no idle rim) so every control in the form reads
    // as one grammar. Mirrors CalendarTaskEditorDialog.fieldFill.
    readonly property color fieldFill: AppTheme.dark
        ? Qt.rgba(1, 1, 1, .06) : Qt.rgba(0, 0, 0, .06)

    title: editing ? qsTr("Edit event") : qsTr("New event")
    modal: true
    // P02/P03: compact editor — 380 wide, and never taller than the client
    // viewport minus margins so the footer stays reachable at 760x540.
    width: Math.min(380, parent ? parent.width - 48 : 380)
    height: Math.min(620, parent ? parent.height - 32 : 620)
    anchors.centerIn: parent
    standardButtons: Dialog.Save | Dialog.Cancel
    // LQ07: shared liquid dialog shell — r24 card, E4 shadow, .25 scrim, and a
    // plain interior (no glass inside L2). Title and body padding follow the
    // Dialog row of liquid-spec §4.4; the footer keeps its own 16px insets so
    // D05's measured 347px bars are unchanged.
    padding: 24
    header: Label {
        text: root.title
        padding: 24
        bottomPadding: 8
        color: AppTheme.text
        // D04: dialog titles are 20 DemiBold (LiquidDialog's default); the
        // editor used to override down to 17 and lost the alert hierarchy.
        font.pixelSize: 20
        font.weight: Font.DemiBold
        elide: Text.ElideRight
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
        errorText = ""
        errorFields = []
        confirmingDelete = false
        titleField.text = ""
        descriptionField.text = ""
        locationField.text = ""
        startDateField.text = formatDateInput(dateText(date))
        endDateField.text = formatDateInput(dateText(date))
        startTimeField.text = formatTimeInput(twoDigits(startHour) + ":00")
        endTimeField.text = formatTimeInput(twoDigits(startHour + 1) + ":00")
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
        errorText = ""
        errorFields = []
        titleField.text = String(event?.title ?? "")
        descriptionField.text = String(event?.description ?? "")
        locationField.text = String(event?.location ?? "")
        startDateField.text = formatDateInput(isoDatePart(event?.start, fallbackDate))
        endDateField.text = formatDateInput(isoDatePart(event?.end, startDateField.text))
        startTimeField.text = formatTimeInput(isoTimePart(event?.start, "09:00"))
        endTimeField.text = formatTimeInput(isoTimePart(event?.end, "10:00"))
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
    }

    // I4: every accept path runs validation first — invalid input keeps the
    // dialog open and reports inline instead of storing a broken record.
    function accept() {
        const problem = validationProblem()
        if (problem !== null) {
            errorText = problem.message
            errorFields = problem.fields
            return
        }
        errorText = ""
        errorFields = []
        close()
        accepted()
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
    // standard buttons did. The labels are bound, not copied once: reading
    // `count` re-evaluates the binding as soon as the box finishes creating
    // its standard buttons (no onCompleted creation-order fragility), and the
    // button `text` dependency keeps the labels live if the platform strings
    // change (locale hot-switch). The qsTr strings are only the
    // pre-instantiation fallback.
    readonly property string saveLabel: {
        const b = labelSource.count > 0 ? labelSource.standardButton(Dialog.Save) : null
        return b ? b.text : qsTr("Save")
    }
    readonly property string cancelLabel: {
        const b = labelSource.count > 0 ? labelSource.standardButton(Dialog.Cancel) : null
        return b ? b.text : qsTr("Cancel")
    }

    footer: Item {
        implicitHeight: 16
            + (root.confirmingDelete ? confirmCol.implicitHeight : footerCol.implicitHeight) + 16

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
            visible: !root.confirmingDelete

            // Primary: the AcceptRole standard button of the shared footer.
            KosButton {
                // D06: the alert action bar is a capsule, not a rounded rect.
                buttonRadius: height / 2
                Layout.fillWidth: true
                text: root.saveLabel
                highlighted: true
                flatPrimary: true
                lightLabel: true
                onClicked: root.accept()
            }

            // Secondary: the RejectRole standard button of the shared footer.
            KosButton {
                // D06: the alert action bar is a capsule, not a rounded rect.
                buttonRadius: height / 2
                Layout.fillWidth: true
                text: root.cancelLabel
                secondary: true
                onClicked: root.reject()
            }

            KosButton {
                // D06: the alert action bar is a capsule, not a rounded rect.
                buttonRadius: height / 2
                Layout.fillWidth: true
                text: qsTr("Delete event")
                visible: root.editing
                destructive: true
                secondary: true
                onClicked: {
                    root.confirmingDelete = true
                    confirmCancelButton.forceActiveFocus()
                }
            }
        }

        // P1-6: delete confirmation, macOS alert form (bold title, one-line
        // description, stacked buttons) per the alert-macos reference. Cancel
        // is the default (highlighted, focused); Delete fires only from here.
        ColumnLayout {
            id: confirmCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6
            visible: root.confirmingDelete

            Label {
                Layout.fillWidth: true
                text: qsTr("Delete this event?")
                font.bold: true
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("The event is removed from every view. This cannot be undone.")
                color: AppTheme.mutedText
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            KosButton {
                id: confirmCancelButton
                // D06: the alert action bar is a capsule, not a rounded rect.
                buttonRadius: height / 2
                Layout.fillWidth: true
                text: root.cancelLabel
                highlighted: true
                flatPrimary: true
                lightLabel: true
                onClicked: root.confirmingDelete = false
            }

            KosButton {
                // D06: the alert action bar is a capsule, not a rounded rect.
                buttonRadius: height / 2
                Layout.fillWidth: true
                text: qsTr("Delete event")
                destructive: true
                secondary: true
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

        // P02: aligned label-left rows with one field height; compact 380
        // editor keeps every existing field, just visually tamed.
        ColumnLayout {
            id: formLayout
            width: editorScroll.width
            spacing: 10

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

                LiquidTextField {
                    id: titleField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    specificationForm: true
                    invalid: root.hasError("title")
                    outlineColor: AppTheme.destructive
                    placeholderText: qsTr("Event title")
                    Accessible.name: qsTr("Event title")
                    onTextChanged: root.clearError("title")
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
                LiquidTextField {
                    id: startDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    specificationForm: true
                    invalid: root.hasError("startDate")
                    outlineColor: AppTheme.destructive
                    placeholderText: root.datePattern
                    Accessible.name: qsTr("Start date")
                    onTextChanged: root.clearError("startDate")
                }
                LiquidTextField {
                    id: startTimeField
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: fieldHeight
                    specificationForm: true
                    invalid: root.hasError("startTime")
                    outlineColor: AppTheme.destructive
                    placeholderText: root.timePattern
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("Start time")
                    onTextChanged: root.clearError("startTime")
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
                LiquidTextField {
                    id: endDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    specificationForm: true
                    invalid: root.hasError("endDate")
                    outlineColor: AppTheme.destructive
                    placeholderText: root.datePattern
                    Accessible.name: qsTr("End date")
                    onTextChanged: root.clearError("endDate")
                }
                LiquidTextField {
                    id: endTimeField
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: fieldHeight
                    specificationForm: true
                    invalid: root.hasError("endTime")
                    outlineColor: AppTheme.destructive
                    placeholderText: root.timePattern
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("End time")
                    onTextChanged: root.clearError("endTime")
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
                LiquidTextField {
                    id: locationField
                    Layout.fillWidth: true
                    Layout.preferredHeight: fieldHeight
                    specificationForm: true
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

                    Label { text: qsTr("Todo list"); color: AppTheme.mutedText; font.pixelSize: 11 }
                    KosComboBox {
                        id: todoListBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: fieldHeight
                        model: root.availableLists
                        textRole: "name"
                        fillColor: root.fieldFill
                        cornerRadius: 10
                        strokeWidth: 0
                        Accessible.name: qsTr("Linked todo list")
                    }
                    Label { text: qsTr("Priority"); color: AppTheme.mutedText; font.pixelSize: 11 }
                    KosComboBox {
                        id: todoPriorityBox
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: fieldHeight
                        model: [qsTr("None"), qsTr("Low"), qsTr("Medium"),
                            qsTr("High")]
                        fillColor: root.fieldFill
                        cornerRadius: 10
                        strokeWidth: 0
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
                    fillColor: root.fieldFill
                    cornerRadius: 10
                    strokeWidth: 0
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
                    fillColor: root.fieldFill
                    cornerRadius: 10
                    strokeWidth: 0
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

                    // LQ18c: plain field surface + outward focus ring, same
                    // two-layer treatment as the task editor (the KosSurface
                    // `focused` ring was drawn inside the fill).
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: root.fieldFill
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: 12
                        color: "transparent"
                        border.width: 2
                        border.color: AppTheme.focusRing
                        visible: descriptionField.activeFocus
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
