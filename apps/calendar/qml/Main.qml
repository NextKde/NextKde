pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Kos.Pim
import Kos.Ui

KosApplicationWindow {
    id: root

    visible: true
    title: qsTr("Calendar")
    minimumWidth: 900
    minimumHeight: 620

    property date visibleMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date selectedDate: new Date()
    property int viewIndex: 0
    property string searchQuery: ""
    property bool showEvents: true
    property bool showTasks: true
    property bool showCompletedTasks: false
    property string statusMessage: ""

    readonly property string activeView: ["month", "week", "day"][viewIndex]
    readonly property date weekStart: startOfWeek(selectedDate)
    readonly property var selectedItems: itemsForDate(selectedDate)

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        const result = record[key]
        return result === undefined || result === null ? fallback : result
    }

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear()
            && left.getMonth() === right.getMonth()
            && left.getDate() === right.getDate()
    }

    function dateKey(date) {
        return Qt.formatDate(date, "yyyy-MM-dd")
    }

    function startOfWeek(date) {
        const mondayOffset = (date.getDay() + 6) % 7
        return new Date(date.getFullYear(), date.getMonth(), date.getDate() - mondayOffset)
    }

    function monthDate(offset) {
        return new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + offset, 1)
    }

    function dateForMonthCell(index) {
        const first = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1)
        const mondayOffset = (first.getDay() + 6) % 7
        return new Date(first.getFullYear(), first.getMonth(), index - mondayOffset + 1)
    }

    function eventContainsDate(event, key) {
        const start = String(value(event, "start", "")).slice(0, 10)
        const end = String(value(event, "end", "")).slice(0, 10)
        return start === key || (start < key && end > key)
    }

    function matchesSearch(record) {
        const query = searchQuery.trim().toLocaleLowerCase()
        if (query.length === 0)
            return true
        const haystack = (String(value(record, "title", "")) + "\n"
            + String(value(record, "description", "")) + "\n"
            + String(value(record, "location", ""))).toLocaleLowerCase()
        return haystack.indexOf(query) >= 0
    }

    function itemsForDate(date) {
        const key = dateKey(date)
        const result = []
        const representedTodos = ({})

        if (showEvents) {
            const events = pim.occurrences ?? []
            for (let index = 0; index < events.length; index++) {
                const event = events[index]
                if (!eventContainsDate(event, key) || !matchesSearch(event))
                    continue
                result.push({ kind: "event", record: event })
                const todoId = String(value(event, "linkedTodoId", ""))
                if (todoId.length > 0)
                    representedTodos[todoId] = true
            }
        }

        if (showTasks) {
            const todos = pim.todoOccurrences ?? []
            for (let index = 0; index < todos.length; index++) {
                const todo = todos[index]
                const due = String(value(todo, "due", "")).slice(0, 10)
                const id = String(value(todo, "seriesId", value(todo, "id", "")))
                if (due !== key || representedTodos[id] || !matchesSearch(todo))
                    continue
                if (!showCompletedTasks && Boolean(value(todo, "completed", false)))
                    continue
                result.push({ kind: "todo", record: todo })
            }
        }

        result.sort(function(left, right) {
            const leftAllDay = itemAllDay(left)
            const rightAllDay = itemAllDay(right)
            if (leftAllDay !== rightAllDay)
                return leftAllDay ? -1 : 1
            return itemDateTime(left).localeCompare(itemDateTime(right))
        })
        return result
    }

    function itemRecord(item) {
        return value(item, "record", ({}))
    }

    function itemTitle(item) {
        return String(value(itemRecord(item), "title", qsTr("Untitled")))
    }

    function itemDateTime(item) {
        const record = itemRecord(item)
        return String(value(record, item.kind === "todo" ? "due" : "start", ""))
    }

    function itemTime(item) {
        if (itemAllDay(item))
            return qsTr("All day")
        const match = itemDateTime(item).match(/T(\d{2}:\d{2})/)
        return match ? match[1] : "--:--"
    }

    function itemHour(item) {
        const match = itemDateTime(item).match(/T(\d{2}):/)
        return match ? Number(match[1]) : 0
    }

    function itemAllDay(item) {
        return Boolean(value(itemRecord(item), "allDay", false))
    }

    function itemCompleted(item) {
        const record = itemRecord(item)
        return item.kind === "todo"
            ? Boolean(value(record, "completed", false))
            : Boolean(value(record, "linkedTodoCompleted", false))
    }

    function itemTodoId(item) {
        const record = itemRecord(item)
        if (item.kind === "todo")
            return String(value(record, "seriesId", value(record, "id", "")))
        return String(value(record, "linkedTodoId", ""))
    }

    function listColor(id) {
        for (let index = 0; index < pim.lists.length; index++) {
            const list = pim.lists[index]
            if (String(value(list, "id", "")) === String(id))
                return Qt.darker(String(value(list, "color", AppTheme.accent)), 1.0)
        }
        return AppTheme.accent
    }

    function listName(id) {
        for (let index = 0; index < pim.lists.length; index++) {
            const list = pim.lists[index]
            if (String(value(list, "id", "")) === String(id))
                return String(value(list, "name", qsTr("List")))
        }
        return qsTr("List")
    }

    function itemColor(item) {
        const record = itemRecord(item)
        if (item.kind === "todo")
            return listColor(value(record, "listId", "inbox"))
        return AppTheme.accent
    }

    function itemSubtitle(item) {
        const record = itemRecord(item)
        if (item.kind === "todo")
            return listName(value(record, "listId", "inbox"))
        const location = String(value(record, "location", ""))
        return location.length > 0 ? location
            : (String(value(record, "linkedTodoId", "")).length > 0
                ? qsTr("Linked with Todo") : qsTr("Calendar event"))
    }

    function openItem(item) {
        if (item.kind === "todo")
            taskEditor.openForTodo(itemRecord(item))
        else
            eventEditor.openForEvent(itemRecord(item))
    }

    function toggleItem(item, completed) {
        const todoId = itemTodoId(item)
        if (todoId.length > 0)
            pim.updateTodo(todoId, { completed: completed })
    }

    function updateEventRange() {
        let first
        let last
        if (activeView === "month") {
            first = dateForMonthCell(0)
            last = dateForMonthCell(41)
        } else if (activeView === "week") {
            first = weekStart
            last = new Date(first.getFullYear(), first.getMonth(), first.getDate() + 6)
        } else {
            first = selectedDate
            last = selectedDate
        }
        pim.setEventRange(dateKey(first), dateKey(last))
    }

    function showToday() {
        const today = new Date()
        selectedDate = today
        visibleMonth = new Date(today.getFullYear(), today.getMonth(), 1)
        Qt.callLater(updateEventRange)
    }

    function shiftView(offset) {
        if (activeView === "month") {
            const currentDay = selectedDate.getDate()
            const target = monthDate(offset)
            const lastDay = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate()
            visibleMonth = target
            selectedDate = new Date(target.getFullYear(), target.getMonth(),
                                    Math.min(currentDay, lastDay))
        } else {
            const days = activeView === "week" ? 7 : 1
            selectedDate = new Date(selectedDate.getFullYear(), selectedDate.getMonth(),
                                    selectedDate.getDate() + offset * days)
            visibleMonth = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
        }
        Qt.callLater(updateEventRange)
    }

    function headerTitle() {
        if (activeView === "month")
            return Qt.formatDate(visibleMonth, "MMMM yyyy")
        if (activeView === "day")
            return Qt.formatDate(selectedDate, Locale.LongFormat)
        const end = new Date(weekStart.getFullYear(), weekStart.getMonth(),
                             weekStart.getDate() + 6)
        if (weekStart.getMonth() === end.getMonth())
            return Qt.formatDate(weekStart, "MMM d") + " – "
                + Qt.formatDate(end, "d, yyyy")
        return Qt.formatDate(weekStart, "MMM d") + " – "
            + Qt.formatDate(end, "MMM d, yyyy")
    }

    function showStatus(message) {
        statusMessage = message
        statusTimer.restart()
    }

    onVisibleMonthChanged: {
        if (activeView === "month")
            Qt.callLater(updateEventRange)
    }
    onSelectedDateChanged: {
        if (activeView !== "month")
            Qt.callLater(updateEventRange)
    }
    onViewIndexChanged: Qt.callLater(updateEventRange)

    PimClient { id: pim }

    Connections {
        target: pim

        function onOperationSucceeded(operation, itemId) {
            if (operation === "createEvent")
                root.showStatus(qsTr("Event created"))
            else if (operation === "updateEvent")
                root.showStatus(qsTr("Event updated"))
            else if (operation === "updateTodo")
                root.showStatus(qsTr("Task updated in Calendar and Todo"))
            else if (operation === "removeEvent")
                root.showStatus(qsTr("Event removed"))
            else if (operation === "removeTodo")
                root.showStatus(qsTr("Task removed"))
            else if (operation === "importIcalendar")
                root.showStatus(qsTr("Calendar imported"))
            else if (operation === "exportIcalendar")
                root.showStatus(qsTr("Calendar exported"))
            Qt.callLater(root.updateEventRange)
        }
    }

    Timer {
        id: statusTimer
        interval: 3500
        onTriggered: root.statusMessage = ""
    }

    FileDialog {
        id: importDialog
        title: qsTr("Import iCalendar")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("iCalendar files (*.ics)"), qsTr("All files (*)")]
        onAccepted: pim.importIcalendar(selectedFile.toString(), false)
    }

    FileDialog {
        id: exportDialog
        title: qsTr("Export iCalendar")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "ics"
        nameFilters: [qsTr("iCalendar files (*.ics)")]
        onAccepted: pim.exportIcalendar(selectedFile.toString())
    }

    EventEditorDialog {
        id: eventEditor
        parent: root.contentItem
        availableLists: pim.lists
        onSaveRequested: function(uid, event) {
            if (uid.length > 0)
                pim.updateEvent(uid, event)
            else
                pim.createEvent(event)
        }
        onDeleteRequested: uid => pim.removeEvent(uid)
    }

    CalendarTaskEditorDialog {
        id: taskEditor
        parent: root.contentItem
        availableLists: pim.lists
        onSaveRequested: function(uid, todo) { pim.updateTodo(uid, todo) }
        onDeleteRequested: uid => pim.removeTodo(uid)
    }

    Shortcut { sequence: StandardKey.New; onActivated: eventEditor.openForDate(root.selectedDate) }
    Shortcut { sequence: "Ctrl+T"; onActivated: root.showToday() }
    Shortcut { sequence: "Ctrl+1"; onActivated: root.viewIndex = 0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: root.viewIndex = 1 }
    Shortcut { sequence: "Ctrl+3"; onActivated: root.viewIndex = 2 }
    Shortcut { sequence: StandardKey.Find; onActivated: searchField.forceActiveFocus() }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 244
            color: AppTheme.withAlpha(AppTheme.sidebar, 0.94)
            border.width: 1
            border.color: AppTheme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Label {
                    text: qsTr("KOS Calendar")
                    color: AppTheme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    Layout.bottomMargin: 6
                }

                RowLayout {
                    Layout.fillWidth: true

                    ToolButton {
                        text: "‹"
                        flat: true
                        onClicked: root.visibleMonth = root.monthDate(-1)
                    }
                    Label {
                        Layout.fillWidth: true
                        text: Qt.formatDate(root.visibleMonth, "MMMM yyyy")
                        color: AppTheme.text
                        horizontalAlignment: Text.AlignHCenter
                        font.weight: Font.DemiBold
                        font.pixelSize: 12
                    }
                    ToolButton {
                        text: "›"
                        flat: true
                        onClicked: root.visibleMonth = root.monthDate(1)
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    columnSpacing: 1
                    rowSpacing: 1

                    Repeater {
                        model: 7
                        delegate: Label {
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
                            text: Qt.locale().dayName(index + 1, Locale.NarrowFormat)
                            color: AppTheme.mutedText
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 9
                        }
                    }

                    Repeater {
                        model: 42
                        delegate: Button {
                            id: miniDay
                            required property int index
                            readonly property date cellDate: root.dateForMonthCell(index)
                            readonly property bool selected: root.sameDay(cellDate, root.selectedDate)
                            readonly property bool today: root.sameDay(cellDate, new Date())
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            text: String(cellDate.getDate())
                            flat: true
                            opacity: cellDate.getMonth() === root.visibleMonth.getMonth() ? 1 : 0.38
                            font.pixelSize: 9
                            onClicked: {
                                root.selectedDate = cellDate
                                if (root.activeView === "month"
                                        && cellDate.getMonth() !== root.visibleMonth.getMonth()) {
                                    root.visibleMonth = new Date(cellDate.getFullYear(),
                                                                 cellDate.getMonth(), 1)
                                }
                            }
                            background: Rectangle {
                                radius: 12
                                color: miniDay.today ? AppTheme.accent
                                    : (miniDay.selected
                                        ? AppTheme.withAlpha(AppTheme.accent, 0.16)
                                        : (miniDay.hovered ? AppTheme.cardHover : "transparent"))
                            }
                            palette.buttonText: today ? "white" : AppTheme.text
                        }
                    }
                }

                Label {
                    Layout.topMargin: 12
                    text: qsTr("CALENDARS")
                    color: AppTheme.mutedText
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                CheckBox {
                    text: qsTr("Events")
                    checked: root.showEvents
                    onToggled: root.showEvents = checked
                }

                CheckBox {
                    text: qsTr("Scheduled tasks")
                    checked: root.showTasks
                    onToggled: root.showTasks = checked
                }

                CheckBox {
                    leftPadding: 28
                    text: qsTr("Show completed tasks")
                    checked: root.showCompletedTasks
                    enabled: root.showTasks
                    onToggled: root.showCompletedTasks = checked
                    font.pixelSize: 10
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 118)
                    clip: true
                    model: pim.lists
                    spacing: 2

                    delegate: Item {
                        id: listLegend
                        required property var modelData
                        width: ListView.view.width
                        height: 24

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 8
                            spacing: 8
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: String(root.value(listLegend.modelData,
                                    "color", AppTheme.accent))
                            }
                            Label {
                                text: String(root.value(listLegend.modelData,
                                    "name", qsTr("List")))
                                color: AppTheme.mutedText
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Label {
                    Layout.fillWidth: true
                    text: pim.connected
                        ? qsTr("Calendar and Todo are synchronized")
                        : qsTr("Waiting for the local PIM service")
                    color: pim.connected ? AppTheme.positive : AppTheme.warning
                    wrapMode: Text.WordWrap
                    font.pixelSize: 10
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ToolButton {
                    Layout.preferredWidth: 36
                    text: "‹"
                    Accessible.name: qsTr("Previous period")
                    onClicked: root.shiftView(-1)
                }
                ToolButton {
                    Layout.preferredWidth: 36
                    text: "›"
                    Accessible.name: qsTr("Next period")
                    onClicked: root.shiftView(1)
                }
                Button {
                    Layout.preferredWidth: 74
                    text: qsTr("Today")
                    onClicked: root.showToday()
                }

                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 142
                    text: root.headerTitle()
                    color: AppTheme.text
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                BusyIndicator {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    running: pim.busy
                    visible: running
                }

                LiquidTextField {
                    id: searchField
                    Layout.preferredWidth: 150
                    placeholderText: qsTr("Search events and tasks")
                    text: root.searchQuery
                    onTextEdited: root.searchQuery = text
                    Accessible.name: qsTr("Search calendar")
                }

                LiquidSegmentedControl {
                    Layout.preferredWidth: 174
                    labels: [qsTr("Month"), qsTr("Week"), qsTr("Day")]
                    currentIndex: root.viewIndex
                    backgroundColor: AppTheme.withAlpha(AppTheme.text,
                        AppTheme.dark ? 0.10 : 0.06)
                    selectionColor: AppTheme.dark ? AppTheme.cardHover : AppTheme.windowRaised
                    textColor: AppTheme.text
                    mutedTextColor: AppTheme.mutedText
                    onSelectionRequested: index => root.viewIndex = index
                }

                Button {
                    Layout.preferredWidth: 96
                    text: qsTr("New event")
                    highlighted: true
                    enabled: pim.connected && pim.writable
                    onClicked: eventEditor.openForDate(root.selectedDate)
                }

                Button {
                    id: actionsButton
                    Layout.preferredWidth: 42
                    text: "⋯"
                    Accessible.name: qsTr("Calendar actions")
                    onClicked: actionsMenu.open()

                    Menu {
                        id: actionsMenu
                        y: actionsButton.height
                        MenuItem {
                            text: qsTr("Import iCalendar…")
                            enabled: pim.connected && pim.writable
                            onTriggered: importDialog.open()
                        }
                        MenuItem {
                            text: qsTr("Export iCalendar…")
                            enabled: pim.connected && pim.ready
                            onTriggered: exportDialog.open()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.statusMessage.length > 0 || (pim.errorMessage.length > 0 && pim.ready)

                Label {
                    Layout.fillWidth: true
                    text: pim.errorMessage.length > 0 ? pim.errorMessage : root.statusMessage
                    color: pim.errorMessage.length > 0 ? AppTheme.warning : AppTheme.positive
                    wrapMode: Text.WordWrap
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.viewIndex

                ColumnLayout {
                    spacing: 10

                    CalendarMonthView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visibleDate: root.visibleMonth
                        selectedDate: root.selectedDate
                        itemsForDate: root.itemsForDate
                        itemTitle: root.itemTitle
                        itemColor: root.itemColor
                        itemCompleted: root.itemCompleted
                        onDateSelected: function(date) { root.selectedDate = date }
                        onItemActivated: function(item) { root.openItem(item) }
                        onCreateRequested: function(date) { eventEditor.openForDate(date) }
                    }

                    KosCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 210

                        contentItem: ColumnLayout {
                            spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: Qt.formatDate(root.selectedDate, Locale.LongFormat)
                                    color: AppTheme.text
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }
                                Label {
                                    text: qsTr("%n item(s)", "", root.selectedItems.length)
                                    color: AppTheme.mutedText
                                    font.pixelSize: 11
                                }
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: qsTr("Add")
                                    flat: true
                                    enabled: pim.connected && pim.writable
                                    onClicked: eventEditor.openForDate(root.selectedDate)
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: qsTr("No events or scheduled tasks for this day")
                                color: AppTheme.mutedText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                visible: root.selectedItems.length === 0
                            }

                            ListView {
                                id: dayAgenda
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.selectedItems.length > 0
                                clip: true
                                spacing: 2
                                model: root.selectedItems

                                delegate: ItemDelegate {
                                    id: agendaItem
                                    required property var modelData
                                    width: dayAgenda.width
                                    implicitHeight: 38
                                    onClicked: root.openItem(modelData)

                                    contentItem: RowLayout {
                                        spacing: 9
                                        CheckBox {
                                            visible: root.itemTodoId(agendaItem.modelData).length > 0
                                            checked: root.itemCompleted(agendaItem.modelData)
                                            Accessible.name: checked
                                                ? qsTr("Mark task open") : qsTr("Mark task complete")
                                            onClicked: root.toggleItem(agendaItem.modelData, checked)
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 4
                                            Layout.preferredHeight: 30
                                            radius: 2
                                            color: root.itemColor(agendaItem.modelData)
                                        }
                                        Label {
                                            Layout.preferredWidth: 58
                                            text: root.itemTime(agendaItem.modelData)
                                            color: AppTheme.mutedText
                                            font.pixelSize: 11
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Label {
                                                Layout.fillWidth: true
                                                text: root.itemTitle(agendaItem.modelData)
                                                color: root.itemCompleted(agendaItem.modelData)
                                                    ? AppTheme.mutedText : AppTheme.text
                                                font.strikeout: root.itemCompleted(agendaItem.modelData)
                                                elide: Text.ElideRight
                                            }
                                            Label {
                                                text: root.itemSubtitle(agendaItem.modelData)
                                                color: AppTheme.mutedText
                                                font.pixelSize: 10
                                            }
                                        }
                                        Label {
                                            text: agendaItem.modelData.kind === "todo"
                                                ? qsTr("TASK")
                                                : (root.itemTodoId(agendaItem.modelData).length > 0
                                                    ? qsTr("EVENT + TASK") : qsTr("EVENT"))
                                            color: root.itemColor(agendaItem.modelData)
                                            font.pixelSize: 9
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                CalendarScheduleView {
                    firstDate: root.weekStart
                    dayCount: 7
                    itemsForDate: root.itemsForDate
                    itemTitle: root.itemTitle
                    itemColor: root.itemColor
                    itemCompleted: root.itemCompleted
                    itemAllDay: root.itemAllDay
                    itemHour: root.itemHour
                    onDateSelected: function(date) { root.selectedDate = date }
                    onItemActivated: function(item) { root.openItem(item) }
                    onCreateRequested: function(date, hour) {
                        eventEditor.openForDate(date, hour)
                    }
                }

                CalendarScheduleView {
                    firstDate: root.selectedDate
                    dayCount: 1
                    itemsForDate: root.itemsForDate
                    itemTitle: root.itemTitle
                    itemColor: root.itemColor
                    itemCompleted: root.itemCompleted
                    itemAllDay: root.itemAllDay
                    itemHour: root.itemHour
                    onDateSelected: function(date) { root.selectedDate = date }
                    onItemActivated: function(item) { root.openItem(item) }
                    onCreateRequested: function(date, hour) {
                        eventEditor.openForDate(date, hour)
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        const argumentsList = Qt.application.arguments
        if (argumentsList.indexOf("week") >= 0)
            viewIndex = 1
        else if (argumentsList.indexOf("day") >= 0)
            viewIndex = 2
        updateEventRange()
    }
}
