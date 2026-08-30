pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Pim
import Kos.Ui

KosApplicationWindow {
    id: root

    visible: true
    title: qsTr("Todo")

    property string activeFilter: "inbox"
    property string activeListId: "inbox"
    readonly property var visibleTodos: filteredTodos()

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        const result = record[key]
        return result === undefined || result === null ? fallback : result
    }

    function datePart(value) {
        return String(value ?? "").slice(0, 10)
    }

    function todayKey() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd")
    }

    function filteredTodos() {
        const result = []
        const today = todayKey()
        const source = pim.todos ?? []
        for (let index = 0; index < source.length; index++) {
            const todo = source[index]
            const completed = Boolean(value(todo, "completed", false))
            const due = datePart(value(todo, "due", ""))
            let include = false
            if (activeFilter === "inbox")
                include = !completed && String(value(todo, "listId", "inbox")) === "inbox"
            else if (activeFilter === "today")
                include = !completed && due === today
            else if (activeFilter === "planned")
                include = !completed && due.length > 0
            else if (activeFilter === "calendar")
                include = !completed
                    && String(value(todo, "linkedEventId", "")).length > 0
            else if (activeFilter === "completed")
                include = completed
            else if (activeFilter === "list")
                include = !completed
                    && String(value(todo, "listId", "inbox")) === activeListId
            if (include)
                result.push(todo)
        }
        return result
    }

    function filterTitle() {
        if (activeFilter === "today") return qsTr("Today")
        if (activeFilter === "planned") return qsTr("Planned")
        if (activeFilter === "calendar") return qsTr("Calendar")
        if (activeFilter === "completed") return qsTr("Completed")
        if (activeFilter === "list") return listName(activeListId)
        return qsTr("Inbox")
    }

    function listName(id) {
        for (let index = 0; index < pim.lists.length; index++) {
            const list = pim.lists[index]
            if (String(value(list, "id", "")) === String(id))
                return String(value(list, "name", qsTr("List")))
        }
        return qsTr("List")
    }

    function dueLabel(todo) {
        const due = String(value(todo, "due", ""))
        if (due.length === 0)
            return ""
        const date = due.slice(0, 10)
        if (Boolean(value(todo, "allDay", false)))
            return date === todayKey() ? qsTr("Today") : date
        const match = due.match(/T(\d{2}:\d{2})/)
        return date + (match ? " · " + match[1] : "")
    }

    function isOverdue(todo) {
        const due = datePart(value(todo, "due", ""))
        return due.length > 0 && due < todayKey()
            && !Boolean(value(todo, "completed", false))
    }

    function priorityColor(todo) {
        const priority = Number(value(todo, "priority", 0))
        if (priority > 0 && priority <= 3)
            return AppTheme.destructive
        if (priority <= 6 && priority > 0)
            return AppTheme.warning
        return AppTheme.accent
    }

    function addTask() {
        const title = taskField.text.trim()
        if (title.length === 0)
            return
        pim.createTodo({
            title: title,
            listId: activeFilter === "list" ? activeListId : "inbox",
            order: Date.now()
        })
        taskField.clear()
        taskField.forceActiveFocus()
    }

    function selectFilter(filter, listId) {
        activeFilter = filter
        if (listId !== undefined)
            activeListId = listId
    }

    PimClient { id: pim }

    TodoEditorDialog {
        id: todoEditor

        parent: root.contentItem
        availableLists: pim.lists
        defaultListId: root.activeFilter === "list" ? root.activeListId : "inbox"
        onSaveRequested: function(uid, todo) {
            if (uid.length > 0)
                pim.updateTodo(uid, todo)
            else
                pim.createTodo(todo)
        }
        onDeleteRequested: uid => pim.removeTodo(uid)
    }

    Dialog {
        id: listDialog

        parent: root.contentItem
        title: qsTr("New list")
        modal: true
        anchors.centerIn: parent
        width: 380
        standardButtons: Dialog.Save | Dialog.Cancel
        onOpened: listNameField.forceActiveFocus()
        onAccepted: {
            const name = listNameField.text.trim()
            if (name.length > 0)
                pim.createList({ name: name, color: "#4f8cff" })
            listNameField.clear()
        }

        contentItem: ColumnLayout {
            spacing: 8

            Label { text: qsTr("List name"); color: AppTheme.mutedText }
            LiquidTextField {
                id: listNameField
                Layout.fillWidth: true
                placeholderText: qsTr("e.g. Work")
                Accessible.name: qsTr("New list name")
                onAccepted: listDialog.accept()
            }
        }
    }

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
                    checked: root.activeFilter === "inbox"
                    ButtonGroup.group: navigationGroup
                    onClicked: root.selectFilter("inbox")
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Today")
                    symbol: "◉"
                    checked: root.activeFilter === "today"
                    ButtonGroup.group: navigationGroup
                    onClicked: root.selectFilter("today")
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Planned")
                    symbol: "◫"
                    checked: root.activeFilter === "planned"
                    ButtonGroup.group: navigationGroup
                    onClicked: root.selectFilter("planned")
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Calendar")
                    symbol: "▦"
                    checked: root.activeFilter === "calendar"
                    ButtonGroup.group: navigationGroup
                    onClicked: root.selectFilter("calendar")
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Completed")
                    symbol: "✓"
                    checked: root.activeFilter === "completed"
                    ButtonGroup.group: navigationGroup
                    onClicked: root.selectFilter("completed")
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 16

                    Label {
                        text: qsTr("MY LISTS")
                        color: AppTheme.mutedText
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "+"
                        flat: true
                        enabled: pim.connected && pim.writable
                        Accessible.name: qsTr("Create list")
                        onClicked: listDialog.open()
                    }
                }

                ListView {
                    id: listNavigation
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 3
                    model: pim.lists

                    delegate: KosNavigationButton {
                        id: listButton

                        required property var modelData
                        width: listNavigation.width
                        text: String(root.value(modelData, "name", qsTr("List")))
                        symbol: "●"
                        checked: root.activeFilter === "list"
                            && root.activeListId === String(root.value(modelData, "id", ""))
                        ButtonGroup.group: navigationGroup
                        onClicked: root.selectFilter("list",
                            String(root.value(modelData, "id", "inbox")))
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: pim.connected
                        ? qsTr("Local iCalendar service connected")
                        : qsTr("Waiting for the local PIM service")
                    color: pim.connected ? AppTheme.positive : AppTheme.warning
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
                        text: root.filterTitle()
                        color: AppTheme.text
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    Label {
                        text: qsTr("%n task(s)", "", root.visibleTodos.length)
                        color: AppTheme.mutedText
                    }
                }

                Item { Layout.fillWidth: true }

                BusyIndicator {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    running: pim.busy
                    visible: running
                }

                Button {
                    text: qsTr("New task")
                    highlighted: true
                    enabled: pim.connected && pim.writable
                    onClicked: todoEditor.openNew()
                }
            }

            KosCard {
                Layout.fillWidth: true

                contentItem: RowLayout {
                    spacing: 10

                    LiquidTextField {
                        id: taskField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Add a task to %1…").arg(
                            root.activeFilter === "list"
                                ? root.listName(root.activeListId) : qsTr("Inbox"))
                        Accessible.name: qsTr("New task title")
                        enabled: pim.connected && pim.writable
                        onAccepted: root.addTask()
                    }

                    Button {
                        text: qsTr("Add")
                        highlighted: true
                        enabled: taskField.enabled && taskField.text.trim().length > 0
                        onClicked: root.addTask()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: todoError.implicitHeight + 20
                radius: AppTheme.smallRadius
                color: AppTheme.withAlpha(AppTheme.warning, AppTheme.dark ? 0.16 : 0.12)
                border.width: 1
                border.color: AppTheme.withAlpha(AppTheme.warning, 0.35)
                visible: pim.errorMessage.length > 0 && pim.ready

                Label {
                    id: todoError
                    anchors.fill: parent
                    anchors.margins: 10
                    text: pim.errorMessage
                    color: AppTheme.text
                    wrapMode: Text.WordWrap
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
                        visible: root.visibleTodos.length === 0
                        symbol: root.activeFilter === "completed" ? "◇" : "✓"
                        title: root.activeFilter === "completed"
                            ? qsTr("No completed tasks") : qsTr("Nothing to do here")
                        description: pim.connected
                            ? qsTr("Create a task or choose another list.")
                            : qsTr("Start the local PIM service to load tasks.")
                        actionText: pim.connected && pim.writable ? qsTr("New task") : ""
                        onActionTriggered: todoEditor.openNew()
                    }

                    ListView {
                        id: taskList
                        anchors.fill: parent
                        visible: root.visibleTodos.length > 0
                        clip: true
                        spacing: 6
                        model: root.visibleTodos
                        currentIndex: -1

                        delegate: ItemDelegate {
                            id: taskDelegate

                            required property var modelData
                            width: taskList.width
                            implicitHeight: 60
                            leftPadding: String(root.value(modelData, "parentId", "")).length > 0
                                ? 34 : 10
                            rightPadding: 8
                            onClicked: todoEditor.openForTodo(modelData)

                            contentItem: RowLayout {
                                spacing: 10

                                CheckBox {
                                    checked: Boolean(root.value(taskDelegate.modelData,
                                        "completed", false))
                                    Accessible.name: checked
                                        ? qsTr("Mark task open") : qsTr("Mark task complete")
                                    onClicked: pim.updateTodo(String(root.value(
                                        taskDelegate.modelData, "id", "")), {
                                            completed: checked
                                        })
                                }

                                Rectangle {
                                    Layout.preferredWidth: 4
                                    Layout.preferredHeight: 34
                                    radius: 2
                                    color: root.priorityColor(taskDelegate.modelData)
                                    opacity: Number(root.value(taskDelegate.modelData,
                                        "priority", 0)) > 0 ? 1 : 0.18
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Label {
                                        Layout.fillWidth: true
                                        text: String(root.value(taskDelegate.modelData,
                                            "title", qsTr("Untitled task")))
                                        color: Boolean(root.value(taskDelegate.modelData,
                                            "completed", false))
                                            ? AppTheme.mutedText : AppTheme.text
                                        font.strikeout: Boolean(root.value(taskDelegate.modelData,
                                            "completed", false))
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Label {
                                            text: root.dueLabel(taskDelegate.modelData)
                                            color: root.isOverdue(taskDelegate.modelData)
                                                ? AppTheme.destructive : AppTheme.mutedText
                                            font.pixelSize: 11
                                            visible: text.length > 0
                                        }

                                        Label {
                                            text: root.listName(String(root.value(
                                                taskDelegate.modelData, "listId", "inbox")))
                                            color: AppTheme.mutedText
                                            font.pixelSize: 11
                                        }

                                        Label {
                                            text: "↻"
                                            color: AppTheme.accent
                                            visible: String(root.value(taskDelegate.modelData,
                                                "recurrence", "none")) !== "none"
                                            Accessible.name: qsTr("Repeating task")
                                        }

                                        Label {
                                            text: qsTr("Calendar linked")
                                            color: AppTheme.accent
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            visible: String(root.value(taskDelegate.modelData,
                                                "linkedEventId", "")).length > 0
                                        }
                                    }
                                }

                                Button {
                                    text: "⋯"
                                    flat: true
                                    Accessible.name: qsTr("Edit task")
                                    onClicked: todoEditor.openForTodo(taskDelegate.modelData)
                                }

                                Button {
                                    text: "×"
                                    flat: true
                                    Accessible.name: qsTr("Delete task")
                                    onClicked: pim.removeTodo(String(root.value(
                                        taskDelegate.modelData, "id", "")))
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
