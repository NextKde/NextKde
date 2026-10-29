pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as NativeDialogs
import Kos.Ui
import Kos.Demo as Demo

Demo.LiquidContentPopover {
    id: root
    borderWidth: 0.5
    borderColor: AppTheme.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)
    materialOpacity: 0.99
    // Suppress background lettering while retaining sampled colour and refraction.
    backdropBlur: 1.0
    blurStrength: 1.0
    tintStrength: 0.42
    CalendarStyle { id: design }

    property string editingId: ""
    property bool allowTypeSwitch: true
    property string savedRecurrence: "none"
    property int initialRecurrenceIndex: 0
    readonly property bool customRecurrence: !["none", "daily", "weekly", "monthly", "yearly"].includes(savedRecurrence)
    function setQuickTitle(text) { titleField.text = text }
    property bool saving: false
    closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    property string linkedEventId: ""
    property string parentId: ""
    property string parentTitle: ""
    property var availableLists: []
    property var availableTags: []
    property var imageFiles: []
    property var availableCategories: []
    property string calendarId: "personal"
    property string listId: "personal"
    property int savedReminderMinutes: -1
    property int originalReminderIndex: 0
    readonly property bool customReminder: ![-1, 0, 5, 15, 30, 60, 1440].includes(savedReminderMinutes)

    signal saveRequested(string uid, var todo)
    signal deleteRequested(string uid)

    title: editingId.length > 0 ? qsTr("Edit reminder") : qsTr("New reminder")
    modal: false
    popupType: Popup.Item
    // P02/P03: compact neutral editor, matching the event editor treatment.
    width: Math.min(360, parent ? parent.width - 16 : 360)
    height: Math.min((header ? header.implicitHeight : 0) + (footer ? footer.implicitHeight : 0)
        + formLayout.implicitHeight + topPadding + bottomPadding, parent ? parent.height - 16 : 560)
    standardButtons: Dialog.Save | Dialog.Cancel
    padding: 16
    signal switchTypeRequested()
    header: CalendarEditorTabs {
        visible: root.allowTypeSwitch && root.editingId.length === 0
        implicitHeight: visible ? 82 : 0
        leftInset: root.leftPadding
        // Match the form width, including its 8px scrollbar gutter.
        rightInset: root.rightPadding + 8
        currentIndex: 1
        switchingEnabled: root.allowTypeSwitch && root.editingId.length === 0 && !root.saving
        onSwitchRequested: root.switchTypeRequested()
    }
    readonly property int labelColumnWidth: 56
    readonly property int fieldHeight: design.fieldHeight

    // Fixed compact action row; the form scrolls independently.
    footer: CalendarEditorFooter {
        sourceItem: root.sourceItem
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
        if (urlField.text.trim() && !/^https?:\/\/[^\s/]+(?:\/[^\s]*)?$/.test(urlField.text.trim()))
            return { message: qsTr("Enter a link starting with https:// or http://."), fields: ["url"] }
        // An empty due date is allowed (the task simply stays off Calendar),
        // but a linked task must keep one — it defines the event time.
        const dueDate = dueDateField.text.trim()
        if (dueDate.length === 0) {
            if (recurrenceBox.currentIndex > 0)
                return { message: qsTr("A repeating reminder needs a due date."), fields: ["dueDate"] }
            if (linkedEventId.length > 0)
                return { message: qsTr("A linked task needs a due date."),
                    fields: ["dueDate"] }
        } else if (parseDateText(dueDate) === null) {
            return { message: qsTr("Due date must be %1.").arg(datePattern),
                fields: ["dueDate"] }
        }
        if (dueDate.length > 0 && !allDayCheck.checked && parseTimeText(dueTimeField.text) === null)
            return { message: qsTr("Due time must be %1.").arg(timePattern),
                fields: ["dueTime"] }
        return null
    }

    function enableTime() {
        if (!dueDateField.text.trim()) dueDateField.text = formatDateInput(Qt.formatDate(new Date(), "yyyy-MM-dd"))
        allDayCheck.checked = false
        Qt.callLater(() => dueTimeField.showPicker())
    }
    function addImages(files) {
        const next = imageFiles.slice()
        for (const file of files) if (!next.includes(String(file))) next.push(String(file))
        if (next.length > 8) { errorText = qsTr("You can attach up to 8 images."); return }
        imageFiles = next
    }
    NativeDialogs.FileDialog {
        id: imagePicker
        title: qsTr("Add images")
        fileMode: NativeDialogs.FileDialog.OpenFiles
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)")]
        onAccepted: root.addImages(selectedFiles)
    }
    function openForTodo(todo) {
        editingId = String(value(todo, "seriesId", value(todo, "id", "")))
        linkedEventId = String(value(todo, "linkedEventId", ""))
        parentId = String(value(todo, "parentId", ""))
        flaggedCheck.checked = Boolean(value(todo, "flagged", false))
        titleField.text = String(value(todo, "title", ""))
        notesField.text = String(value(todo, "description", ""))
        urlField.text = String(value(todo, "url", ""))
        imageFiles = Array.from(value(todo, "images", []) || [])
        tagsField.text = (value(todo, "tags", []) || []).map(tag => "#" + tag).join(" ")
        completedCheck.checked = Boolean(value(todo, "completed", false))
        listId = String(value(todo, "listId", "inbox"))
        listBox.currentIndex = listIndex(listId)
        sectionField.text = String(value(todo, "section", ""))
        tagsPane.visible = false
        savedRecurrence = String(value(todo, "recurrence", "none"))
        recurrenceBox.currentIndex = customRecurrence ? 5 : ["none", "daily", "weekly", "monthly", "yearly"].indexOf(savedRecurrence)
        initialRecurrenceIndex = recurrenceBox.currentIndex
        calendarId = String(value(todo, "calendarId", "personal"))
        savedReminderMinutes = Number(value(todo, "reminderMinutes", -1))
        reminderBox.currentIndex = (customReminder ? 7 : [-1, 0, 5, 15, 30, 60, 1440].indexOf(savedReminderMinutes))
        originalReminderIndex = reminderBox.currentIndex
        const due = String(value(todo, "due", ""))
        dueDateField.text = formatDateInput(datePart(due))
        const timeMatch = due.match(/T(\d{2}:\d{2})/)
        dueTimeField.text = formatTimeInput(timeMatch ? timeMatch[1] : "18:00")
        allDayCheck.checked = Boolean(value(todo, "allDay", true))
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
        const result = {
            title: titleField.text.trim(),
            description: notesField.text.trim(),
            url: urlField.text.trim(),
            images: imageFiles,
            tags: tagsField.text.split(/[\s,，]+/).map(tag => tag.replace(/^#+/, "")).filter(Boolean),
            section: sectionField.text.trim(),
            listId: listId,
            calendarId: calendarId,
            reminderMinutes: linkedEventId.length > 0 || dueDate.length === 0 ? -1
                : reminderBox.currentIndex === originalReminderIndex ? savedReminderMinutes
                : [-1, 0, 5, 15, 30, 60, 1440][reminderBox.currentIndex],
            due: dueDate.length > 0 ? isoFromDateText(dueDate) + "T"
                + (allDayCheck.checked ? "00:00" : isoFromTimeText(dueTimeField.text)) + ":00" : "",
            allDay: allDayCheck.checked,
            priority: priorityValues[priorityBox.currentIndex],
            flagged: flaggedCheck.checked,
            completed: completedCheck.checked
        }
        if (editingId.length === 0 && parentId.length > 0) result.parentId = parentId
        // Imported custom recurrence rules stay untouched unless explicitly changed.
        if (recurrenceBox.currentIndex !== initialRecurrenceIndex || editingId.length === 0)
            result.recurrence = ["none", "daily", "weekly", "monthly", "yearly"][recurrenceBox.currentIndex] || "none"
        return result
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
            spacing: 12
            enabled: !root.saving
            Label { visible: root.errorText.length > 0; text: root.errorText; Layout.fillWidth: true; color: root.errorColor; font.pixelSize: 11; wrapMode: Text.WordWrap }
            Label { visible: root.parentId.length > 0; text: qsTr("Subtask of %1").arg(root.parentTitle); Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 11; color: AppTheme.mutedText }
            Demo.SettingsGroup {
                backgroundColor: design.controlFill
                verticalPadding: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                    spacing: 6
                    CalendarTextField {
                        id: titleField
                        objectName: "reminderTitle"
                        Layout.fillWidth: true
                        implicitHeight: 32
                        padding: 0
                        font.pixelSize: 20; font.weight: Font.DemiBold
                        placeholderText: qsTr("Task title")
                        background: Item {}
                        invalid: root.hasError("title")
                        onTextChanged: root.clearError("title")
                    }
                    Flickable {
                        id: notesScroll
                        Layout.fillWidth: true; Layout.preferredHeight: 52
                        clip: true; interactive: false
                        TextArea.flickable: KosTextArea {
                            id: notesField
                            objectName: "reminderNotes"
                            width: notesScroll.width
                            font.pixelSize: 12; font.weight: Font.Normal
                            padding: 0
                            placeholderText: qsTr("Optional notes")
                            wrapMode: TextEdit.Wrap
                            background: null
                            selectByMouse: true
                        }
                        ScrollBar.vertical: ScrollBar {}
                        MouseArea {
                            anchors.fill: parent; acceptedButtons: Qt.NoButton
                            onWheel: wheel => { const step = wheel.pixelDelta.y || wheel.angleDelta.y / 2; notesScroll.contentY = Math.max(0, Math.min(Math.max(0, notesScroll.contentHeight - notesScroll.height), notesScroll.contentY - step)); wheel.accepted = true }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: design.separator }
                    CalendarTextField { id: urlField; objectName: "reminderUrl"; Layout.fillWidth: true; padding: 0; placeholderText: qsTr("URL"); maximumLength: 4096; background: Item {}
                        invalid: root.hasError("url"); onTextChanged: root.clearError("url") }
                }
            }
            Demo.SettingsGroup {
                title: qsTr("Date & time")
                titleFont.pixelSize: 12; titleFont.weight: Font.Medium
                titleColor: AppTheme.mutedText
                backgroundColor: design.controlFill
                Demo.SettingsItem {
                    title: qsTr("Date")
                    minimumLabelWidth: 70; controlSpacing: 6; horizontalPadding: 12
                    CalendarDateField {
                        id: dueDateField
                        objectName: "reminderDueDate"
                        visible: text.length > 0
                        implicitWidth: 130
                        parseDate: root.parseDateText
                        formatDate: date => Qt.formatDate(date, root.inputDateFormat)
                        calendarLocale: root.inputLocale
                        placeholderText: root.datePattern
                        invalid: root.hasError("dueDate")
                        onTextChanged: root.clearError("dueDate")
                    }
                    KosSwitch {
                        implicitWidth: 34; implicitHeight: 20
                        checked: dueDateField.text.length > 0
                        enabled: root.linkedEventId.length === 0
                        accessibleName: qsTr("Date")
                        onToggled: checked => { dueDateField.text = checked ? root.formatDateInput(Qt.formatDate(new Date(), "yyyy-MM-dd")) : ""; if (!checked) allDayCheck.checked = true }
                    }
                }
                Demo.SettingsItem {
                    title: qsTr("Time")
                    minimumLabelWidth: 70; controlSpacing: 6; horizontalPadding: 12
                    CalendarTimeField {
                        id: dueTimeField
                        objectName: "reminderDueTime"
                        visible: !allDayCheck.checked
                        implicitWidth: 130
                        parseTime: root.parseTimeText
                        formatTime: date => Qt.formatTime(date, root.inputTimeFormat)
                        placeholderText: root.timePattern
                        invalid: root.hasError("dueTime")
                        onTextChanged: root.clearError("dueTime")
                        onTimeSelected: if (!dueDateField.text.trim()) dueDateField.text = root.formatDateInput(Qt.formatDate(new Date(), "yyyy-MM-dd"))
                    }
                    KosSwitch { objectName: "reminderTimeToggle"; implicitWidth: 34; implicitHeight: 20; checked: !allDayCheck.checked; accessibleName: qsTr("Time"); onToggled: checked => { if (checked) root.enableTime(); else allDayCheck.checked = true } }
                }
                Demo.SettingsItem {
                    title: qsTr("Repeat"); visible: dueDateField.text.length > 0
                    minimumLabelWidth: 70; horizontalPadding: 12
                    CalendarComboBox { id: recurrenceBox; objectName: "reminderRecurrence"; implicitWidth: 150; enabled: root.linkedEventId.length === 0; model: [qsTr("Never"), qsTr("Daily"), qsTr("Weekly"), qsTr("Monthly"), qsTr("Yearly")].concat(root.customRecurrence ? [qsTr("Custom repeat")] : []) }
                }
                Demo.SettingsItem {
                    title: qsTr("Notification"); visible: dueDateField.text.length > 0 && root.linkedEventId.length === 0
                    minimumLabelWidth: 70; horizontalPadding: 12
                    CalendarComboBox { id: reminderBox; objectName: "reminderAlarm"; implicitWidth: 150; model: [qsTr("None"), qsTr("At the scheduled time"), qsTr("5 minutes before"), qsTr("15 minutes before"), qsTr("30 minutes before"), qsTr("1 hour before"), qsTr("1 day before")].concat(root.customReminder ? [qsTr("%1 minutes before").arg(root.savedReminderMinutes)] : []) }
                }
            }
            CalendarCheckBox { id: allDayCheck; visible: false }
            Demo.SettingsGroup {
                title: qsTr("Organization")
                titleFont.pixelSize: 12; titleFont.weight: Font.Medium
                titleColor: AppTheme.mutedText
                backgroundColor: design.controlFill
                Demo.SettingsItem {
                    title: qsTr("List"); minimumLabelWidth: 70; horizontalPadding: 12
                    CalendarComboBox {
                        id: listBox; objectName: "reminderList"; implicitWidth: 180; colorRole: "color"; textRole: "name"
                        model: root.availableLists.map(list => ({id: list.id, color: list.color, name: list.id === "inbox" && list.name === "Inbox" ? qsTr("Inbox") : list.id === "personal" && list.name === "Personal" ? qsTr("Personal") : list.name}))
                        onActivated: { root.listId = model[currentIndex].id; sectionField.text = "" }
                    }
                }
                Demo.SettingsItem {
                    title: qsTr("Section"); minimumLabelWidth: 70; horizontalPadding: 12
                    CalendarComboBox {
                        id: sectionField; objectName: "reminderSection"; implicitWidth: 180; textRole: "label"
                        property string text: ""
                        enabled: root.parentId.length === 0
                        model: [{name: "", label: qsTr("None")}].concat(((root.availableLists.find(list => list.id === root.listId) || {}).sections || []).map(section => ({name: section.name, label: section.name})))
                        onTextChanged: currentIndex = Math.max(0, model.findIndex(item => item.name === text))
                        onModelChanged: currentIndex = Math.max(0, model.findIndex(item => item.name === text))
                        onActivated: text = model[currentIndex].name
                    }
                }
                Demo.SettingsItem {
                    title: qsTr("Tags"); minimumLabelWidth: 70; horizontalPadding: 12
                    CalendarButton { text: tagsField.text || qsTr("Add tags…"); implicitWidth: 180; flat: true; onClicked: tagsPane.visible = !tagsPane.visible }
                }
                ColumnLayout {
                    id: tagsPane
                    visible: false
                    Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.bottomMargin: 6
                    spacing: 4
                    CalendarTextField { id: tagsField; objectName: "reminderTags"; Layout.fillWidth: true; placeholderText: qsTr("#work #errands"); maximumLength: 2048 }
                    Flow {
                        Layout.fillWidth: true; spacing: 4
                        Repeater {
                            model: root.availableTags
                            delegate: Button {
                                id: tag
                                required property string modelData
                                readonly property var selectedTags: tagsField.text.split(/[\s,，]+/).map(value => value.replace(/^#+/, "")).filter(Boolean)
                                readonly property bool selected: selectedTags.some(value => value.toLocaleLowerCase() === modelData.toLocaleLowerCase())
                                implicitWidth: contentItem.implicitWidth + 12; implicitHeight: 22; padding: 2; leftPadding: 6; rightPadding: 6
                                contentItem: Label { text: "#" + tag.modelData; color: tag.selected ? "white" : design.labelPrimary; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 11; color: tag.selected ? design.accent : tag.hovered ? design.selectionFill : design.controlFill }
                                onClicked: tagsField.text = (selected ? selectedTags.filter(value => value.toLocaleLowerCase() !== modelData.toLocaleLowerCase()) : selectedTags.concat([modelData])).map(value => "#" + value).join(" ")
                            }
                        }
                    }
                }
            }
            Demo.SettingsGroup {
                backgroundColor: design.controlFill
                Demo.SettingsItem { title: qsTr("Flagged"); horizontalPadding: 12; KosSwitch { id: flaggedCheck; implicitWidth: 34; implicitHeight: 20; accessibleName: qsTr("Flagged"); onToggled: value => checked = value } }
                Demo.SettingsItem { title: qsTr("Priority"); minimumLabelWidth: 70; horizontalPadding: 12; CalendarComboBox { id: priorityBox; implicitWidth: 180; model: [qsTr("None"), qsTr("Low"), qsTr("Medium"), qsTr("High")] } }
                Demo.SettingsItem { title: qsTr("Completed"); visible: root.editingId.length > 0; horizontalPadding: 12; KosSwitch { id: completedCheck; implicitWidth: 34; implicitHeight: 20; accessibleName: qsTr("Completed"); onToggled: value => checked = value } }
            }
            CalendarButton { text: qsTr("Add images…"); Layout.fillWidth: true; enabled: root.imageFiles.length < 8; onClicked: imagePicker.open() }
            CalendarReminderImages { visible: root.imageFiles.length > 0; images: root.imageFiles; editable: true; onRemoveRequested: index => root.imageFiles = root.imageFiles.filter((file, i) => i !== index) }
        }
    }
}
