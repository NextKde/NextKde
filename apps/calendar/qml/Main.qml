pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Kos.Pim
import Kos.Ui

KosApplicationWindow {
    id: root

    modernDesign: true
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

    // Apple 26 ("Tahoe") design tokens, verbatim from the shared Sketch
    // library's document.tokenExport dump — see
    // tmp/ui-replication/calendar-v2/LEDGER.md §5. Values are the measured /
    // exported hexes, not theme roles, so the chrome matches the reference
    // instead of drifting with AppTheme.
    readonly property QtObject tahoe: QtObject {
        // Sidebar and content are two flush planes, not floating cards.
        readonly property color sidebarPlane: "#E4E4E4"
        readonly property color contentPlane: "#FFFFFF"
        readonly property int sidebarWidth: 320

        // Glass. Two independent frames agree on one law, so this is measured,
        // not eyeballed: the body is 0.44 x backdrop + 129. Materials/Liquid
        // Glass - Over Light Backgrounds puts six pills on a grey ramp
        // (102,127,152,177,204,229) and reads back 185,186,212,223,219... and
        // the sidebar toolbar pill here on the #E4E4E4 plane reads 228 at its
        // dip — all on that line. It is a #E6E6E6 veil at 56%, which means the
        // glass *compresses* whatever is behind it instead of just adding
        // white. That is the part a flat opaque gradient cannot do: over the
        // white content plane it stays a light grey (241) rather than blowing
        // out, and over a dark backdrop it lifts hard.
        readonly property color glassVeil: Qt.rgba(0xE6 / 255, 0xE6 / 255,
                                                   0xE6 / 255, 0.56)
        // Outermost hairline. Measured 200-210 on a 228 plane, 142 on 177.
        readonly property color glassEdge: Qt.rgba(0, 0, 0, 0.08)
        // 1px specular line just inside it: 255 against a 229 body at both the
        // top and the bottom rim, so the glass catches light on both edges.
        readonly property color glassRim: Qt.rgba(1, 1, 1, 0.90)

        // Fills/Light 2 Secondary #787880 @16% over the sidebar plane
        // resolves to the #D2D2D2 the reference measures.
        readonly property color controlFill: Qt.rgba(0x78 / 255, 0x78 / 255,
                                                     0x80 / 255, 0.16)
        // Fills/Light 3 Tertiary #767680 @12% → the measured #D6D6D8.
        readonly property color selectionFill: Qt.rgba(0x76 / 255, 0x76 / 255,
                                                       0x80 / 255, 0.12)

        // Labels/Light 1 Primary, 2 Secondary (#3C3C43 @60% → #8A8A8A).
        readonly property color labelPrimary: "#000000"
        readonly property color labelSecondary: Qt.rgba(0x3C / 255, 0x3C / 255,
                                                        0x43 / 255, 0.6)
        // Separators/Light Non-Opaque (#000000 @12%).
        readonly property color separator: Qt.rgba(0, 0, 0, 0.12)

        // System Colors/Light 8 Blue, 4 Green, 3 Orange.
        readonly property color accent: "#0088FF"
        readonly property color positive: "#34C759"
        readonly property color warning: "#FF8D28"

        // Sidebar search field: Sidebar/Light/Search, 300x44 on a 320 plane,
        // fully rounded, filled with Fills/Light 2 over the plane.
        readonly property color searchFill: "#D2D2D2"
        readonly property int searchHeight: 44
        readonly property int searchInsetLeading: 10
        readonly property int searchInsetTrailing: 11

        // Rows (Items/Level 0 + States/Selected): 44 tall, selection inset 20
        // from the sidebar edge and 11 from the far side, a 20x20 marker box
        // 16 inside the selection, label 15 after the marker.
        readonly property int rowHeight: 44
        readonly property int rowInsetLeading: 20
        readonly property int rowInsetTrailing: 11
        readonly property int rowIconInset: 16
        readonly property int rowIconSize: 20
        readonly property int rowTextGap: 15
        readonly property int rowFontSize: 15
        readonly property int rowDetailInset: 12
        readonly property color rowHoverFill: Qt.rgba(0x74 / 255, 0x74 / 255,
                                                      0x80 / 255, 0.08)

        readonly property int controlHeight: 44
        readonly property int controlRowHeight: 54
        readonly property int pillHeight: 44
    }

    readonly property string activeView: ["month", "week", "day"][viewIndex]
    readonly property int localeFirstDayOfWeek:
        Number(Qt.locale().firstDayOfWeek) % 7
    readonly property date weekStart: startOfWeek(selectedDate)
    readonly property var selectedItems: itemsForDate(selectedDate)
    // One scan per invalidation (occurrencesChanged, searchQuery, filters);
    // every day/hour cell then just looks up its key instead of rescanning
    // pim.occurrences + pim.todoOccurrences.
    readonly property var itemsByDate: buildItemsByDate()

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // Sidebar row chrome, from Items/Level 0 + States/Selected: the selection
    // is a capsule inset 20 from the sidebar edge and 11 from the far side, the
    // marker box is 20x20, the label sits 15 after it, and any trailing detail
    // is right-aligned 12 inside the capsule.
    component SidebarRow: AbstractButton {
        id: row

        property string detail: ""
        property color markerColor: "transparent"
        property string markerGlyph: ""
        property bool markerFilled: false
        property bool selected: false
        property bool showSwitch: false
        property color switchColor: root.tahoe.accent
        // Child rows in Items/Level 1 sit one icon-width further in.
        property bool nested: false

        implicitHeight: root.tahoe.rowHeight
        hoverEnabled: true
        Accessible.name: row.text

        readonly property real nestInset: row.nested ? 24 : 0
        readonly property real markerLeft: root.tahoe.rowInsetLeading
                                           + root.tahoe.rowIconInset
                                           + row.nestInset
        readonly property real labelLeft: markerLeft + root.tahoe.rowIconSize
                                          + root.tahoe.rowTextGap

        background: Rectangle {
            x: root.tahoe.rowInsetLeading
            width: row.width - root.tahoe.rowInsetLeading
                   - root.tahoe.rowInsetTrailing
            height: row.height
            radius: height / 2
            color: row.selected ? root.tahoe.selectionFill
                : (row.hovered ? root.tahoe.rowHoverFill : "transparent")
        }

        contentItem: Item {
            Item {
                x: row.markerLeft
                anchors.verticalCenter: parent.verticalCenter
                width: root.tahoe.rowIconSize
                height: root.tahoe.rowIconSize

                Rectangle {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    radius: 6
                    color: row.markerFilled ? row.markerColor : "transparent"
                    border.width: row.markerColor.a > 0 && !row.markerFilled ? 2 : 0
                    border.color: row.markerColor
                }

                Label {
                    anchors.centerIn: parent
                    text: row.markerGlyph
                    color: row.markerColor
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: row.labelLeft
                width: Math.max(0, row.width - row.labelLeft
                                   - root.tahoe.rowInsetTrailing
                                   - root.tahoe.rowDetailInset
                                   - detailLabel.implicitWidth - 8)
                text: row.text
                color: row.enabled ? root.tahoe.labelPrimary
                                   : root.tahoe.labelSecondary
                font.pixelSize: root.tahoe.rowFontSize
                elide: Text.ElideRight
            }

            Label {
                id: detailLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: row.showSwitch ? switchTrack.left : parent.right
                anchors.rightMargin: row.showSwitch ? 10
                    : root.tahoe.rowInsetTrailing + root.tahoe.rowDetailInset
                text: row.detail
                color: root.tahoe.labelSecondary
                font.pixelSize: root.tahoe.rowFontSize
                horizontalAlignment: Text.AlignRight
            }

            // The kit's own switch spec was not in the frames pulled for this
            // task, so this is a proportional stand-in (LEDGER.md §4).
            Rectangle {
                id: switchTrack
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: root.tahoe.rowInsetTrailing
                                     + root.tahoe.rowDetailInset
                visible: row.showSwitch
                width: visible ? 42 : 0
                height: 26
                radius: height / 2
                color: row.checked
                    ? row.switchColor
                    : Qt.rgba(0x78 / 255, 0x78 / 255, 0x80 / 255, 0.32)
                opacity: row.enabled ? 1 : 0.48

                Rectangle {
                    y: 3
                    x: row.checked ? parent.width - width - 3 : 3
                    width: 20
                    height: 20
                    radius: 10
                    color: "#FFFFFF"

                    Behavior on x {
                        NumberAnimation {
                            duration: AppTheme.motionFast
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    // Sidebar/Light/Search: a #D2D2D2 capsule with a leading magnifier, the
    // placeholder at x 47 inside it, and a dictation glyph at the far end. Both
    // glyphs are hand-drawn (no icon font ships here — LEDGER.md §6).
    component SidebarSearch: Item {
        id: field

        property alias text: input.text
        property string placeholder: qsTr("Search")
        signal edited(string value)

        implicitHeight: root.tahoe.searchHeight

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: root.tahoe.searchInsetLeading
            anchors.rightMargin: root.tahoe.searchInsetTrailing
            radius: height / 2
            color: root.tahoe.searchFill

            TextInput {
                id: input
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 47
                anchors.right: parent.right
                anchors.rightMargin: 47
                clip: true
                color: root.tahoe.labelPrimary
                font.pixelSize: root.tahoe.rowFontSize
                selectionColor: root.tahoe.accent
                onTextEdited: field.edited(text)
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 47
                text: field.placeholder
                visible: input.text.length === 0
                color: root.tahoe.labelSecondary
                font.pixelSize: root.tahoe.rowFontSize
            }

            Item {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20

                Rectangle {
                    x: 2
                    y: 1.5
                    width: 12
                    height: 12
                    radius: 6
                    color: "transparent"
                    border.width: 1.6
                    border.color: root.tahoe.labelSecondary
                }

                Rectangle {
                    x: 12.4
                    y: 13.4
                    width: 7
                    height: 1.6
                    radius: 0.8
                    rotation: 45
                    color: root.tahoe.labelSecondary
                }
            }

            Item {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20

                Rectangle {
                    x: 3
                    y: 5
                    width: 14
                    height: 9
                    radius: 7
                    color: "transparent"
                    border.width: 1.6
                    border.color: root.tahoe.labelSecondary
                }

                Rectangle {
                    x: 2.4
                    y: 4.4
                    width: 15.2
                    height: 4
                    color: root.tahoe.searchFill
                }

                Rectangle {
                    x: 6.5
                    y: 1
                    width: 7
                    height: 12
                    radius: 3.5
                    color: root.tahoe.labelSecondary
                }

                Rectangle {
                    x: 9.2
                    y: 13
                    width: 1.6
                    height: 4
                    color: root.tahoe.labelSecondary
                }

                Rectangle {
                    x: 6.5
                    y: 16.4
                    width: 7
                    height: 1.6
                    radius: 0.8
                    color: root.tahoe.labelSecondary
                }
            }
        }
    }

    // The glass body, shared by every glass control. Three stacked pieces
    // because the reference has three: a dark hairline at the very edge, a 1px
    // white specular line inside it, and the veil between them carrying a
    // vertical profile that dips near the top and lifts toward the bottom. The
    // sidebar toolbar pill measures 238 / 228 / 234 / 250 top to bottom on a
    // 228 plane, with 255 at both rims — so the glass catches light on its top
    // *and* bottom edge, and the dark end of its gradient never goes below the
    // plane it sits on.
    component GlassSurface: Rectangle {
        id: glass

        radius: height / 2
        color: root.tahoe.glassVeil
        border.width: 1
        border.color: root.tahoe.glassEdge

        // The vertical profile, drawn inside the rim so the edges stay crisp.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, glass.radius - 1)
            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0.410) }
                GradientStop { position: 0.16; color: Qt.rgba(0, 0, 0, 0.008) }
                GradientStop { position: 0.40; color: Qt.rgba(1, 1, 1, 0.050) }
                GradientStop { position: 0.70; color: Qt.rgba(1, 1, 1, 0.150) }
                GradientStop { position: 0.88; color: Qt.rgba(1, 1, 1, 0.550) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 1.000) }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, glass.radius - 1)
            color: "transparent"
            border.width: 1
            border.color: root.tahoe.glassRim
        }
    }

    // Circular glass button from Sidebar/Light/Toolbar. Measures ⌀40 on the
    // sidebar plane with a faint lighter-than-plane fill and a hairline edge.
    component GlassButton: AbstractButton {
        id: control

        property string symbol: ""
        property string hint: ""

        implicitWidth: root.tahoe.controlHeight
        implicitHeight: root.tahoe.controlHeight
        hoverEnabled: true
        Accessible.name: hint
        ToolTip.visible: hovered && hint.length > 0
        ToolTip.text: hint

        contentItem: Label {
            text: control.symbol
            color: root.tahoe.labelPrimary
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: GlassSurface {
            opacity: control.enabled ? 1 : 0.5
        }
    }

    // Labeled glass pill from the same toolbar spec: as tall as the circular
    // buttons beside it (44), fully rounded, horizontal padding 16.
    component GlassPill: AbstractButton {
        id: control

        implicitWidth: Math.max(65, contentItem.implicitWidth + 32)
        implicitHeight: root.tahoe.pillHeight
        hoverEnabled: true

        contentItem: Label {
            text: control.text
            color: root.tahoe.labelPrimary
            font.pixelSize: root.tahoe.rowFontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: GlassSurface {
            opacity: control.enabled ? 1 : 0.5
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
        return AppTheme.formatDate(date, "yyyy-MM-dd")
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

    function addDayRange(bucket, startKey, endKey, item) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(startKey))
            return
        const start = new Date(startKey + "T00:00:00")
        const end = /^\d{4}-\d{2}-\d{2}$/.test(endKey)
            ? new Date(endKey + "T00:00:00") : start
        for (let day = start; day <= end;
                day = new Date(day.getFullYear(), day.getMonth(),
                               day.getDate() + 1)) {
            const key = dateKey(day)
            if (bucket[key] === undefined)
                bucket[key] = []
            bucket[key].push(item)
        }
    }

    function buildItemsByDate() {
        const result = ({})
        const representedTodos = new Map()
        const events = pim.occurrences ?? []
        const todos = pim.todoOccurrences ?? []

        if (showEvents) {
            for (let index = 0; index < events.length; index++) {
                const event = events[index]
                if (!matchesSearch(event))
                    continue
                const item = { kind: "event", record: event }
                const start = String(value(event, "start", "")).slice(0, 10)
                const end = String(value(event, "end", "")).slice(0, 10)
                // Keep the old per-day semantics: a multi-day event lands on
                // its start day and every strictly-covered day, not the end.
                addDayRange(result, start,
                    end > start ? previousDateKey(end) : start, item)
                const todoId = String(value(event, "linkedTodoId", ""))
                if (todoId.length > 0) {
                    let todoDays = representedTodos.get(todoId)
                    if (todoDays === undefined)
                        representedTodos.set(todoId,
                            todoDays = Object.create(null))
                    addDayRange(todoDays, start,
                        end > start ? previousDateKey(end) : start, item)
                }
            }
        }

        if (showTasks) {
            for (let index = 0; index < todos.length; index++) {
                const todo = todos[index]
                if (!matchesSearch(todo))
                    continue
                const due = String(value(todo, "due", "")).slice(0, 10)
                const id = String(value(todo, "seriesId",
                                        value(todo, "id", "")))
                const days = representedTodos.get(id)
                if (days !== undefined && days[due] !== undefined)
                    continue
                if (!showCompletedTasks
                        && Boolean(value(todo, "completed", false)))
                    continue
                addDayRange(result, due, due,
                            { kind: "todo", record: todo })
            }
        }

        for (const key in result) {
            result[key].sort(function(left, right) {
                const leftAllDay = itemAllDay(left)
                const rightAllDay = itemAllDay(right)
                if (leftAllDay !== rightAllDay)
                    return leftAllDay ? -1 : 1
                return itemDateTime(left).localeCompare(itemDateTime(right))
            })
        }
        return result
    }

    function previousDateKey(key) {
        const date = new Date(key + "T00:00:00")
        return dateKey(new Date(date.getFullYear(), date.getMonth(),
                                date.getDate() - 1))
    }

    function itemsForDate(date) {
        return itemsByDate[dateKey(date)] ?? []
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
            return AppTheme.formatDate(visibleMonth, "MMMM yyyy")
        if (activeView === "day")
            return AppTheme.formatDate(selectedDate, Locale.LongFormat)
        const end = new Date(weekStart.getFullYear(), weekStart.getMonth(),
                             weekStart.getDate() + 6)
        if (weekStart.getMonth() === end.getMonth())
            return AppTheme.formatDate(weekStart, "MMM d") + " – "
                + AppTheme.formatDate(end, "d, yyyy")
        return AppTheme.formatDate(weekStart, "MMM d") + " – "
            + AppTheme.formatDate(end, "MMM d, yyyy")
    }

    // The reference pairs the header title with a count line ("67 Messages,
    // 12 Unread"); this is the calendar's equivalent. selectedItems is already
    // bound, so reading it here costs nothing.
    function headerSubtitle() {
        const count = root.selectedItems.length
        return count === 1 ? qsTr("1 item") : qsTr("%1 items").arg(count)
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

    // Window framework: two flush planes. The sidebar runs the full height of
    // the window at its left edge — macOS keeps the window controls over it —
    // and everything right of it is plain paper. Backgrounds from the shared
    // library (LEDGER.md §5).
    Item {
        anchors.fill: parent

        Rectangle {
            id: sidebarPlane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: sidebar.width
            color: root.tahoe.sidebarPlane
        }

        Rectangle {
            anchors.left: sidebarPlane.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: root.tahoe.contentPlane
        }

        // Same collapse contract KosSidebar uses: the body keeps its expanded
        // geometry while the viewport closes, so filters, scroll position and
        // focus survive. Flush and square instead of a floating card.
        Item {
            id: sidebar
            objectName: "applicationSidebar"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.sidebarExpanded ? root.tahoe.sidebarWidth : 0
            clip: true
            enabled: root.sidebarExpanded

            Behavior on width {
                NumberAnimation {
                    duration: AppTheme.motionNormal
                    easing.type: Easing.InOutCubic
                }
            }

            ColumnLayout {
                width: root.tahoe.sidebarWidth
                height: sidebar.height
                spacing: 0

                // Sidebar control row, from Sidebar/Light/Toolbar/Floating
                // Window: window controls, one labeled glass pill for the
                // primary action, then circular glass buttons at the right.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.tahoe.controlRowHeight

                    KosWindowControls {
                        id: windowControls
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        targetWindow: root
                    }

                    GlassPill {
                        id: newEventButton
                        anchors.left: windowControls.right
                        anchors.leftMargin: 12
                        // Both sides anchored: the pill is left-anchored in the
                        // spec, but "New Event" is longer than the spec's "Edit",
                        // so pinning the right edge is what keeps it off the
                        // circular buttons instead of overlapping them.
                        anchors.right: toolButtons.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("New Event")
                        enabled: pim.connected && pim.writable
                        Accessible.name: text
                        onClicked: eventEditor.openForDate(root.selectedDate)
                    }

                    Row {
                        id: toolButtons
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        GlassButton {
                            symbol: "◇"
                            hint: qsTr("Go to today")
                            onClicked: root.showToday()
                        }

                        GlassButton {
                            symbol: "▤"
                            hint: qsTr("Toggle sidebar")
                            checked: root.sidebarExpanded
                            onClicked: root.sidebarExpanded = !root.sidebarExpanded
                        }
                    }
                }

                // macOS puts the window's search field in the sidebar, directly
                // under the control row (Sidebar/Light/Search: 300x44, r22).
                SidebarSearch {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.tahoe.searchHeight
                    Layout.topMargin: 7
                    placeholder: qsTr("Search")
                    text: root.searchQuery
                    onEdited: root.searchQuery = value
                    Accessible.name: qsTr("Search events and tasks")
                }

                SidebarRow {
                    id: todayNavigation

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.tahoe.rowHeight
                    text: qsTr("Today")
                    detail: AppTheme.formatDate(root.now, "ddd")
                    markerColor: root.tahoe.accent
                    markerFilled: true
                    onClicked: root.showToday()
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
                        text: AppTheme.formatDate(root.visibleMonth, "MMMM yyyy")
                        color: root.tahoe.labelPrimary
                        horizontalAlignment: Text.AlignHCenter
                        font.weight: Font.DemiBold
                        font.pixelSize: root.tahoe.rowFontSize
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
                            color: root.tahoe.labelSecondary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 10
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
                            Accessible.name: AppTheme.formatDate(cellDate, Locale.LongFormat)
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
                                    ? root.tahoe.accent
                                    : (miniDay.selected
                                        ? root.tahoe.selectionFill
                                        : (miniDay.hovered
                                            ? root.tahoe.rowHoverFill : "transparent"))
                                border.width: miniDay.selected && !miniDay.today ? 1 : 0
                                border.color: root.tahoe.accent

                                Label {
                                    anchors.centerIn: parent
                                    text: String(miniDay.cellDate.getDate())
                                    color: miniDay.today
                                        ? "#FFFFFF"
                                        : (miniDay.selected
                                            ? root.tahoe.accent
                                            : root.tahoe.labelPrimary)
                                    font.pixelSize: 11
                                    font.weight: miniDay.today || miniDay.selected
                                        ? Font.DemiBold : Font.Normal
                                }
                            }

                            background: null
                        }
                    }
                }

                // Section header per Sidebar/Light/Header: sentence case, the
                // secondary label colour, text 4 clear of the row capsule.
                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.tahoe.rowInsetLeading + 4
                    Layout.topMargin: 18
                    Layout.bottomMargin: 4
                    Layout.preferredHeight: 20
                    text: qsTr("Calendars")
                    color: root.tahoe.labelSecondary
                    font.pixelSize: root.tahoe.rowFontSize
                    verticalAlignment: Text.AlignVCenter
                }

                SidebarRow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.tahoe.rowHeight
                    text: qsTr("Events")
                    checkable: true
                    showSwitch: true
                    markerFilled: true
                    markerColor: root.tahoe.accent
                    switchColor: root.tahoe.accent
                    Accessible.role: Accessible.CheckBox
                    checked: root.showEvents
                    onToggled: root.showEvents = checked
                }

                SidebarRow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.tahoe.rowHeight
                    text: qsTr("Scheduled tasks")
                    checkable: true
                    showSwitch: true
                    markerFilled: true
                    markerColor: root.tahoe.positive
                    switchColor: root.tahoe.positive
                    Accessible.role: Accessible.CheckBox
                    checked: root.showTasks
                    onToggled: root.showTasks = checked
                }

                SidebarRow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.tahoe.rowHeight
                    text: qsTr("Show completed")
                    checkable: true
                    showSwitch: true
                    nested: true
                    markerColor: root.tahoe.warning
                    switchColor: root.tahoe.warning
                    checked: root.showCompletedTasks
                    enabled: root.showTasks
                    opacity: enabled ? 1 : 0.48
                    Accessible.role: Accessible.CheckBox
                    onToggled: root.showCompletedTasks = checked
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.tahoe.rowInsetLeading + 4
                    Layout.topMargin: 18
                    Layout.bottomMargin: 4
                    Layout.preferredHeight: 20
                    text: qsTr("Task lists")
                    color: root.tahoe.labelSecondary
                    font.pixelSize: root.tahoe.rowFontSize
                    verticalAlignment: Text.AlignVCenter
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight,
                                                     root.tahoe.rowHeight * 2)
                    Layout.maximumHeight: root.tahoe.rowHeight * 2
                    clip: true
                    model: pim.lists

                    delegate: SidebarRow {
                        id: listLegend

                        required property var modelData

                        width: ListView.view.width
                        text: String(root.value(listLegend.modelData, "name",
                                                qsTr("List")))
                        detail: qsTr("Tasks")
                        markerFilled: true
                        markerColor: String(root.value(listLegend.modelData,
                            "color", root.tahoe.accent))
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    id: statusPill

                    readonly property color statusColor: pim.connected
                        ? root.tahoe.positive : root.tahoe.warning

                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Layout.leftMargin: 10
                    Layout.rightMargin: root.tahoe.rowInsetTrailing
                    Layout.bottomMargin: 6
                    radius: height / 2
                    color: Qt.rgba(statusPill.statusColor.r, statusPill.statusColor.g,
                                   statusPill.statusColor.b, 0.14)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: width / 2
                            color: statusPill.statusColor
                        }

                        Label {
                            Layout.fillWidth: true
                            text: pim.connected
                                ? qsTr("Calendar and Todo are synchronized")
                                : qsTr("Waiting for the local PIM service")
                            color: root.tahoe.labelSecondary
                            wrapMode: Text.WordWrap
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }

        // Content plane: a 52-tall header band on paper, then the view. The
        // reference keeps the title block at the left of that band and its
        // controls at the right (LEDGER.md §5).
        ColumnLayout {
            anchors.left: sidebarPlane.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.tahoe.controlRowHeight

                RowLayout {
                    id: headerLeading
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    GlassButton {
                        Layout.alignment: Qt.AlignVCenter
                        symbol: "‹"
                        hint: qsTr("Previous period")
                        onClicked: root.shiftView(-1)
                    }
                    GlassButton {
                        Layout.alignment: Qt.AlignVCenter
                        symbol: "›"
                        hint: qsTr("Next period")
                        onClicked: root.shiftView(1)
                    }
                    GlassPill {
                        Layout.alignment: Qt.AlignVCenter
                        text: qsTr("Today")
                        onClicked: root.showToday()
                    }

                    Column {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 10
                        Layout.minimumWidth: root.compact ? 100 : 180
                        spacing: 1

                        Label {
                            text: root.headerTitle()
                            color: root.tahoe.labelPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Label {
                            text: root.headerSubtitle()
                            color: root.tahoe.labelSecondary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }

                RowLayout {
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    BusyIndicator {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        running: pim.busy
                        visible: running
                    }

                    LiquidSegmentedControl {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 196
                        Layout.preferredHeight: 32
                        labels: [qsTr("Month"), qsTr("Week"), qsTr("Day")]
                        currentIndex: root.viewIndex
                        backgroundColor: root.tahoe.controlFill
                        selectionColor: root.tahoe.contentPlane
                        textColor: root.tahoe.labelPrimary
                        mutedTextColor: root.tahoe.labelSecondary
                        onSelectionRequested: index => root.viewIndex = index
                    }

                    GlassButton {
                        id: actionsButton
                        Layout.alignment: Qt.AlignVCenter
                        symbol: "⋯"
                        hint: qsTr("Calendar actions")
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

                    GlassButton {
                        symbol: "⚙"
                        hint: qsTr("Calendar settings")
                        onClicked: settingsDialog.open()
                    }

                    GlassButton {
                        symbol: "▤"
                        hint: qsTr("Toggle sidebar")
                        checked: root.sidebarExpanded
                        onClicked: root.sidebarExpanded = !root.sidebarExpanded
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.fillHeight: false

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.tahoe.separator
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

            KosPageCache {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.viewIndex
                // Keep the active view and one recent view warm. Retaining all
                // three would only defer StackLayout's original memory cost.
                cacheLimit: 2
                pages: [monthPage, weekPage, dayPage]

                Component {
                    id: monthPage
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
                            Layout.preferredHeight: root.height < 680 ? 145 : 170

                            contentItem: ColumnLayout {
                                spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: AppTheme.formatDate(root.selectedDate, Locale.LongFormat)
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

                                delegate: KosItemDelegate {
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
                }

                Component {
                    id: weekPage
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
                }

                Component {
                    id: dayPage
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
    }

    Component.onCompleted: updateEventRange()
}
