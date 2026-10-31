pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

ItemDelegate {
    id: root
    required property var workspace
    property string listId: "inbox"
    property string section: ""
    property bool editing: false
    readonly property string draftKey: listId + "/" + section
    readonly property bool saving: workspace.inlineSavingKey === draftKey
    property bool card: false
    readonly property string errorText: editing ? workspace.inlineError : ""
    objectName: "inlineAdd_" + listId + "_" + section
    CalendarStyle { id: design }
    implicitHeight: Math.max(card ? 32 : 28, contentItem.implicitHeight + topPadding + bottomPadding)
    padding: card ? 5 : 3
    topPadding: card ? 4 : 2
    bottomPadding: topPadding
    enabled: workspace.pim.connected && workspace.pim.writable
    function begin() { workspace.inlineFocusKey = draftKey; editing = true; input.forceActiveFocus() }
    function submit() { workspace.submitInline(listId, section, {description: inlineFields.notes, tags: inlineFields.tags, flagged: inlineFields.flagged}) }
    function containsFocus() {
        let item = root.Window.window ? root.Window.window.activeFocusItem : null
        while (item) { if (item === root) return true; item = item.parent }
        return false
    }
    Timer {
        interval: 100; repeat: true; running: root.editing && !root.saving
        onTriggered: if (!root.containsFocus()) { root.editing = false; if (input.text.trim()) root.submit() }
    }
    onSavingChanged: {
        if (!saving && !workspace.inlineError && !String(workspace.inlineDrafts[draftKey] || "").trim()) {
            inlineFields.notes = ""; inlineFields.tagsText = ""; inlineFields.flagged = false
        }
    }
    Component.onCompleted: if (workspace.inlineFocusKey === draftKey) Qt.callLater(begin)
    onClicked: begin()
    background: Rectangle { radius: design.contentRowRadius; color: root.hovered || root.editing ? design.rowHoverFill : root.card ? design.controlFill : "transparent" }
    DropArea {
        id: sectionDrop
        anchors.fill: parent
        keys: ["kos-reminder"]
        onDropped: drop => { if (drop.source && !root.workspace.pim.busy) { root.workspace.pim.updateTodo(drop.source.taskId, {listId: root.listId, section: root.section, parentId: "", order: Date.now()}); drop.acceptProposedAction() } }
        Rectangle { anchors.fill: parent; radius: design.contentRowRadius; color: design.selectionFill; opacity: 0.5; visible: sectionDrop.containsDrag }
    }
    contentItem: ColumnLayout {
        spacing: 2
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle { Layout.preferredWidth: 18; Layout.preferredHeight: 18; Layout.leftMargin: 3; Layout.rightMargin: 3; radius: 9; color: "transparent"; border.color: design.labelSecondary; border.width: 1; opacity: root.editing ? 0.7 : 0.3 }
            TextField {
                id: input
                objectName: "inlineReminderTitle"
                Layout.fillWidth: true
                implicitHeight: 24
                padding: 0
                font.pixelSize: 14
                color: design.labelPrimary
                placeholderTextColor: design.labelSecondary
                placeholderText: root.editing || root.hovered ? qsTr("New reminder") : ""
                text: root.workspace.inlineDrafts[root.draftKey] || ""
                onTextEdited: { const drafts = Object.assign({}, root.workspace.inlineDrafts); drafts[root.draftKey] = text; root.workspace.inlineDrafts = drafts }
                readOnly: root.saving
                background: Item {}
                onActiveFocusChanged: {
                    if (activeFocus) { root.editing = true; root.workspace.inlineFocusKey = root.draftKey }

                }
                onAccepted: root.submit()
                Keys.onEscapePressed: { const drafts = Object.assign({}, root.workspace.inlineDrafts); delete drafts[root.draftKey]; root.workspace.inlineDrafts = drafts; root.workspace.inlineFocusKey = ""; root.editing = false; root.forceActiveFocus() }
            }
        }
        CalendarReminderInlineFields {
            id: inlineFields
            visible: root.editing
            Layout.fillWidth: true
            Layout.leftMargin: 30
            Layout.rightMargin: 30
        }
        Label { visible: root.errorText.length > 0; text: root.errorText; color: design.statusWarning; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    }
}
