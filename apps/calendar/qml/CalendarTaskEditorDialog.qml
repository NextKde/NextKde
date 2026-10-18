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

    title: editingId.length > 0 ? qsTr("Edit task") : qsTr("New task")
    modal: true
    // P02/P03: compact neutral editor, matching the event editor treatment.
    width: Math.min(380, parent ? parent.width - 48 : 380)
    height: Math.min(560, parent ? parent.height - 64 : 560)
    anchors.centerIn: parent
    standardButtons: Dialog.Save | Dialog.Cancel
    readonly property int fieldHeight: 30

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

    background: KosSurface {
        radius: AppTheme.smallRadius + 4
        fillColor: AppTheme.dark ? "#262626" : "#F7F7F7"
        elevation: 0.5
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
                Layout.fillWidth: true
                text: root.saveLabel
                highlighted: true
                flatPrimary: true
                lightLabel: true
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
                text: qsTr("Delete task")
                visible: root.editingId.length > 0
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
                text: qsTr("Delete this task?")
                font.bold: true
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("The task is removed from every view. This cannot be undone.")
                color: AppTheme.mutedText
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            KosButton {
                id: confirmCancelButton
                Layout.fillWidth: true
                text: root.cancelLabel
                highlighted: true
                flatPrimary: true
                lightLabel: true
                onClicked: root.confirmingDelete = false
            }

            KosButton {
                Layout.fillWidth: true
                text: qsTr("Delete task")
                destructive: true
                secondary: true
                onClicked: {
                    root.deleteRequested(root.editingId)
                    root.close()
                }
            }
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
    function parseDateText(value) {
        const match = String(value ?? "").trim().match(/^(\d{4})-(\d{2})-(\d{2})$/)
        if (!match)
            return null
        const date = new Date(Number(match[1]), Number(match[2]) - 1,
            Number(match[3]))
        // Reject calendar rollovers (2026-02-30 → Mar 2) via round-trip.
        return date.getFullYear() === Number(match[1])
            && date.getMonth() === Number(match[2]) - 1
            && date.getDate() === Number(match[3]) ? date : null
    }

    function parseTimeText(value) {
        const match = String(value ?? "").trim().match(/^(\d{2}):(\d{2})$/)
        if (!match)
            return null
        const hours = Number(match[1])
        const minutes = Number(match[2])
        return hours <= 23 && minutes <= 59 ? hours * 60 + minutes : null
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
            return { message: qsTr("Due date must be YYYY-MM-DD."),
                fields: ["dueDate"] }
        }
        if (!allDayCheck.checked && parseTimeText(dueTimeField.text) === null)
            return { message: qsTr("Due time must be HH:MM (00-23:00-59)."),
                fields: ["dueTime"] }
        return null
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
        errorText = ""
        errorFields = []
        confirmingDelete = false
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
        close()
        accepted()
    }

    onAccepted: saveRequested(editingId, payload())

    contentItem: Flickable {
        id: editorScroll
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
            width: editorScroll.width
            spacing: 10

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

                KosTextField {
                    id: titleField
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldHeight
                    placeholderText: qsTr("Task title")
                    Accessible.name: qsTr("Task title")
                    outlineColor: root.hasError("title")
                        ? AppTheme.destructive : AppTheme.border
                    onTextChanged: root.clearError("title")
                }

                KosCheckBox {
                    id: completedCheck
                    text: qsTr("Completed")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label { text: qsTr("List"); color: AppTheme.mutedText; font.pixelSize: 11 }
                KosComboBox {
                    id: listBox
                    Accessible.name: qsTr("Task list")
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldHeight
                    model: root.availableLists
                    textRole: "name"
                }
                Label { text: qsTr("Priority"); color: AppTheme.mutedText; font.pixelSize: 11 }
                KosComboBox {
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
                KosTextField {
                    id: dueDateField
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldHeight
                    placeholderText: "YYYY-MM-DD"
                    Accessible.name: qsTr("Task due date")
                    outlineColor: root.hasError("dueDate")
                        ? AppTheme.destructive : AppTheme.border
                    onTextChanged: root.clearError("dueDate")
                }

                KosTextField {
                    id: dueTimeField
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: root.fieldHeight
                    placeholderText: "HH:MM"
                    enabled: !allDayCheck.checked
                    Accessible.name: qsTr("Task due time")
                    outlineColor: root.hasError("dueTime")
                        ? AppTheme.destructive : AppTheme.border
                    onTextChanged: root.clearError("dueTime")
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
                    radius: AppTheme.smallRadius
                    fillColor: AppTheme.fieldSurface
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
