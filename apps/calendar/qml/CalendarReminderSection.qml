pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

ColumnLayout {
    id: root
    required property var workspace
    required property var sectionData
    property bool card: false
    readonly property string sectionKey: sectionData.listId + "/" + sectionData.id
    readonly property bool collapsed: workspace.collapsedSections.includes(sectionKey)
    property bool renaming: false
    function beginAdd() { inlineAdd.begin() }
    spacing: card ? 8 : 1
    CalendarStyle { id: design }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: design.separator; visible: !root.card && root.sectionData.title.length > 0 }
    RowLayout {
        Layout.fillWidth: true
        visible: root.sectionData.title.length > 0 || root.renaming
        Layout.preferredHeight: 34
        spacing: 4
        Label { visible: !root.renaming; text: root.sectionData.title; Layout.fillWidth: true; elide: Text.ElideRight; color: design.labelPrimary; font.pixelSize: 15; font.weight: Font.Bold }
        TextField {
            id: nameInput
            objectName: "sectionName_" + root.sectionData.id
            visible: root.renaming
            Layout.fillWidth: true
            text: root.sectionData.name
            font.pixelSize: 15; font.weight: Font.Bold
            color: design.labelPrimary
            padding: 0
            maximumLength: 128
            background: Item {}
            onAccepted: {
                if (text.trim()) { root.workspace.pim.saveSection(root.sectionData.listId, root.sectionData.id, {name: text.trim()}); root.renaming = false }
            }
            Keys.onEscapePressed: root.renaming = false
        }
        ToolButton {
            id: sectionMore
            property var actionMenu: menu
            objectName: "sectionMenu_" + root.sectionData.id
            visible: root.sectionData.id.length > 0
            implicitWidth: 24; implicitHeight: 24; padding: 5
            contentItem: Demo.VectorIcon { name: "more"; size: 14; color: design.labelSecondary }
            background: Rectangle { radius: 12; color: sectionMore.hovered ? design.rowHoverFill : "transparent" }
            Accessible.name: qsTr("Manage section")
            onClicked: menu.openAtAnchor()
        }
        ToolButton {
            id: fold
            objectName: "sectionFold_" + root.sectionData.id
            implicitWidth: 24; implicitHeight: 24; padding: 6
            contentItem: Demo.VectorIcon { name: root.collapsed ? "forward" : "chevron"; size: 12; color: design.labelSecondary }
            background: Rectangle { radius: 12; color: fold.hovered ? design.rowHoverFill : "transparent" }
            Accessible.name: qsTr("Show or hide section")
            onClicked: root.workspace.toggleSection(root.sectionKey)
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: root.card ? 4 : 0
        visible: !root.collapsed
        Repeater {
            model: root.sectionData.todos
            delegate: CalendarReminderRow {
                required property var modelData
                Layout.fillWidth: true
                workspace: root.workspace
                todo: modelData
                card: root.card
            }
        }
        CalendarReminderInlineAdd {
            id: inlineAdd
            Layout.fillWidth: true
            visible: root.sectionData.canAdd
            workspace: root.workspace
            listId: root.sectionData.listId
            section: root.sectionData.name
            card: root.card
        }
    }
    Demo.LiquidPopover {
        id: menu
        anchorItem: sectionMore
        sourceItem: root.workspace.sourceItem
        Demo.LiquidPopoverItem { objectName: "renameReminderSection_" + root.sectionData.id; text: qsTr("Rename section"); iconName: "editRounded"; onTriggered: { root.renaming = true; nameInput.forceActiveFocus(); nameInput.selectAll() } }
        Demo.LiquidPopoverItem { text: qsTr("Move up"); enabled: root.sectionData.position > 0; onTriggered: root.workspace.pim.saveSection(root.sectionData.listId, root.sectionData.id, {position: root.sectionData.position - 1}) }
        Demo.LiquidPopoverItem { objectName: "moveReminderSectionDown_" + root.sectionData.id; text: qsTr("Move down"); enabled: root.sectionData.position + 1 < root.sectionData.sectionCount; onTriggered: root.workspace.pim.saveSection(root.sectionData.listId, root.sectionData.id, {position: root.sectionData.position + 1}) }
        Demo.LiquidPopoverItem { objectName: "removeReminderSection_" + root.sectionData.id; text: qsTr("Remove section…"); iconName: "trashRounded"; onTriggered: root.workspace.removeSectionRequested(root.sectionData, sectionMore) }
    }
}
