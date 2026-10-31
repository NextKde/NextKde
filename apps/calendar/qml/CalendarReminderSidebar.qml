pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

ScrollView {
    id: root
    required property var workspace
    required property var pim
    signal editListRequested(var list, Item anchor)
    signal editGroupRequested(var group, bool remove)
    property var collapsedGroups: []
    readonly property var groupedLists: [{id: "", name: ""}].concat(pim.groups || []).map(group => ({id: group.id, name: group.name,
        lists: pim.lists.filter(list => String(list.group || "") === group.name).sort((a,b) => Number(a.position || 0) - Number(b.position || 0))}))
    CalendarStyle { id: design }
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
        width: root.availableWidth
        spacing: 3
        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            columns: 2
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                model: [{key: "today", title: qsTr("Today"), icon: "calendar", color: "#3478F6"},
                    {key: "planned", title: qsTr("Scheduled"), icon: "calendar", color: "#e4453f"},
                    {key: "all", title: qsTr("All reminders"), icon: "reminder", color: "#687786"},
                    {key: "flagged", title: qsTr("Flagged"), icon: "flag", color: "#FB8208"}]
                delegate: ItemDelegate {
                    id: smart
                    required property var modelData
                    readonly property bool selected: root.workspace.filter === modelData.key
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 60
                    padding: 8
                    Accessible.name: modelData.title + ": " + root.workspace.count(modelData.key, "")
                    onClicked: root.workspace.select(modelData.key)
                    background: Rectangle {
                        radius: design.contentRowRadius
                        color: smart.selected ? (AppTheme.dark ? "#56565C" : "#C8C8CC")
                            : smart.hovered || smart.visualFocus ? (AppTheme.dark ? "#45454B" : "#D0D0D4")
                            : design.controlFill
                    }
                    contentItem: ColumnLayout {
                        spacing: 6
                        RowLayout {
                            Rectangle {
                                implicitWidth: 24; implicitHeight: 24; radius: 12
                                color: smart.modelData.color
                                Demo.VectorIcon { anchors.centerIn: parent; name: smart.modelData.icon; size: 14; color: "white" }
                            }
                            Item { Layout.fillWidth: true }
                            Label { text: root.workspace.count(smart.modelData.key, ""); font.pixelSize: 18; font.weight: Font.DemiBold; color: design.labelPrimary }
                        }
                        Label { text: smart.modelData.title; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 12; font.weight: Font.DemiBold; color: design.labelPrimary }
                    }
                }
            }
        }
        NavRow {
            Layout.topMargin: 6
            label: qsTr("Completed")
            iconName: "check"
            listColor: "#738477"
            count: root.workspace.count("completed", "")
            selected: root.workspace.filter === "completed"
            onClicked: root.workspace.select("completed")
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 14
            Layout.leftMargin: 16
            Layout.rightMargin: 12
            Label { text: qsTr("My lists"); color: design.labelSecondary; font.pixelSize: 11; Layout.fillWidth: true }
            ToolButton {
                id: addList
                objectName: "addReminderListOrGroup"
                implicitWidth: 26; implicitHeight: 26
                enabled: root.pim.connected && root.pim.writable && !root.pim.busy
                Accessible.name: qsTr("New list")
                contentItem: Demo.VectorIcon { name: "plus"; size: 14; color: design.labelSecondary }
                background: Rectangle { radius: design.navigationRadius; color: addList.hovered ? design.rowHoverFill : "transparent" }
                onClicked: addMenu.openAtAnchor()
                Demo.LiquidPopover {
                    id: addMenu
                    anchorItem: addList
                    sourceItem: root.workspace.sourceItem
                    Demo.LiquidPopoverItem { text: qsTr("New list"); iconName: "plus"; onTriggered: root.editListRequested(null, addList) }
                    Demo.LiquidPopoverItem { objectName: "newReminderGroup"; text: qsTr("New group"); iconName: "folder"; onTriggered: root.editGroupRequested(null, false) }
                }
            }
        }
        Repeater {
            model: root.groupedLists
            delegate: ColumnLayout {
                id: group
                required property var modelData
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    visible: group.modelData.name.length > 0
                    Layout.fillWidth: true
                    Layout.rightMargin: 8
                    spacing: 0
                    ToolButton {
                        id: groupFold
                        objectName: "groupFold_" + group.modelData.id
                        implicitWidth: 24; implicitHeight: 28; padding: 6
                        contentItem: Demo.VectorIcon { name: root.collapsedGroups.includes(group.modelData.name) ? "forward" : "chevron"; size: 12; color: design.labelSecondary }
                        background: Rectangle { radius: design.navigationRadius; color: groupFold.hovered ? design.rowHoverFill : "transparent" }
                        Accessible.name: qsTr("Show or hide group")
                        onClicked: root.collapsedGroups = root.collapsedGroups.includes(group.modelData.name) ? root.collapsedGroups.filter(name => name !== group.modelData.name) : root.collapsedGroups.concat([group.modelData.name])
                    }
                    ItemDelegate {
                        id: groupHeader
                        objectName: "groupSelect_" + group.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 28
                        padding: 0
                        topInset: 0; bottomInset: 0
                        contentItem: RowLayout {
                            spacing: 6
                            Demo.VectorIcon { Layout.alignment: Qt.AlignVCenter; name: "folder"; size: 16; color: design.labelSecondary }
                            Label { text: group.modelData.name; Layout.fillWidth: true; Layout.fillHeight: true; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.pixelSize: 12; font.weight: Font.DemiBold; color: design.labelPrimary }
                        }
                        background: Rectangle { radius: design.navigationRadius; color: root.workspace.filter === "group" && root.workspace.listId === group.modelData.id ? design.selectionFill : groupHeader.hovered ? design.rowHoverFill : "transparent" }
                        onClicked: root.workspace.select("group", group.modelData.id)
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: groupMenu.openAtAnchor() }
                        DropArea {
                            anchors.fill: parent
                            keys: ["kos-reminder-list"]
                            onDropped: drop => { if (drop.source) { root.pim.updateList(drop.source.listId, {group: group.modelData.name}); drop.acceptProposedAction() } }
                        }
                    }
                    ToolButton {
                        id: groupMore
                        property var actionMenu: groupMenu
                        objectName: "manageGroup_" + group.modelData.id
                        implicitWidth: 24; implicitHeight: 26; padding: 5
                        Accessible.name: qsTr("Manage group")
                        contentItem: Demo.VectorIcon { name: "more"; size: 14; color: design.labelSecondary }
                        background: Rectangle { radius: design.navigationRadius; color: groupMore.hovered ? design.rowHoverFill : "transparent" }
                        onClicked: groupMenu.openAtAnchor()
                    }
                    Demo.LiquidPopover {
                        id: groupMenu
                        anchorItem: groupMore
                        sourceItem: root.workspace.sourceItem
                        Demo.LiquidPopoverItem { text: qsTr("Rename group"); iconName: "editRounded"; onTriggered: root.editGroupRequested(group.modelData, false) }
                        Demo.LiquidPopoverItem { objectName: "removeReminderGroup_" + group.modelData.id; text: qsTr("Remove group…"); iconName: "trashRounded"; onTriggered: root.editGroupRequested(group.modelData, true) }
                    }
                }
                Repeater {
                    model: root.collapsedGroups.includes(group.modelData.name) ? [] : group.modelData.lists
                    delegate: RowLayout {
                        id: listRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: group.modelData.name.length > 0 ? 18 : 0
                        spacing: 0
                        NavRow {
                            id: listTarget
                            objectName: "reminderListTarget_" + listRow.modelData.id
                            Layout.fillWidth: true
                            label: root.workspace.listName(listRow.modelData.id)
                            iconName: listRow.modelData.icon || (listRow.modelData.kind === "smart" ? "sparkle" : "reminder")
                            listColor: root.workspace.listColor(listRow.modelData.id)
                            count: root.workspace.count(listRow.modelData.kind === "smart" ? "smart" : "list", listRow.modelData.id)
                            selected: ["list", "smart"].includes(root.workspace.filter) && root.workspace.listId === listRow.modelData.id
                            onClicked: root.workspace.select(listRow.modelData.kind === "smart" ? "smart" : "list", listRow.modelData.id)
                            DropArea {
                                id: listDrop
                                anchors.fill: parent
                                keys: ["kos-reminder"]
                                enabled: listRow.modelData.kind !== "smart"
                                onDropped: drop => { if (drop.source && root.workspace.moveToList(drop.source.taskId, listRow.modelData.id)) drop.acceptProposedAction() }
                                Rectangle { anchors.fill: parent; radius: design.navigationRadius; color: design.selectionFill; opacity: 0.5; visible: listDrop.containsDrag }
                            }
                        }
                        ToolButton {
                            id: more
                            implicitWidth: 26; implicitHeight: 26
                            Layout.rightMargin: 8
                            text: "…"
                            Accessible.name: qsTr("Edit list") + ": " + root.workspace.listName(listRow.modelData.id)
                            enabled: root.pim.connected && root.pim.writable && !root.pim.busy
                            background: Rectangle { radius: design.navigationRadius; color: more.hovered || more.visualFocus ? design.rowHoverFill : "transparent" }
                            onClicked: root.editListRequested(listRow.modelData, more)
                        }
                    }
                }
            }
        }
        Label {
            visible: root.workspace.allTags.length > 0
            Layout.topMargin: 14
            Layout.leftMargin: 16
            text: qsTr("Tags")
            color: design.labelSecondary
            font.pixelSize: 11
        }
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            spacing: 4
            Repeater {
                model: root.workspace.allTags
                delegate: Button {
                    id: tagButton
                    required property string modelData
                    readonly property bool selected: root.workspace.filter === "tag" && root.workspace.listId === modelData
                    text: "#" + modelData
                    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
                    implicitHeight: 22
                    leftPadding: 6; rightPadding: 6
                    topPadding: 2; bottomPadding: 2
                    hoverEnabled: true
                    Accessible.checkable: true
                    Accessible.checked: selected
                    contentItem: Label { text: tagButton.text; color: tagButton.selected ? "#FFFFFF" : design.labelPrimary; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 11; color: tagButton.selected ? design.accent : tagButton.hovered || tagButton.visualFocus ? (AppTheme.dark ? "#505056" : "#CFCFD3") : design.controlFill }
                    onClicked: {
                        if (selected) root.workspace.select("all")
                        else root.workspace.select("tag", modelData)
                    }
                }
            }
        }
    }

    component NavRow: ItemDelegate {
        id: nav
        property string label
        property string iconName: "reminder"
        property color listColor: design.accent
        property int count
        property bool selected
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        implicitHeight: 30
        leftPadding: 8; rightPadding: 8; topPadding: 4; bottomPadding: 4
        Accessible.name: label
        contentItem: RowLayout {
            spacing: 8
            Rectangle {
                implicitWidth: 18; implicitHeight: 18; radius: 9
                color: nav.listColor
                Demo.VectorIcon { anchors.centerIn: parent; name: nav.iconName; size: 11; color: "white" }
            }
            Label { text: nav.label; color: design.labelPrimary; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
            Label { text: String(nav.count); color: design.labelSecondary; font.pixelSize: 11 }
        }
        background: Rectangle { radius: design.navigationRadius; color: nav.selected ? design.selectionFill : nav.hovered ? design.rowHoverFill : "transparent" }
    }
}
