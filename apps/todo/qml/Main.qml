pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosApplicationWindow {
    id: root

    visible: true
    title: qsTr("Todo")

    function addTask() {
        const title = taskField.text.trim()
        if (title.length === 0)
            return
        tasks.append({ taskTitle: title, completed: false })
        taskField.clear()
        taskField.forceActiveFocus()
    }

    ListModel { id: tasks }

    Shortcut {
        sequence: StandardKey.New
        onActivated: taskField.forceActiveFocus()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 238
            color: AppTheme.withAlpha(AppTheme.sidebar, 0.92)
            border.width: 1
            border.color: AppTheme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 8

                Label {
                    text: qsTr("KOS Todo")
                    color: AppTheme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    Layout.bottomMargin: 16
                }

                ButtonGroup { id: navigationGroup }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Inbox")
                    symbol: "▣"
                    checked: true
                    ButtonGroup.group: navigationGroup
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Today")
                    symbol: "◉"
                    ButtonGroup.group: navigationGroup
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Planned")
                    symbol: "◫"
                    ButtonGroup.group: navigationGroup
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Completed")
                    symbol: "✓"
                    ButtonGroup.group: navigationGroup
                }

                Label {
                    Layout.topMargin: 20
                    text: qsTr("MY LISTS")
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Personal")
                    symbol: "●"
                }

                Item { Layout.fillHeight: true }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Prototype tasks remain in memory until the PIM service is connected.")
                    color: AppTheme.mutedText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: AppTheme.pageMargin
            spacing: 16

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 2

                    Label {
                        text: qsTr("Inbox")
                        color: AppTheme.text
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    Label {
                        text: qsTr("%n open task(s)", "", tasks.count)
                        color: AppTheme.mutedText
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: qsTr("Task options")
                    enabled: false
                }
            }

            KosCard {
                Layout.fillWidth: true

                contentItem: RowLayout {
                    spacing: 10

                    LiquidTextField {
                        id: taskField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Add a task…")
                        Accessible.name: qsTr("New task title")
                        onAccepted: root.addTask()
                    }

                    Button {
                        text: qsTr("Add")
                        highlighted: true
                        enabled: taskField.text.trim().length > 0
                        onClicked: root.addTask()
                    }
                }
            }

            KosCard {
                Layout.fillWidth: true
                Layout.fillHeight: true

                contentItem: Item {
                    KosEmptyState {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, implicitWidth)
                        height: implicitHeight
                        visible: tasks.count === 0
                        symbol: "✓"
                        title: qsTr("Nothing to do yet")
                        description: qsTr("Add a task above. Persistent lists, due dates, recurrence, and reminders arrive with the PIM service.")
                        actionText: qsTr("Focus task field")
                        onActionTriggered: taskField.forceActiveFocus()
                    }

                    ListView {
                        id: taskList
                        anchors.fill: parent
                        visible: tasks.count > 0
                        clip: true
                        spacing: 6
                        model: tasks
                        currentIndex: -1

                        delegate: ItemDelegate {
                            id: taskDelegate

                            required property int index
                            required property string taskTitle
                            required property bool completed

                            width: taskList.width
                            implicitHeight: 52

                            contentItem: RowLayout {
                                spacing: 10

                                CheckBox {
                                    checked: taskDelegate.completed
                                    Accessible.name: qsTr("Mark %1 complete").arg(taskDelegate.taskTitle)
                                    onToggled: tasks.setProperty(taskDelegate.index, "completed", checked)
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: taskDelegate.taskTitle
                                    color: taskDelegate.completed
                                        ? AppTheme.mutedText : AppTheme.text
                                    font.strikeout: taskDelegate.completed
                                    elide: Text.ElideRight
                                }

                                Button {
                                    text: "×"
                                    flat: true
                                    Accessible.name: qsTr("Delete %1").arg(taskDelegate.taskTitle)
                                    onClicked: tasks.remove(taskDelegate.index)
                                }
                            }

                            background: Rectangle {
                                radius: AppTheme.smallRadius
                                color: taskDelegate.hovered ? AppTheme.cardHover : "transparent"
                                border.width: taskDelegate.activeFocus ? 1 : 0
                                border.color: AppTheme.withAlpha(AppTheme.accent, 0.58)
                            }
                        }
                    }
                }
            }
        }
    }
}
