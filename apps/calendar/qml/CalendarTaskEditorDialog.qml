pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosWorkspaceDialog {
    id: root
    CalendarStyle { id: design }

    property string editingId: ""
    property bool saving: false
    closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape
    property string linkedEventId: ""
    property var availableLists: []
    property var availableCategories: []
    property string calendarId: "personal"
    property string listId: "personal"
    property int savedReminderMinutes: -1
    property int originalReminderIndex: 0
    readonly property bool customReminder: ![-1, 0, 5, 15, 30, 60, 1440].includes(savedReminderMinutes)

    signal saveRequested(string uid, var todo)
    signal deleteRequested(string uid)

    title: editingId.length > 0 ? qsTr("Edit reminder") : qsTr("New reminder")
    modal: true
    popupType: Popup.Item
    // P02/P03: compact neutral editor, matching the event editor treatment.
    width: Math.min(420, parent ? parent.width - 32 : 420)
    height: Math.min(480, parent ? parent.height - 32 : 480)
    anchors.centerIn: parent
    standardButtons: Dialog.Save | Dialog.Cancel
    background: Rectangle { radius: 12; color: design.dialogPlane }
    padding: 16
    header: Label {
        text: root.title
        color: design.labelPrimary
        font.pixelSize: 17
        font.weight: Font.DemiBold
        padding: 16
        bottomPadding: 8
        elide: Text.ElideRight
    }
    readonly property int fieldHeight: design.fieldHeight

    // Fixed compact action row; the form scrolls independently.
    footer: CalendarEditorFooter {
        enabled: !root.saving
        editing: root.editingId.length > 0
        confirmingDelete: root.confirmingDelete
        deleteLabel: qsTr("Delete task")
        deleteTitle: qsTr("Delete this task?")
        deleteMessage: qsTr("The task is removed from every view. This cannot be undone.")
        onAccepted: root.accept()
        onRejected: root.reject()
        onDeleteArmed: root.confirmingDelete = true
        onDeleteCanceled: root.confirmingDelete = false
        onDeleteConfirmed: {
            root.deleteRequested(root.editingId)
            root.close()
        }
    }

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

    // P1-5 (REVIEW): save-time validation, mirroring the event editor. The
    // due date/time fields are free text, so parse strictly before they are
    // concatenated into the ISO due string — an unparsable field must block
    // accept instead of storing a broken todo.
    //
    // I7 (REVIEW): the fields speak the locale's short format — the
    // placeholder shows the locale's field order, seeds and parsing use it,
    // and plain ISO stays accepted (copy/paste). The due string is still
    // assembled as ISO at payload time.
    function twoDigits(value) {
        return value < 10 ? "0" + value : String(value)
    }

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

    // P1-5: last validation problem, kept until the offending field is edited
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
        // An empty due date is allowed (the task simply stays off Calendar),
        // but a linked task must keep one — it defines the event time.
        const dueDate = dueDateField.text.trim()
        if (dueDate.length === 0) {
            if (linkedEventId.length > 0)
                return { message: qsTr("A linked task needs a due date."),
                    fields: ["dueDate"] }
        } else if (parseDateText(dueDate) === null) {
            return { message: qsTr("Due date must be %1.").arg(datePattern),
                fields: ["dueDate"] }
        }
        if (!allDayCheck.checked && parseTimeText(dueTimeField.text) === null)
            return { message: qsTr("Due time must be %1.").arg(timePattern),
                fields: ["dueTime"] }
        return null
    }

    function openForTodo(todo) {
        editingId = String(value(todo, "seriesId", value(todo, "id", "")))
        linkedEventId = String(value(todo, "linkedEventId", ""))
        titleField.text = String(value(todo, "title", ""))
        notesField.text = String(value(todo, "description", ""))
        completedCheck.checked = Boolean(value(todo, "completed", false))
        listId = String(value(todo, "listId", "personal"))
        calendarId = String(value(todo, "calendarId", "personal"))
        categoryBox.currentIndex = Math.max(0, availableCategories.findIndex(item => item.id === calendarId) < 0 ? 1 : availableCategories.findIndex(item => item.id === calendarId))
        savedReminderMinutes = Number(value(todo, "reminderMinutes", -1))
        reminderBox.currentIndex = (customReminder ? 7 : [-1, 0, 5, 15, 30, 60, 1440].indexOf(savedReminderMinutes))
        originalReminderIndex = reminderBox.currentIndex
        const due = String(value(todo, "due", ""))
        dueDateField.text = formatDateInput(datePart(due))
        const timeMatch = due.match(/T(\d{2}:\d{2})/)
        dueTimeField.text = formatTimeInput(timeMatch ? timeMatch[1] : "18:00")
        allDayCheck.checked = Boolean(value(todo, "allDay", false))
        priorityBox.currentIndex = priorityIndex(value(todo, "priority", 0))
        errorText = ""
        errorFields = []
        confirmingDelete = false
        open()
        titleField.forceActiveFocus()
    }

    function payload() {
        const priorityValues = [0, 9, 5, 1]
        const dueDate = dueDateField.text.trim()
        return {
            title: titleField.text.trim(),
            description: notesField.text.trim(),
            listId: listId,
            calendarId: calendarId,
            reminderMinutes: linkedEventId.length > 0 || dueDate.length === 0 ? -1
                : reminderBox.currentIndex === originalReminderIndex ? savedReminderMinutes
                : [-1, 0, 5, 15, 30, 60, 1440][reminderBox.currentIndex],
            due: dueDate.length > 0 ? isoFromDateText(dueDate) + "T"
                + (allDayCheck.checked ? "00:00" : isoFromTimeText(dueTimeField.text)) + ":00" : "",
            allDay: allDayCheck.checked,
            priority: priorityValues[priorityBox.currentIndex],
            completed: completedCheck.checked
        }
    }

    // P1-5: every accept path runs validation first — invalid input keeps
    // the dialog open and reports inline instead of storing a broken todo.
    function accept() {
        const problem = validationProblem()
        if (problem !== null) {
            errorText = problem.message
            errorFields = problem.fields
            return
        }
        errorText = ""
        errorFields = []
        accepted()
    }

    onAccepted: saveRequested(editingId, payload())

    contentItem: Flickable {
        id: editorScroll
        enabled: !root.saving
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
        // Harness probe hook: names this Flickable so the review harness can
        // read its height/contentHeight/contentY (regionPosition). No visual
        // or behavioural effect.
        objectName: "editorScroll"
        clip: true
        // Non-interactive form: the outer drag filter is the last press
        // competitor for the notes area; dragging the form is not needed —
        // it scrolls by wheel (NoButton MouseArea below) and the attached
        // scrollbar. Explicit Flickable (not ScrollView) because
        // interactive is a real Flickable property; ScrollView has none.
        interactive: false
        contentWidth: width
        contentHeight: formLayout.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        // P03: macOS overlay scrollbar — floats over the form, no track, so a
        // clipped form reads as scrollable instead of as a rendering fault
        // (same treatment as the event editor).
        // AsNeeded on its own is NOT enough here: measured at 1100x692 the
        // form already fits (contentHeight 295 <= the flickable's height, the
        // notes box's bottom border is drawn) yet a bare AsNeeded bar still
        // painted a full-length thumb — a stray 3px dark line beside the form.
        // Gate the policy on the real scrollability the wheel handler uses.
        ScrollBar.vertical: ScrollBar {
            id: formScrollBar
            policy: editorScroll.contentHeight > editorScroll.height
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width: 6
            background: Item {}
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: AppTheme.withAlpha(AppTheme.blackSeed,
                                          AppTheme.dark ? 0.40 : 0.30)
            }
        }

        // Outer wheel scrolling, same NoButton pattern as the notes area:
        // wheel over the form (outside the notes field, which accepts its
        // own wheel first) scrolls the form.
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

        ColumnLayout {
            id: formLayout
            width: editorScroll.width - 8
            spacing: 8

            // P1-5: inline validation error — pinned to the top of the form so
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

            Label {
                Layout.fillWidth: true
                visible: root.linkedEventId.length > 0
                text: qsTr("Linked to this Calendar event. Editing the title or date updates the matching task in Todo.")
                color: AppTheme.mutedText
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Label { text: qsTr("Title"); color: AppTheme.mutedText; font.pixelSize: 11 }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                CalendarTextField {
                    id: titleField
                    objectName: "reminderTitle"
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldHeight
                    placeholderText: qsTr("Task title")
                    Accessible.name: qsTr("Task title")
                    invalid: root.hasError("title")
                    outlineColor: root.hasError("title")
                        ? AppTheme.destructive : AppTheme.border
                    onTextChanged: root.clearError("title")
                }

                CalendarCheckBox {
                    id: completedCheck
                    text: qsTr("Completed")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label { text: qsTr("Category"); color: AppTheme.mutedText; font.pixelSize: 11 }
                CalendarComboBox {
                    popupScene: root.contentItem.parent
                    id: categoryBox
                    objectName: "reminderCategory"
                    Accessible.name: qsTr("Category")
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldHeight
                    model: root.availableCategories
                    onActivated: root.calendarId = root.availableCategories[currentIndex].id
                    textRole: "name"
                }
                Label { text: qsTr("Priority"); color: AppTheme.mutedText; font.pixelSize: 11 }
                CalendarComboBox {
                    popupScene: root.contentItem.parent
                    id: priorityBox
                    Accessible.name: qsTr("Task priority")
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: root.fieldHeight
                    model: [qsTr("None"), qsTr("Low"), qsTr("Medium"), qsTr("High")]
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label { text: qsTr("Due date"); color: AppTheme.mutedText; font.pixelSize: 11 }
                CalendarTextField {
                    id: dueDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldHeight
                    placeholderText: root.datePattern
                    Accessible.name: qsTr("Task due date")
                    invalid: root.hasError("dueDate")
                    outlineColor: root.hasError("dueDate")
                        ? AppTheme.destructive : AppTheme.border
                    onTextChanged: root.clearError("dueDate")
                }

                CalendarTextField {
                    id: dueTimeField
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: root.fieldHeight
                    placeholderText: root.timePattern
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("Task due time")
                    invalid: root.hasError("dueTime")
                    outlineColor: root.hasError("dueTime")
                        ? AppTheme.destructive : AppTheme.border
                    onTextChanged: root.clearError("dueTime")
                }

                CalendarCheckBox {
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

            RowLayout {
                Layout.fillWidth: true
                visible: root.linkedEventId.length === 0
                Label { text: qsTr("Notification"); color: AppTheme.mutedText; font.pixelSize: 11 }
                CalendarComboBox {
                    id: reminderBox
                    objectName: "reminderAlarm"
                    popupScene: root.contentItem.parent
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldHeight
                    enabled: dueDateField.text.trim().length > 0
                    model: [qsTr("None"), qsTr("At the scheduled time"), qsTr("5 minutes before"),
                        qsTr("15 minutes before"), qsTr("30 minutes before"), qsTr("1 hour before"), qsTr("1 day before")].concat(root.customReminder ? [qsTr("%1 minutes before").arg(root.savedReminderMinutes)] : [])
                }
            }

            Label { text: qsTr("Notes"); color: AppTheme.mutedText; font.pixelSize: 11 }
            // Canonical editable-notes scroller: an explicit Flickable owns
            // the TextArea. The editor's height follows its wrapped content,
            // so the flickable gets real vertical extent and the rendered
            // glyphs move with contentY (no implicit-ScrollView adoption
            // ambiguity). Bounded 96 viewport, wrapping, cursor and editing
            // all preserved; the outer form scroll is unaffected because the
            // flickable consumes wheel events over the notes area.
            // P02: the neutral field surface is a FIXED frame around the 96px
            // viewport (KosTextArea's own scrolling background would travel
            // with the text), so the outline/corners/focus stay put while
            // only text and thumb move.
            Item {
                id: notesFrame
                Layout.fillWidth: true
                Layout.preferredHeight: 96

                KosSurface {
                    anchors.fill: parent
                    radius: 8
                    fillColor: design.controlFill
                    elevation: 0
                    focused: notesField.activeFocus
                }

                Flickable {
                    id: notesScroll
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // Non-interactive: the notes view scrolls by wheel and
                    // scrollbar only. A Flickable that can drag would let
                    // its press filter compete with the TextArea for every
                    // press once the view is scrolled, which is exactly the
                    // hit-testing failure seen at lines 17/18 — clicks and
                    // drags then never reach the native text control. With
                    // interactive off, presses pass straight through to the
                    // editor (native cursor placement and drag selection),
                    // while wheel and the visible scrollbar still scroll.
                    interactive: false
                    // Native Qt integration (TextArea.flickable attached
                    // property, per Qt docs): the attached property lives on
                    // the Flickable and its value IS the TextArea. The
                    // native text control then owns pointer handling — every
                    // click moves the cursor, drag selects, and the view
                    // keeps the cursor visible — while the Flickable only
                    // provides scrolling. The attached integration derives
                    // the content geometry from the TextArea itself, so no
                    // manual height/content/cursor bindings are needed.
                    TextArea.flickable: KosTextArea {
                        id: notesField
                        Accessible.name: qsTr("Task notes")
                        width: notesScroll.width
                        placeholderText: qsTr("Optional notes")
                        wrapMode: TextEdit.Wrap
                        background: null
                        activeFocusOnPress: true
                        selectByMouse: true
                    }

                    ScrollBar.vertical: ScrollBar {}

                    // Wheel scrolling for the non-interactive flickable.
                    // MouseArea.onWheel (not a WheelHandler — measured in
                    // this repo that an independent WheelHandler at this
                    // layer never receives the wheel). NoButton means the
                    // area handles ONLY the wheel: clicks and drag-selection
                    // pass straight through to the native text control, and
                    // accepting the wheel keeps the outer form from moving.
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
