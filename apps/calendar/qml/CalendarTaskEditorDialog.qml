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
    // P02/P03: compact neutral editor, matching the event editor treatment.
    width: Math.min(380, parent ? parent.width - 48 : 380)
    height: Math.min(560, parent ? parent.height - 64 : 560)
    anchors.centerIn: parent
    standardButtons: Dialog.Save | Dialog.Cancel
    readonly property int fieldHeight: 30
    background: KosSurface {
        radius: AppTheme.smallRadius + 4
        fillColor: AppTheme.dark ? "#262626" : "#F7F7F7"
        elevation: 0.5
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

    contentItem: Flickable {
        id: editorScroll
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
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.fieldHeight
                    model: root.availableLists
                    textRole: "name"
                }
                Label { text: qsTr("Priority"); color: AppTheme.mutedText; font.pixelSize: 11 }
                KosComboBox {
                    id: priorityBox
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
                }

                KosTextField {
                    id: dueTimeField
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: root.fieldHeight
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
