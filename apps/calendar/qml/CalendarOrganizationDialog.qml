pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

Demo.LiquidDialog {
    id: root
    required property var pim
    property string recordId: ""
    property string listId: ""
    property bool sectionMode: false
    property bool removing: false
    property bool saving: false
    property string errorText: ""
    width: Math.min(340, parent ? parent.width - 24 : 340)
    anchors.centerIn: parent
    title: sectionMode ? qsTr("Remove section") : removing ? qsTr("Remove group") : recordId ? qsTr("Rename group") : qsTr("New group")
    closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape
    function editGroup(group, remove) {
        recordId = group ? group.id : ""; listId = ""; sectionMode = false; removing = !!remove
        nameInput.text = group ? group.name : ""; saving = false; errorText = ""; open()
        if (!removing) Qt.callLater(() => { nameInput.forceActiveFocus(); nameInput.selectAll() })
    }
    function editSection(section, anchor) {
        recordId = section.id; listId = section.listId; sectionMode = true; removing = true
        nameInput.text = section.name; saving = false; errorText = ""; open()
    }
    contentItem: ColumnLayout {
        spacing: 12
        CalendarTextField { id: nameInput; objectName: "organizationName"; visible: !root.removing; Layout.fillWidth: true; maximumLength: 128; placeholderText: qsTr("Group name"); enabled: !root.saving; onAccepted: root.save() }
        Label { visible: root.removing; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.sectionMode ? qsTr("Remove “%1”? Its reminders will stay in this list without a section.").arg(nameInput.text) : qsTr("Remove “%1”? Its lists and reminders will be kept.").arg(nameInput.text); color: AppTheme.text }
        Label { visible: root.errorText.length > 0; text: root.errorText; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: AppTheme.destructive; font.pixelSize: 12 }
    }
    function save() {
        if (saving || (!removing && !nameInput.text.trim())) return
        saving = true
        if (sectionMode) pim.removeSection(listId, recordId)
        else if (removing) pim.removeGroup(recordId)
        else pim.saveGroup(recordId, {name: nameInput.text.trim()})
    }
    footer: Item {
        implicitHeight: 62
        RowLayout {
            anchors.fill: parent; anchors.margins: 16; spacing: 8
            Item { Layout.fillWidth: true }
            Demo.LiquidDialogButton { text: qsTr("Cancel"); enabled: !root.saving; onClicked: root.close() }
            Demo.LiquidDialogButton { objectName: "organizationAccept"; text: root.removing ? qsTr("Remove") : root.recordId ? qsTr("Save") : qsTr("Add"); primaryAction: !root.removing; destructive: root.removing; enabled: !root.saving && (root.removing || nameInput.text.trim().length > 0); onClicked: root.save() }
        }
    }
    Connections {
        target: root.pim
        function onOperationSucceeded(operation, id) { if (root.saving && ["saveGroup", "removeGroup", "removeSection"].includes(operation)) { root.saving = false; root.close() } }
        function onOperationFailed(operation, message) { if (root.saving && ["saveGroup", "removeGroup", "removeSection"].includes(operation)) { root.saving = false; root.errorText = message } }
    }
}
