pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

ItemDelegate {
    id: row
    required property var workspace
    required property var todo
    property bool card: false
    property bool editing: false
    property bool saving: false
    readonly property var pim: workspace.pim
    objectName: "reminderRow_" + todo.id
    CalendarStyle { id: design }
    implicitHeight: Math.max(34, body.implicitHeight + (card ? 14 : 6))
    padding: card ? 7 : 3
    leftPadding: padding + Math.min(Number(todo.displayDepth || 0), 5) * 16
    Accessible.name: todo.title
    onClicked: { editing = true; titleInput.text = todo.title; titleInput.forceActiveFocus() }
    function saveTitle() {
        if (!editing || saving) return
        const value = titleInput.text.trim()
        if (!value || value === todo.title) { editing = false; return }
        saving = true
        pim.updateTodo(todo.id, {title: value})
    }
    Connections {
        target: row.pim
        function onOperationSucceeded(operation, id) {
            if (row.saving && operation === "updateTodo" && id === row.todo.id) { row.saving = false; row.editing = false }
        }
        function onOperationFailed(operation, message) { if (row.saving && operation === "updateTodo") row.saving = false }
    }
    background: Rectangle {
        radius: design.contentRowRadius
        color: row.hovered || row.visualFocus || row.editing ? design.rowHoverFill : row.card ? design.controlFill : "transparent"
    }
    DropArea {
        id: dropTarget
        anchors.fill: parent
        keys: ["kos-reminder"]
        enabled: row.workspace.canOrganize && !row.workspace.searchQuery.trim()
        onDropped: drop => {
            if (drop.source && row.workspace.moveRelative(drop.source.taskId, row.todo, drop.y > height / 2)) drop.acceptProposedAction()
        }
        Rectangle { visible: dropTarget.containsDrag; width: parent.width; height: 2; radius: 1; y: dropTarget.drag.y > parent.height / 2 ? parent.height - 2 : 0; color: row.workspace.listColor(row.todo.listId) }
    }
    contentItem: ColumnLayout {
        id: body
        spacing: 5
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            CalendarCheckBox {
                implicitWidth: 24; implicitHeight: 24; padding: 3
                roundIndicator: true
                accentColor: row.workspace.listColor(row.todo.listId)
                checked: row.todo.completed
                enabled: row.pim.writable && !row.pim.busy
                Accessible.name: row.todo.completed ? qsTr("Mark incomplete") : qsTr("Mark complete")
                onClicked: row.pim.updateTodo(row.todo.id, {completed: !row.todo.completed})
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                TextField {
                    id: titleInput
                    objectName: "reminderTitle_" + row.todo.id
                    Layout.fillWidth: true
                    implicitHeight: 24
                    padding: 0
                    text: row.todo.title
                    readOnly: row.saving
                    font.pixelSize: 14
                    font.underline: false
                    font.strikeout: row.todo.completed
                    color: row.todo.completed ? design.labelSecondary : design.labelPrimary
                    background: Item {}
                    selectByMouse: true
                    onActiveFocusChanged: {
                        if (activeFocus) { row.workspace.inlineFocusKey = ""; row.editing = true }
                        else row.saveTitle()
                    }
                    onAccepted: { row.saveTitle(); row.forceActiveFocus() }
                    Keys.onEscapePressed: { text = row.todo.title; row.editing = false; row.forceActiveFocus() }
                }
                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: [row.workspace.dueText(row.todo), row.workspace.canOrganize ? "" : row.workspace.listName(row.todo.listId), (row.todo.tags || []).map(tag => "#" + tag).join(" ")].filter(Boolean).join(" · ")
                    color: !row.todo.completed && row.todo.due && String(row.todo.due).slice(0,10) < row.workspace.today ? design.statusWarning : design.labelSecondary
                    font.pixelSize: 11; elide: Text.ElideRight
                }
                Label { visible: Boolean(row.todo.description); text: String(row.todo.description || "").replace(/\n/g, " "); Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 11; color: design.labelSecondary }
            }
            Label { visible: text.length > 0; text: row.workspace.priorityText(row.todo); color: design.statusWarning; font.pixelSize: 11 }
            ToolButton {
                visible: Boolean(row.todo.flagged)
                implicitWidth: 22; implicitHeight: 24; padding: 4
                contentItem: Demo.VectorIcon { name: "flag"; size: 14; color: "#FB8208"; filled: true }
                background: Item {}
                Accessible.name: qsTr("Remove flag")
                onClicked: row.pim.updateTodo(row.todo.id, {flagged: false})
            }
            ToolButton {
                visible: row.workspace.childCount(row.todo.id) > 0 && ["list", "inbox", "all", "group"].includes(row.workspace.filter)
                implicitWidth: 20; implicitHeight: 24; padding: 4
                contentItem: Demo.VectorIcon { name: row.workspace.collapsedParents.includes(row.todo.id) ? "forward" : "chevron"; size: 12; color: design.labelSecondary }
                background: Item {}
                Accessible.name: qsTr("Show or hide subtasks")
                onClicked: row.workspace.toggleChildren(row.todo.id)
            }
            Item {
                id: dragHandle
                objectName: "reminderDrag_" + row.todo.id
                implicitWidth: row.hovered ? 18 : 0; implicitHeight: 24
                visible: row.hovered
                Demo.VectorIcon { anchors.centerIn: parent; name: "queueList"; size: 12; color: design.labelSecondary }
                Item {
                    id: dragProxy
                    width: 18; height: 24
                    property string taskId: row.todo.id
                    Drag.active: dragMouse.drag.active
                    Drag.source: dragProxy
                    Drag.keys: ["kos-reminder"]
                    Drag.hotSpot.x: 9; Drag.hotSpot.y: 12
                }
                MouseArea {
                    id: dragMouse
                    anchors.fill: parent
                    preventStealing: true
                    enabled: row.pim.writable && !row.pim.busy
                    drag.target: dragProxy
                    cursorShape: Qt.OpenHandCursor
                    onReleased: { dragProxy.Drag.drop(); dragProxy.x = 0; dragProxy.y = 0 }
                    onCanceled: { dragProxy.Drag.cancel(); dragProxy.x = 0; dragProxy.y = 0 }
                }
            }
            ToolButton {
                id: details
                objectName: "reminderDetails_" + row.todo.id
                implicitWidth: 24; implicitHeight: 24; padding: 3
                opacity: row.hovered || row.editing || activeFocus ? 1 : 0.4
                Accessible.name: qsTr("Reminder details")
                contentItem: Label { text: "ⓘ"; font.pixelSize: 17; color: row.workspace.listColor(row.todo.listId); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 12; color: details.hovered ? design.controlFill : "transparent" }
                onClicked: { row.workspace.inlineFocusKey = ""; row.saveTitle(); row.workspace.editRequested(row.todo, details) }
            }
        }
        Image {
            visible: row.card && (row.todo.images || []).length > 0
            source: visible ? row.todo.images[0] : ""
            Layout.fillWidth: true; Layout.preferredHeight: visible ? 128 : 0
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
    }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: taskMenu.openAtAnchor() }
    Demo.LiquidPopover {
        id: taskMenu
        anchorItem: row
        sourceItem: row.workspace.sourceItem
        Demo.LiquidPopoverItem { text: qsTr("Reminder details"); iconName: "editRounded"; onTriggered: row.workspace.editRequested(row.todo, row) }
        Demo.LiquidPopoverItem { text: qsTr("Add subtask"); iconName: "plus"; onTriggered: row.workspace.subtaskRequested(row.todo, row) }
        Demo.LiquidPopoverItem { text: row.todo.flagged ? qsTr("Remove flag") : qsTr("Flag reminder"); iconName: "flag"; onTriggered: row.pim.updateTodo(row.todo.id, {flagged: !row.todo.flagged}) }
    }
}
