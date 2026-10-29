pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

Demo.LiquidContentPopover {
    id: root
    property string editingId: ""
    property var availableLists: []
    property var availableGroups: []
    property string selectedColor: "#1D9BF6"
    property string selectedIcon: "reminder"
    readonly property var presetColors: ["#FF453A", "#FB0055", "#FF6482", "#FB8208", "#FEC309", "#56D72B", "#39C487", "#30B0A0", "#64D2FF", "#1D9BF6", "#4F8CFF", "#5856D6", "#BF57DA", "#A2845E", "#90714C", "#8E8E93", "#636366", "#3A3A3C"]
    readonly property var iconChoices: [
        {id: "reminder", name: qsTr("Checklist")}, {id: "calendar", name: qsTr("Calendar")},
        {id: "home", name: qsTr("Home")}, {id: "folder", name: qsTr("Folder")},
        {id: "music", name: qsTr("Music")}, {id: "album", name: qsTr("Album")},
        {id: "artist", name: qsTr("Person")}, {id: "keyboard", name: qsTr("Keyboard")},
        {id: "settings", name: qsTr("Settings")}, {id: "wallpaper", name: qsTr("Picture")},
        {id: "heart", name: qsTr("Heart")}, {id: "flag", name: qsTr("Flag")},
        {id: "sparkle", name: qsTr("Sparkle")}, {id: "queue", name: qsTr("Tasks")},
        {id: "download", name: qsTr("Download")}, {id: "radio", name: qsTr("Radio")},
        {id: "grid", name: qsTr("Grid")}, {id: "circle", name: qsTr("Circle")}]
    property bool saving: false
    property bool confirmingDelete: false
    property string errorText: ""
    signal saveRequested(string id, var values)
    signal removeRequested(string id)
    width: 340
    height: Math.min(implicitHeight, parent ? parent.height - 24 : 620)
    closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    function edit(list, anchor, name) {
        editingId = list ? list.id : ""
        selectedColor = list ? list.color : "#1D9BF6"
        selectedIcon = list && list.icon ? list.icon : list && list.kind === "smart" ? "sparkle" : "reminder"
        nameField.text = list ? name : ""
        groupField.currentIndex = Math.max(0, groupField.model.findIndex(group => group.name === (list ? String(list.group || "") : "")))
        kindBox.currentIndex = list && list.kind === "smart" ? 1 : 0
        const rules = list ? list.rules || {} : {}
        tagField.text = rules.tag || ""
        sourceBox.currentIndex = Math.max(0, sourceBox.model.findIndex(item => item.id === (rules.listId || "")))
        dateBox.currentIndex = Math.max(0, ["any", "today", "scheduled", "undated", "overdue"].indexOf(rules.date || "any"))
        flagBox.currentIndex = Math.max(0, ["any", "yes", "no"].indexOf(rules.flag || "any"))
        priorityBox.currentIndex = Math.max(0, ["any", "high", "medium", "low", "none"].indexOf(rules.priority || "any"))
        errorText = ""
        confirmingDelete = false
        anchorItem = anchor
        open()
        nameField.forceActiveFocus()
    }
    onAccepted: {
        if (!/^#[0-9a-fA-F]{6}$/.test(selectedColor)) { errorText = qsTr("Enter a color as #RRGGBB."); return }
        if (!nameField.text.trim()) { errorText = qsTr("Enter a list name."); return }
        saving = true
        saveRequested(editingId, {name: nameField.text.trim(), color: selectedColor, icon: selectedIcon,
            group: groupField.model[groupField.currentIndex].name, kind: kindBox.currentIndex === 1 ? "smart" : "list",
            rules: {tag: tagField.text.trim().replace(/^#+/, ""), listId: sourceBox.model[sourceBox.currentIndex].id,
                date: ["any", "today", "scheduled", "undated", "overdue"][dateBox.currentIndex],
                flag: ["any", "yes", "no"][flagBox.currentIndex],
                priority: ["any", "high", "medium", "low", "none"][priorityBox.currentIndex]}})
    }
    contentItem: ScrollView {
        id: formScroll
        clip: true
        contentWidth: availableWidth
        implicitHeight: form.implicitHeight
        ColumnLayout {
        id: form
        width: formScroll.availableWidth
        enabled: !root.saving
        spacing: 8
        Label { text: root.editingId ? qsTr("Edit list") : qsTr("New list"); font.pixelSize: 15; font.weight: Font.DemiBold; color: AppTheme.text }
        CalendarTextField { id: nameField; objectName: "reminderListName"; Layout.fillWidth: true; maximumLength: 128; placeholderText: qsTr("List name"); onAccepted: root.accept() }
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Type"); color: AppTheme.mutedText; Layout.preferredWidth: 56 }
            CalendarComboBox { id: kindBox; objectName: "listKind"; Layout.fillWidth: true; enabled: !root.editingId; model: [qsTr("List"), qsTr("Smart list")] }
        }
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Group"); color: AppTheme.mutedText; Layout.preferredWidth: 56 }
            CalendarComboBox { id: groupField; objectName: "listGroup"; Layout.fillWidth: true; textRole: "label"; model: [{name: "", label: qsTr("None")}].concat(root.availableGroups.map(group => ({name: group.name, label: group.name}))) }
        }
        Label { visible: kindBox.currentIndex === 1; text: qsTr("Match all conditions. Reminders stay in their original lists."); Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 11; color: AppTheme.mutedText }
        ColumnLayout {
            visible: kindBox.currentIndex === 1
            Layout.fillWidth: true
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Source"); Layout.preferredWidth: 56; color: AppTheme.mutedText }
                CalendarComboBox {
                    id: sourceBox; Layout.fillWidth: true; textRole: "name"
                    model: [{id: "", name: qsTr("All lists")}].concat(root.availableLists.filter(list => list.kind !== "smart").map(list => ({id: list.id, name: list.id === "inbox" && list.name === "Inbox" ? qsTr("Inbox") : list.id === "personal" && list.name === "Personal" ? qsTr("Personal") : list.name})))
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Tag"); Layout.preferredWidth: 56; color: AppTheme.mutedText }
                CalendarTextField { id: tagField; objectName: "smartTag"; Layout.fillWidth: true; maximumLength: 64; placeholderText: qsTr("Any tag") }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Date"); Layout.preferredWidth: 56; color: AppTheme.mutedText }
                CalendarComboBox { id: dateBox; Layout.fillWidth: true; model: [qsTr("Any date"), qsTr("Today and overdue"), qsTr("Scheduled"), qsTr("No date"), qsTr("Overdue")] }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Flag"); Layout.preferredWidth: 56; color: AppTheme.mutedText }
                CalendarComboBox { id: flagBox; Layout.fillWidth: true; model: [qsTr("Any"), qsTr("Flagged"), qsTr("Not flagged")] }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Priority"); Layout.preferredWidth: 56; color: AppTheme.mutedText }
                CalendarComboBox { id: priorityBox; Layout.fillWidth: true; model: [qsTr("Any"), qsTr("High"), qsTr("Medium"), qsTr("Low"), qsTr("None")] }
            }
        }
        Label { text: qsTr("Color"); color: AppTheme.mutedText; font.pixelSize: 12 }
        GridLayout {
            Layout.fillWidth: true
            columns: 9
            columnSpacing: Math.max(0, (form.width - columns * 24) / (columns - 1))
            rowSpacing: 6
            Repeater {
                model: root.presetColors
                delegate: ToolButton {
                    id: swatch
                    required property string modelData
                    implicitWidth: 24; implicitHeight: 24
                    padding: 6
                    Accessible.name: qsTr("Color %1").arg(modelData)
                    Accessible.checkable: true
                    Accessible.checked: root.selectedColor.toLowerCase() === modelData.toLowerCase()
                    background: Rectangle { radius: 12; color: swatch.modelData }
                    contentItem: Demo.VectorIcon {
                        name: "check"; color: ["#FEC309", "#56D72B"].includes(swatch.modelData) ? "#242424" : "white"
                        visible: root.selectedColor.toLowerCase() === swatch.modelData.toLowerCase()
                    }
                    onClicked: root.selectedColor = modelData
                }
            }
        }
        Label { text: qsTr("Icon"); color: AppTheme.mutedText; font.pixelSize: 12 }
        GridLayout {
            Layout.fillWidth: true
            columns: 9
            columnSpacing: Math.max(0, (form.width - columns * 24) / (columns - 1))
            rowSpacing: 6
            Repeater {
                model: root.iconChoices
                delegate: ToolButton {
                    id: iconChoice
                    required property var modelData
                    objectName: "listIcon_" + modelData.id
                    implicitWidth: 24; implicitHeight: 24; padding: 5
                    Accessible.name: modelData.name
                    Accessible.checkable: true
                    Accessible.checked: root.selectedIcon === modelData.id
                    contentItem: Demo.VectorIcon { name: iconChoice.modelData.id; size: 14; color: root.selectedIcon === iconChoice.modelData.id ? "white" : AppTheme.text }
                    background: Rectangle { radius: 12; color: root.selectedIcon === iconChoice.modelData.id ? root.selectedColor : iconChoice.hovered || iconChoice.visualFocus ? AppTheme.cardHover : AppTheme.field }
                    onClicked: root.selectedIcon = modelData.id
                    CalendarToolTip { target: iconChoice; text: iconChoice.modelData.name }
                }
            }
        }
        Label { visible: root.errorText.length > 0; text: root.errorText; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: AppTheme.destructive; font.pixelSize: 11 }
    }
    }
    footer: CalendarEditorFooter {
        enabled: !root.saving
        editing: root.editingId.length > 0 && root.editingId !== "inbox"
        confirmingDelete: root.confirmingDelete
        deleteLabel: qsTr("Remove list")
        deleteTitle: qsTr("Remove this list?")
        deleteMessage: kindBox.currentIndex === 1 ? qsTr("Only this saved view will be removed. Your reminders will be kept.") : qsTr("Its reminders will move to Inbox and will not be deleted.")
        onAccepted: root.accept()
        onRejected: root.reject()
        onDeleteArmed: root.confirmingDelete = true
        onDeleteCanceled: root.confirmingDelete = false
        onDeleteConfirmed: { root.saving = true; root.removeRequested(root.editingId) }
    }
    function accept() { accepted() }
}
