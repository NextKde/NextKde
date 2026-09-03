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
    minimumWidth: 760
    minimumHeight: 540

    property date now: new Date()
    property date visibleMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date selectedDate: new Date()
    property int viewIndex: 0
    property string searchQuery: ""
    property bool showEvents: true
    property bool showTasks: true
    property bool showCompletedTasks: false
    property string statusMessage: ""

    readonly property string activeView: ["month", "week", "day"][viewIndex]
    readonly property int localeFirstDayOfWeek:
        Number(Qt.locale().firstDayOfWeek) % 7
    readonly property date weekStart: startOfWeek(selectedDate)
    readonly property var selectedItems: itemsForDate(selectedDate)

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    component SidebarToggle: AbstractButton {
        id: control

        property color markerColor: AppTheme.accent
        property bool nested: false

        checkable: true
        hoverEnabled: true
        implicitHeight: nested ? 28 : 32
        leftPadding: nested ? 26 : 10
        rightPadding: 8
        Accessible.role: Accessible.CheckBox

        contentItem: RowLayout {
            spacing: 9

            Rectangle {
                Layout.preferredWidth: 11
                Layout.preferredHeight: 11
                radius: width / 2
                color: control.checked ? control.markerColor : "transparent"
                border.width: control.checked ? 0 : 1
                border.color: AppTheme.withAlpha(control.markerColor, 0.72)

                Rectangle {
                    anchors.centerIn: parent
                    width: 3
                    height: 3
                    radius: width / 2
                    color: AppTheme.accentText
                    visible: control.checked
                }
            }

            Label {
                Layout.fillWidth: true
                text: control.text
                color: control.enabled ? AppTheme.text : AppTheme.mutedText
                font.pixelSize: control.nested ? 10 : 11
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 18
                radius: height / 2
                color: control.checked
                    ? AppTheme.withAlpha(control.markerColor,
                        AppTheme.dark ? 0.42 : 0.24)
                    : AppTheme.withAlpha(AppTheme.text,
                        AppTheme.dark ? 0.18 : 0.10)
                border.width: 1
                border.color: control.checked
                    ? AppTheme.withAlpha(control.markerColor, 0.48)
                    : AppTheme.border

                Rectangle {
                    y: 2
                    x: control.checked ? parent.width - width - 2 : 2
                    width: 14
                    height: 14
                    radius: 7
                    color: control.checked ? control.markerColor : AppTheme.mutedText

                    Behavior on x {
                        NumberAnimation {
                            duration: AppTheme.motionFast
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }

        background: Rectangle {
            radius: AppTheme.smallRadius
            color: control.down
                ? AppTheme.buttonPressed
                : (control.hovered ? AppTheme.cardHover : "transparent")
            border.width: control.activeFocus ? 1 : 0
            border.color: AppTheme.withAlpha(AppTheme.accent, 0.56)
        }
    }

    function activationOption(activationArgs, name) {
        const prefix = name + "="
        for (let index = 0; index < activationArgs.length; index++) {
            const argument = String(activationArgs[index])
            if (argument === name && index + 1 < activationArgs.length)
                return String(activationArgs[index + 1])
            if (argument.startsWith(prefix))
                return argument.slice(prefix.length)
        }
        return ""
    }

    function handleActivation(activationArgs, workingDirectory) {
        const requestedView = activationOption(activationArgs, "--view")
        const requestedViewIndex = ["month", "week", "day"].indexOf(requestedView)
        if (requestedViewIndex >= 0)
            viewIndex = requestedViewIndex

        const requested = activationOption(activationArgs, "--date")
        if (requested === "today") {
            showToday()
            return
        }
        if (!/^\d{4}-\d{2}-\d{2}$/.test(requested))
            return
        const parts = requested.split("-").map(Number)
        const date = new Date(parts[0], parts[1] - 1, parts[2], 12)
        if (Number.isNaN(date.getTime())
                || date.getFullYear() !== parts[0]
                || date.getMonth() !== parts[1] - 1
                || date.getDate() !== parts[2])
            return
        selectedDate = date
        visibleMonth = new Date(date.getFullYear(), date.getMonth(), 1)
        Qt.callLater(updateEventRange)
    }

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
        const offset = (date.getDay() - localeFirstDayOfWeek + 7) % 7
        return new Date(date.getFullYear(), date.getMonth(), date.getDate() - offset)
    }

    function monthDate(offset) {
        return new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + offset, 1)
    }

    function dateForMonthCell(index) {
        const first = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1)
        const offset = (first.getDay() - localeFirstDayOfWeek + 7) % 7
        return new Date(first.getFullYear(), first.getMonth(), index - offset + 1)
    }

    function weekdayName(column, format) {
        const jsDay = (localeFirstDayOfWeek + column) % 7
        const qtDay = jsDay === 0 ? 7 : jsDay
        return Qt.locale().dayName(qtDay, format)
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
        now = new Date()
        const today = new Date(now.getTime())
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

    KosSettingsDialog {
        id: settingsDialog
        settings: root.applicationSettings
        applicationName: qsTr("Calendar")
    }

    Shortcut { sequences: [StandardKey.New]; onActivated: eventEditor.openForDate(root.selectedDate) }
    Shortcut { sequence: "Ctrl+T"; onActivated: root.showToday() }
    Shortcut { sequence: "Ctrl+1"; onActivated: root.viewIndex = 0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: root.viewIndex = 1 }
    Shortcut { sequence: "Ctrl+3"; onActivated: root.viewIndex = 2 }
    Shortcut { sequences: [StandardKey.Find]; onActivated: searchField.forceActiveFocus() }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: sidebar

            Layout.fillHeight: true
            Layout.preferredWidth: root.compact
                ? AppTheme.compactSidebarWidth : AppTheme.sidebarWidth
            color: AppTheme.sidebarSurface
            border.width: 1
            border.color: AppTheme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Calendar")
                        color: AppTheme.text
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    KosToolButton {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        text: "+"
                        flat: true
                        enabled: pim.connected && pim.writable
                        Accessible.name: qsTr("New event")
                        onClicked: eventEditor.openForDate(root.selectedDate)
                    }
                }

                AbstractButton {
                    id: todayNavigation

                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    hoverEnabled: true
                    Accessible.name: qsTr("Go to today")
                    onClicked: root.showToday()

                    contentItem: RowLayout {
                        spacing: 9

                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 7
                            color: AppTheme.accent

                            Label {
                                anchors.centerIn: parent
                                text: String(root.now.getDate())
                                color: AppTheme.accentText
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Today")
                            color: AppTheme.text
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        Label {
                            text: Qt.formatDate(root.now, "ddd")
                            color: AppTheme.mutedText
                            font.pixelSize: 10
                        }
                    }

                    background: Rectangle {
                        radius: AppTheme.smallRadius
                        color: todayNavigation.down
                            ? AppTheme.buttonPressed
                            : (todayNavigation.hovered
                                ? AppTheme.cardHover : "transparent")
                        border.width: todayNavigation.activeFocus ? 1 : 0
                        border.color: AppTheme.withAlpha(AppTheme.accent, 0.56)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 3
                    Layout.bottomMargin: 3
                    color: AppTheme.border
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 2

                    KosToolButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        text: "‹"
                        flat: true
                        Accessible.name: qsTr("Previous month")
                        onClicked: root.visibleMonth = root.monthDate(-1)
                    }

                    Label {
                        Layout.fillWidth: true
                        text: Qt.formatDate(root.visibleMonth, "MMMM yyyy")
                        color: AppTheme.text
                        horizontalAlignment: Text.AlignHCenter
                        font.weight: Font.DemiBold
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    KosToolButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        text: "›"
                        flat: true
                        Accessible.name: qsTr("Next month")
                        onClicked: root.visibleMonth = root.monthDate(1)
                    }
                }

                Item {
                    id: miniCalendar

                    Layout.fillWidth: true
                    Layout.preferredHeight: 144
                    readonly property real cellWidth: width / 7
                    readonly property real headingHeight: 18
                    readonly property real cellHeight: 21

                    Repeater {
                        model: 7

                        delegate: Label {
                            required property int index
                            x: index * miniCalendar.cellWidth
                            y: 0
                            width: miniCalendar.cellWidth
                            height: miniCalendar.headingHeight
                            text: root.weekdayName(index, Locale.NarrowFormat)
                            color: AppTheme.mutedText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 9
                            font.weight: Font.Medium
                        }
                    }

                    Repeater {
                        model: 42

                        delegate: AbstractButton {
                            id: miniDay

                            required property int index
                            readonly property date cellDate: root.dateForMonthCell(index)
                            readonly property bool inVisibleMonth:
                                cellDate.getMonth() === root.visibleMonth.getMonth()
                            readonly property bool selected:
                                root.sameDay(cellDate, root.selectedDate)
                            readonly property bool today:
                                root.sameDay(cellDate, root.now)

                            x: (index % 7) * miniCalendar.cellWidth
                            y: miniCalendar.headingHeight
                                + Math.floor(index / 7) * miniCalendar.cellHeight
                            width: miniCalendar.cellWidth
                            height: miniCalendar.cellHeight
                            hoverEnabled: true
                            opacity: inVisibleMonth ? 1 : 0.42
                            Accessible.name: Qt.formatDate(cellDate, Locale.LongFormat)
                            onClicked: {
                                root.selectedDate = cellDate
                                if (cellDate.getMonth()
                                    !== root.visibleMonth.getMonth()) {
                                    root.visibleMonth = new Date(
                                        cellDate.getFullYear(),
                                        cellDate.getMonth(), 1)
                                }
                            }

                            contentItem: Rectangle {
                                width: 20
                                height: 20
                                anchors.centerIn: parent
                                radius: width / 2
                                color: miniDay.today
                                    ? AppTheme.accent
                                    : (miniDay.selected
                                        ? AppTheme.withAlpha(AppTheme.accent,
                                            AppTheme.dark ? 0.28 : 0.14)
                                        : (miniDay.hovered
                                            ? AppTheme.cardHover : "transparent"))
                                border.width: miniDay.selected && !miniDay.today ? 1 : 0
                                border.color: AppTheme.withAlpha(AppTheme.accent, 0.52)

                                Label {
                                    anchors.centerIn: parent
                                    text: String(miniDay.cellDate.getDate())
                                    color: miniDay.today
                                        ? AppTheme.accentText
                                        : (miniDay.selected
                                            ? AppTheme.accent : AppTheme.text)
                                    font.pixelSize: 9
                                    font.weight: miniDay.today || miniDay.selected
                                        ? Font.DemiBold : Font.Normal
                                }
                            }

                            background: null
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("CALENDARS")
                        color: AppTheme.mutedText
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }

                    Label {
                        text: "2"
                        color: AppTheme.mutedText
                        font.pixelSize: 9
                    }
                }

                SidebarToggle {
                    Layout.fillWidth: true
                    text: qsTr("Events")
                    markerColor: AppTheme.accent
                    checked: root.showEvents
                    onToggled: root.showEvents = checked
                }

                SidebarToggle {
                    Layout.fillWidth: true
                    text: qsTr("Scheduled tasks")
                    markerColor: AppTheme.positive
                    checked: root.showTasks
                    onToggled: root.showTasks = checked
                }

                SidebarToggle {
                    Layout.fillWidth: true
                    text: qsTr("Show completed")
                    markerColor: AppTheme.warning
                    nested: true
                    checked: root.showCompletedTasks
                    enabled: root.showTasks
                    opacity: enabled ? 1 : 0.48
                    onToggled: root.showCompletedTasks = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("TASK LISTS")
                        color: AppTheme.mutedText
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }

                    Label {
                        text: String(pim.lists.length)
                        color: AppTheme.mutedText
                        font.pixelSize: 9
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 72)
                    Layout.maximumHeight: 72
                    clip: true
                    model: pim.lists
                    spacing: 1

                    delegate: Rectangle {
                        id: listLegend

                        required property var modelData
                        width: ListView.view.width
                        height: 27
                        radius: AppTheme.smallRadius
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 9

                            Rectangle {
                                Layout.preferredWidth: 10
                                Layout.preferredHeight: 10
                                radius: width / 2
                                color: String(root.value(listLegend.modelData,
                                    "color", AppTheme.accent))
                            }

                            Label {
                                Layout.fillWidth: true
                                text: String(root.value(listLegend.modelData,
                                    "name", qsTr("List")))
                                color: AppTheme.text
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            Label {
                                text: qsTr("Tasks")
                                color: AppTheme.mutedText
                                font.pixelSize: 9
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: AppTheme.smallRadius
                    color: AppTheme.withAlpha(
                        pim.connected ? AppTheme.positive : AppTheme.warning,
                        AppTheme.dark ? 0.13 : 0.08)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 7

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            radius: width / 2
                            color: pim.connected ? AppTheme.positive : AppTheme.warning
                        }

                        Label {
                            Layout.fillWidth: true
                            text: pim.connected
                                ? qsTr("Calendar and Todo are synchronized")
                                : qsTr("Waiting for the local PIM service")
                            color: pim.connected ? AppTheme.positive : AppTheme.warning
                            elide: Text.ElideRight
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 18
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    KosToolButton {
                        Layout.preferredWidth: 36
                        text: "‹"
                        Accessible.name: qsTr("Previous period")
                        onClicked: root.shiftView(-1)
                    }
                    KosToolButton {
                        Layout.preferredWidth: 36
                        text: "›"
                        Accessible.name: qsTr("Next period")
                        onClicked: root.shiftView(1)
                    }
                    KosButton {
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

                    KosToolButton {
                        text: "⚙"
                        font.pixelSize: 16
                        Accessible.name: qsTr("Calendar settings")
                        ToolTip.visible: hovered
                        ToolTip.text: Accessible.name
                        onClicked: settingsDialog.open()
                    }

                    KosButton {
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
                    spacing: 8

                    LiquidTextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.minimumWidth: 120
                        Layout.maximumWidth: 340
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
                        selectionColor: AppTheme.dark
                            ? AppTheme.cardHover : AppTheme.windowRaised
                        textColor: AppTheme.text
                        mutedTextColor: AppTheme.mutedText
                        onSelectionRequested: index => root.viewIndex = index
                    }

                    KosButton {
                        Layout.preferredWidth: 96
                        text: qsTr("New event")
                        highlighted: true
                        enabled: pim.connected && pim.writable
                        onClicked: eventEditor.openForDate(root.selectedDate)
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
                        currentTime: root.now
                        firstDayOfWeek: root.localeFirstDayOfWeek
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
                                KosButton {
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
                                        AbstractButton {
                                            id: completionButton

                                            visible: root.itemTodoId(agendaItem.modelData).length > 0
                                            implicitWidth: 24
                                            implicitHeight: 24
                                            checkable: true
                                            checked: root.itemCompleted(agendaItem.modelData)
                                            Accessible.name: checked
                                                ? qsTr("Mark task open") : qsTr("Mark task complete")
                                            onClicked: root.toggleItem(agendaItem.modelData, checked)

                                            contentItem: Rectangle {
                                                anchors.centerIn: parent
                                                width: 17
                                                height: 17
                                                radius: width / 2
                                                color: completionButton.checked
                                                    ? root.itemColor(agendaItem.modelData)
                                                    : "transparent"
                                                border.width: 1
                                                border.color: root.itemColor(agendaItem.modelData)

                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 5
                                                    height: 5
                                                    radius: width / 2
                                                    color: AppTheme.accentText
                                                    visible: completionButton.checked
                                                }
                                            }

                                            background: Rectangle {
                                                radius: AppTheme.smallRadius
                                                color: completionButton.hovered
                                                    ? AppTheme.cardHover : "transparent"
                                            }
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
                    currentTime: root.now
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
                    currentTime: root.now
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

    Component.onCompleted: updateEventRange()
}
