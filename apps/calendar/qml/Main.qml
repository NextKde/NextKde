pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import Kos.Pim
import Kos.Ui

KosApplicationWindow {
    id: root
    neutralTypography: true
    readonly property alias calendarScene: windowChrome

    modernDesign: true
    visible: true
    // The bare attached ToolTip renders the installed Basic style verbatim,
    // whose panel is `palette.toolTipBase` + `palette.toolTipText` (R134). The
    // app sets no palette, so on the dark leg that leaks a pure-white panel
    // with near-black ink onto a (30,30,30) window. Theme the two tooltip
    // slots per leg on the window palette: dark panel #3C3C3C (the tahoe
    // elevated lift over #1E1E1E) with #F2F2F2 ink; light panel #F2F2F2 (one
    // step below the white plane) with black ink. Radius stays Basic's 0
    // (square) — the reference has no tooltip at all (R063), so the choice is
    // ours and is recorded here for both legs.
    palette.toolTipBase: root.tahoeDark ? "#3C3C3C" : "#F2F2F2"
    palette.toolTipText: root.design.labelPrimary
    title: qsTr("Calendar")
    width: 1100
    height: 720
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

    readonly property bool tahoeDark: AppTheme.dark
    readonly property CalendarStyle design: CalendarStyle {}

    readonly property string activeView:
        ["month", "week", "day", "year"][viewIndex]
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

    // Compact ordinary navigation rows; geometry is shared with the category list.
    component SidebarRow: AbstractButton {
        id: row

        property string detail: ""
        property color markerColor: "transparent"
        property string markerGlyph: ""
        property bool markerFilled: false
        property bool selected: false
        property bool showSwitch: false
        property color switchColor: root.design.accent
        // Child rows in Items/Level 1 sit one icon-width further in.
        property bool nested: false

        implicitHeight: root.design.rowHeight
        hoverEnabled: true
        Accessible.role: row.showSwitch ? Accessible.Switch : Accessible.ListItem
        Accessible.name: row.text
        Accessible.checked: row.checked

        readonly property real nestInset: row.nested ? 24 : 0
        readonly property real markerLeft: root.design.rowInsetLeading
                                           + root.design.rowIconInset
                                           + row.nestInset
        readonly property real labelLeft: markerLeft + root.design.rowIconSize
                                          + root.design.rowTextGap

        background: Rectangle {
            x: root.design.rowInsetLeading
            width: row.width - root.design.rowInsetLeading
                   - root.design.rowInsetTrailing
            y: 2
            height: row.height - 4
            radius: 6
            color: row.selected ? root.design.selectionFill
                : (row.hovered ? root.design.rowHoverFill : "transparent")
        }

        contentItem: Item {
            Item {
                x: row.markerLeft
                anchors.verticalCenter: parent.verticalCenter
                width: root.design.rowIconSize
                height: root.design.rowIconSize

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
                                   - root.design.rowInsetTrailing
                                   - root.design.rowDetailInset
                                   - detailLabel.implicitWidth - 8)
                text: row.text
                color: row.enabled ? root.design.labelPrimary
                                   : root.design.labelSecondary
                font.pixelSize: root.design.rowFontSize
                elide: Text.ElideRight
            }

            Label {
                id: detailLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: row.showSwitch ? switchTrack.left : parent.right
                anchors.rightMargin: row.showSwitch ? 10
                    : root.design.rowInsetTrailing + root.design.rowDetailInset
                text: row.detail
                color: root.design.labelSecondary
                font.pixelSize: root.design.rowFontSize
                horizontalAlignment: Text.AlignRight
            }

            // The kit's own switch spec was not in the frames pulled for this
            // task, so this is a proportional stand-in (LEDGER.md §4).
            Rectangle {
                id: switchTrack
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: root.design.rowInsetTrailing
                                     + root.design.rowDetailInset
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

    // S03: compact category row for the 220px sidebar. In checkbox mode the
    // 12px rounded box is the only state carrier: filled with the category
    // colour and a white check when checked, a hollow 1px coloured border
    // when not. Legend mode (checkboxless) draws a plain filled swatch. No
    // colour dot, no switch. 30 tall, inset 12, label 8 after the box at
    // 13px, single-line elide with the tail reserved before the label.
    component CategoryRow: AbstractButton {
        id: row

        property color boxColor: root.design.accent
        property string detail: ""
        property bool nested: false
        // Pure colour-swatch mode for the task-list legend: solid fill, no
        // check, no checked/unchecked reading.
        property bool swatchOnly: false

        implicitHeight: root.design.categoryRowHeight
        hoverEnabled: true
        Accessible.role: row.swatchOnly ? Accessible.ListItem
                                        : Accessible.CheckBox
        Accessible.name: row.text
        Accessible.checked: row.checked

        readonly property real boxLeft: root.design.categoryInset
            + (row.nested ? 24 : 0)

        background: Rectangle {
            x: 6
            width: row.width - 12
            height: row.height
            radius: 6
            color: row.hovered ? root.design.rowHoverFill : "transparent"
        }

        contentItem: Item {
            Rectangle {
                id: box
                x: row.boxLeft
                anchors.verticalCenter: parent.verticalCenter
                width: root.design.categoryBoxSize
                height: root.design.categoryBoxSize
                radius: root.design.categoryBoxRadius
                color: row.swatchOnly || row.checked
                    ? row.boxColor : "transparent"
                border.width: !row.swatchOnly && !row.checked ? 1 : 0
                border.color: row.boxColor
                opacity: row.enabled ? 1 : 0.48

                // White check drawn as two rounded bars in a V: the short
                // stroke falls from upper-left down to the vertex at the
                // lower left, the long stroke rises from the vertex to the
                // upper right. Inside an 8x8 guide in the 12px box.
                Item {
                    anchors.centerIn: parent
                    width: 8; height: 8
                    visible: row.checked && !row.swatchOnly
                    opacity: row.enabled ? 1 : 0.9

                    // Short stroke: upper-left (1.5,4.2) falling to the
                    // shared vertex (2.9,5.6) in the 8x8 guide.
                    Rectangle {
                        width: 2; height: 1.98; radius: 1
                        color: "#FFFFFF"
                        rotation: -45
                        x: 1.2; y: 3.91
                    }
                    // Long stroke: shared vertex (2.9,5.6) rising to
                    // upper-right (6.3,2.2).
                    Rectangle {
                        width: 2; height: 4.81; radius: 1
                        color: "#FFFFFF"
                        rotation: 45
                        x: 3.6; y: 1.495
                    }
                }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: row.boxLeft + root.design.categoryBoxSize
                   + root.design.categoryTextGap
                width: Math.max(0, parent.width - x
                                   - (detailLabel.visible
                                      ? detailLabel.implicitWidth + 8 : 0)
                                   - root.design.categoryInset)
                text: row.text
                color: row.enabled ? root.design.labelPrimary
                                   : root.design.labelSecondary
                font.pixelSize: root.design.categoryFontSize
                elide: Text.ElideRight
            }

            Label {
                id: detailLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: root.design.categoryInset
                visible: row.detail.length > 0
                text: row.detail
                color: root.design.labelSecondary
                font.pixelSize: root.design.categoryFontSize
                horizontalAlignment: Text.AlignRight
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

        implicitHeight: root.design.searchHeight

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: root.design.searchInsetLeading
            anchors.rightMargin: root.design.searchInsetTrailing
            radius: height / 2
            color: root.design.searchFill

            TextInput {
                id: input
                Accessible.name: field.placeholder
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 47
                anchors.right: parent.right
                anchors.rightMargin: 47
                clip: true
                color: root.design.labelPrimary
                font.pixelSize: root.design.rowFontSize
                selectionColor: root.design.accent
                onTextEdited: field.edited(text)
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 47
                text: field.placeholder
                visible: input.text.length === 0
                color: root.design.labelSecondary
                font.pixelSize: root.design.rowFontSize
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
                    border.color: root.design.labelSecondary
                }

                Rectangle {
                    x: 12.4
                    y: 13.4
                    width: 7
                    height: 1.6
                    radius: 0.8
                    rotation: 45
                    color: root.design.labelSecondary
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
                    border.color: root.design.labelSecondary
                }

                Rectangle {
                    x: 2.4
                    y: 4.4
                    width: 15.2
                    height: 4
                    color: root.design.searchFill
                }

                Rectangle {
                    x: 6.5
                    y: 1
                    width: 7
                    height: 12
                    radius: 3.5
                    color: root.design.labelSecondary
                }

                Rectangle {
                    x: 9.2
                    y: 13
                    width: 1.6
                    height: 4
                    color: root.design.labelSecondary
                }

                Rectangle {
                    x: 6.5
                    y: 16.4
                    width: 7
                    height: 1.6
                    radius: 0.8
                    color: root.design.labelSecondary
                }
            }
        }
    }

    // One shared in-window underlay; no per-button shadows or displaced
    // copies of schedule content. The Demo optics supply the liquid rim.
    component GlassSurface: CalendarGlassSurface {
        backdrop: chromeBackdrop
    }

    // Compact 26px liquid toolbar action with a 16px vector icon.
    component ToolbarButton: AbstractButton {
        id: control

        property string iconName: ""
        property string hint: ""

        implicitWidth: root.design.toolbarButtonSize
        implicitHeight: root.design.toolbarButtonSize
        hoverEnabled: true
        // Clicks on toolbar buttons must not steal focus from the inline
        // search input: a press that moved focus would fire the input's blur
        // handler before onClicked, and toggle() would then reopen what the
        // blur just closed. Tab keeps keyboard accessibility.
        focusPolicy: Qt.TabFocus
        Accessible.name: hint
        ToolTip.visible: hovered && hint.length > 0
        ToolTip.text: hint

        // Control stretches contentItem to the button box, so the icon is a
        // fixed-size child centred inside a plain filler Item.
        contentItem: Item {
            CalendarToolbarIcon {
                anchors.centerIn: parent
                name: control.iconName
                size: root.design.toolbarIconSize
                color: control.enabled ? root.design.liquidLabel : root.design.labelSecondary
            }
        }

        background: GlassSurface {
            opacity: control.enabled ? 1 : 0.5
            hovered: control.hovered
            pressed: control.pressed
            focused: control.activeFocus && control.enabled
        }
    }

    // Calendar-local copy of the three toolbar glyph paths from the shared
    // VectorIcon (panel/plus/search). Same data-SVG technique and 2px round
    // stroke styling; kept inside this file because the shared Kos.Ui module
    // list does not export VectorIcon to applications.
    component CalendarToolbarIcon: Item {
        id: icon

        property string name: "check"
        property color color: "white"
        property real size: 16
        implicitWidth: size
        implicitHeight: size
        readonly property var paths: ({
            panel: "M3 5h18v14H3zM3 9h18M7 9v10",
            plus: "M12 4v16M4 12h16",
            search: "M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14M15 15l6 6"
        })
        Image {
            anchors.fill: parent
            sourceSize: Qt.size(icon.size * 2, icon.size * 2)
            source: "data:image/svg+xml;utf8," + encodeURIComponent(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="rgb('
                + Math.round(icon.color.r * 255) + ',' + Math.round(icon.color.g * 255) + ','
                + Math.round(icon.color.b * 255) + ')" stroke-opacity="' + icon.color.a
                + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="'
                + (icon.paths[icon.name] || icon.paths.search) + '"/></svg>')
        }
    }

    // L07: subdued date-navigation button for the heading band — 26 high,
    // 13px text, low-contrast neutral edge/fill (macOS light-grey nav look,
    // dark variant equally quiet). No lens, no thick glass. Arrows are a
    // local chevron vector, not a glyph font.
    component DateNavButton: AbstractButton {
        id: control

        // "" → chevron arrow (rotation from arrowRotation), otherwise text.
        property string text_: ""
        property real arrowRotation: 0
        property string hint: ""

        implicitHeight: root.design.dateNavHeight
        implicitWidth: text_.length > 0
            ? textLabel.implicitWidth + 20 : root.design.dateNavHeight
        hoverEnabled: true
        Accessible.name: hint
        ToolTip.visible: hovered && hint.length > 0
        ToolTip.text: hint

        background: Rectangle {
            radius: 6
            color: control.pressed
                ? root.design.selectionFill
                : (control.hovered ? root.design.rowHoverFill : root.design.controlFill)
            border.width: control.activeFocus ? 2 : 0
            border.color: root.design.accent
            opacity: control.enabled ? 1 : 0.5
        }

        contentItem: Item {
            Label {
                id: textLabel
                anchors.centerIn: parent
                visible: control.text_.length > 0
                text: control.text_
                color: root.design.labelPrimary
                font.pixelSize: root.design.dateNavTextSize
            }
            Item {
                anchors.centerIn: parent
                width: 14; height: 14
                visible: control.text_.length === 0
                // The two bars meet at a bottom point (caret ^); rotating the
                // holder +90° points it left (‹), -90° points it right (›)
                // — verified against the actual screenshot evidence.
                rotation: control.arrowRotation

                // Local chevron: two short bars meeting at a point, same
                // technique as the checkbox check.
                Rectangle {
                    width: 2; height: 5.4; radius: 1
                    color: root.design.labelSecondary
                    rotation: -45
                    x: 3.0; y: 2.4
                }
                Rectangle {
                    width: 2; height: 5.4; radius: 1
                    color: root.design.labelSecondary
                    rotation: 45
                    x: 7.2; y: 2.4
                }
            }
        }
    }

    // The reference's month arrows are 5x9 px of ink at 1:1 (x22..27 /
    // y350..358, ~1 px stroke). Its mini month's column pitch is 24.25 where
    // ours is 28.0 (x1.155), so the scaled target is 5.8x10.4 and the 1:1
    // target is 5x9; the shape below lands between them by construction, so
    // the scale choice is not load-bearing at this size. Drawn as a local
    // vector for the same reason DateNavButton is: the "‹" glyph this
    // replaced rendered only 4x5 of ink at 13px.
    component MiniMonthChevron: Item {
        id: chevron

        // Ink envelope, not a box: two bars at 45 meeting at a point on the
        // left. The two bars' ink spans x0.18..5.62 / y0.24..10.18 inside
        // this item, so these two numbers put the item's centre AT the ink's
        // centre (2.90, 5.21) — that is what makes the 180° rotation below
        // exactly mirror rather than shift.
        implicitWidth: 5.8
        implicitHeight: 10.42

        Rectangle {
            width: 1.4
            height: 6.3
            radius: 0.6
            color: root.design.labelSecondary
            rotation: 45
            x: 2.2
            y: -0.19
        }

        Rectangle {
            width: 1.4
            height: 6.3
            radius: 0.6
            color: root.design.labelSecondary
            rotation: -45
            x: 2.2
            y: 4.31
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
        // P2-9: "year" was silently dropped even though viewIndex 3 exists;
        // the fourth view now has a CLI activation path to match Ctrl+4.
        const requestedViewIndex = ["month", "week", "day", "year"].indexOf(requestedView)
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
                const byDateTime =
                    itemDateTime(left).localeCompare(itemDateTime(right))
                if (byDateTime !== 0)
                    return byDateTime
                // R083: two items can share an identical start (the fixture's
                // Thu all-day pair does), and upstream order is then whatever
                // the model happened to emit. Tiebreak on the UID so the
                // rendered order is stable run to run.
                const byId =
                    itemStableId(left).localeCompare(itemStableId(right))
                return byId !== 0 ? byId : itemTitle(left).localeCompare(
                                        itemTitle(right))
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

    // E02 (R-CHIP user ruling 2026-10-17): the timed chip's second line is
    // the time range ("11AM – 1PM" on the ref). Todos render their due time
    // only; no end is invented when the record lacks one. R246/P1-1: the
    // format follows the locale — 12-hour locales keep the compact style
    // (minutes only when nonzero; the start meridiem dropped when both ends
    // share the same period, "12 – 2PM") with meridiem text from the locale;
    // 24-hour locales render plain "HH:MM – HH:MM" with no meridiem.
    function itemSecondary(item) {
        if (itemAllDay(item))
            return ""
        const startMatch = itemDateTime(item).match(/T(\d{2}:\d{2})/)
        if (!startMatch)
            return ""
        const endText = String(value(itemRecord(item), "end", ""))
        const endMatch = endText.match(/T(\d{2}:\d{2})/)
        const startClock = AppTheme.formatClock(startMatch[1])
        if (!endMatch)
            return startClock
        const endClock = AppTheme.formatClock(endMatch[1])
        if (AppTheme.localeUses24hClock())
            return startClock + " – " + endClock
        const startSuffix = AppTheme.meridiemText(parseInt(startMatch[1], 10))
        const endSuffix = AppTheme.meridiemText(parseInt(endMatch[1], 10))
        if (startSuffix === endSuffix)
            return startClock.slice(0, startClock.length - startSuffix.length) + " – " + endClock
        return startClock + " – " + endClock
    }

    function itemDateTime(item) {
        const record = itemRecord(item)
        return String(value(record, item.kind === "todo" ? "due" : "start", ""))
    }

    // R083: the record's stable identity — the UID, which the store exposes as
    // `seriesId`. Only for ORDERING ties; never for display.
    function itemStableId(item) {
        const record = itemRecord(item)
        return String(value(record, "seriesId", value(record, "id", "")))
    }

    // P1-2: locale-aware via AppTheme.formatClock — 24h locales keep "HH:MM",
    // 12h locales get the compact form ("11AM" / "1:30PM").
    function itemTime(item) {
        if (itemAllDay(item))
            return qsTr("All day")
        const match = itemDateTime(item).match(/T(\d{2}:\d{2})/)
        return match ? AppTheme.formatClock(match[1]) : "--:--"
    }

    // P01: full date/time line for the detail popover. Events get a
    // locale-formatted date plus the start–end range (the stored end is
    // exclusive, so the displayed end for a same-day timed event is the
    // literal stored end; multi-day/all-day ranges show a date range).
    // Tasks show their due date/time. No end is invented when absent.
    function itemDetailsRange(item) {
        const record = itemRecord(item)
        const startText = String(value(record, item.kind === "todo" ? "due" : "start", ""))
        const start = new Date(startText)
        if (Number.isNaN(start.getTime()))
            return itemTime(item)
        const dateLine = AppTheme.formatDate(start, Locale.LongFormat)
        if (item.kind === "todo")
            return dateLine + " · " + itemTime(item)
        if (itemAllDay(item)) {
            const endText = String(value(record, "end", ""))
            const end = new Date(endText)
            // Stored end is exclusive: the last covered day is end − 1.
            if (!Number.isNaN(end.getTime()) && endText.length >= 10
                    && sameDay(start, end)) {
                return dateLine + " · " + qsTr("All day")
            }
            if (!Number.isNaN(end.getTime()) && endText.length >= 10) {
                const lastDay = new Date(end.getFullYear(), end.getMonth(),
                                         end.getDate() - 1)
                return dateLine + " – " + AppTheme.formatDate(lastDay, Locale.LongFormat)
                    + " · " + qsTr("All day")
            }
            return dateLine + " · " + qsTr("All day")
        }
        const endText = String(value(record, "end", ""))
        const end = new Date(endText)
        if (Number.isNaN(end.getTime()) || endText.length < 16)
            return dateLine + " · " + itemTime(item)
        if (sameDay(start, end)) {
            // P1-2: same locale-aware clock formatting as itemTime.
            const endMatch = endText.match(/T(\d{2}:\d{2})/)
            const endClock = endMatch ? AppTheme.formatClock(endMatch[1])
                                      : itemTime(item)
            return dateLine + " · " + itemTime(item) + " – " + endClock
        }
        return dateLine + " – " + AppTheme.formatDate(end, Locale.LongFormat)
            + " · " + itemTime(item)
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

    // P2-9: Qt.darker(color, 1.0) is an identity transform — dropped. The
    // accent fallback also gave every unknown list the accent color, so
    // unknown ids now land in a small stable palette, hashed from the id.
    readonly property var listPalette: ["#0A84FF", "#34C759", "#FF9F0A",
        "#BF5AF2", "#FF375F", "#64D2FF"]

    function listColor(id) {
        for (let index = 0; index < pim.lists.length; index++) {
            const list = pim.lists[index]
            if (String(value(list, "id", "")) === String(id))
                return String(value(list, "color", AppTheme.accent))
        }
        let hash = 0
        const key = String(id)
        for (let index = 0; index < key.length; index++)
            hash = (hash * 31 + key.charCodeAt(index)) & 0x7fffffff
        return root.listPalette[hash % root.listPalette.length]
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
        // P01: single/double click on an existing item first opens the
        // compact detail popover; the editors are reached through its Edit
        // action. Double-click on empty grid time still opens the editor
        // directly (create flow untouched).
        itemDetails.showItem(item)
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
        } else if (activeView === "year") {
            first = new Date(selectedDate.getFullYear(), 0, 1)
            last = new Date(selectedDate.getFullYear(), 11, 31)
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
        if (activeView === "year") {
            selectedDate = new Date(selectedDate.getFullYear() + offset,
                                    selectedDate.getMonth(), selectedDate.getDate())
            visibleMonth = new Date(selectedDate.getFullYear(), 0, 1)
            Qt.callLater(updateEventRange)
            return
        }
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
        if (activeView === "year")
            return String(visibleMonth.getFullYear())
        if (activeView === "month")
            return AppTheme.formatDate(visibleMonth, "MMMM yyyy")
        if (activeView === "day")
            return AppTheme.formatDate(selectedDate, Locale.LongFormat)
        const end = new Date(weekStart.getFullYear(), weekStart.getMonth(),
                             weekStart.getDate() + 6)
        // Week range follows locale word order via I18n templates (P2-5/I5).
        return AppTheme.formatWeekRange(weekStart, end)
    }

    // The reference pairs the header title with a count line ("67 Messages,
    // 12 Unread"); this is the calendar's equivalent. selectedItems is already
    // bound, so reading it here costs nothing.
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

    // P01: compact neutral detail popover. Opens on item activation, clamps
    // into the content viewport, and hands the record to the existing
    // editors only through its Edit action. One connection, made once; the
    // pending record is swapped per open.
    property var pendingDetailsRecord: null
    property bool pendingDetailsIsTodo: false

    EventDetailsPopover {
        id: itemDetails
        parent: root.contentItem
        z: 50
        onEditRequested: {
            if (root.pendingDetailsIsTodo)
                taskEditor.openForTodo(root.pendingDetailsRecord)
            else
                eventEditor.openForEvent(root.pendingDetailsRecord)
        }

        function showItem(item) {
            const record = root.itemRecord(item)
            root.pendingDetailsRecord = record
            root.pendingDetailsIsTodo = item.kind === "todo"
            // root-qualified: the popover's own string properties would
            // otherwise shadow the window helper functions here.
            itemTitle = root.itemTitle(item)
            kindColor = root.itemColor(item)
            kindCompleted = root.itemCompleted(item)
            itemTime = root.itemDetailsRange(item)
            itemLocation = String(root.value(record, "location", ""))
            itemNotes = String(root.value(record, "description", ""))
            openAt(null)
        }
    }

    EventEditorDialog {
        id: eventEditor
        objectName: "calendarEventEditor"
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
        objectName: "taskEditorDialog"
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
    // P2-9: the Year segment had no keyboard path (REVIEW P2, clue 8).
    Shortcut { sequence: "Ctrl+4"; onActivated: root.viewIndex = 3 }
    Shortcut { sequences: [StandardKey.Find]; onActivated: toolbarSearch.toggle() }

    // Window framework: two flush planes. The sidebar runs the full height of
    // the window at its left edge — macOS keeps the window controls over it —
    // and everything right of it is plain paper. Backgrounds from the shared
    // library (LEDGER.md §5). Both planes reach the very top of the window so
    // the 30px dot band is the planes' own top strip, not a separate
    // titlebar; the corner clipping follows the shared windowCornerRadius
    // rule (square when maximized/fullscreen).
    Item {
        id: windowChrome
        anchors.fill: parent

        // Clip the planes to the window's rounded corners (top-left/right);
        // the corner radius itself comes from KosApplicationWindow.
        Rectangle {
            id: chromeMask
            anchors.fill: parent
            radius: root.windowCornerRadius
            visible: false
            layer.enabled: true
        }
        layer.enabled: root.windowCornerRadius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: chromeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // 窗口顶部 30px 安全区承载窗口圆点,侧栏面与内容面从它下面开始,
        // 工具栏内容与三圆点完整分开。
        readonly property int topSafeInset: 30

        // 自绘窗口圆点:几何照抄 apps/settings/main.qml(14px 圆点、间距 14、
        // 右缘距窗口右 14.5、上缘距窗口顶 10.5),锚定窗口边缘,不嵌在带
        // margin 的工具栏里。
        Row {
            anchors {
                right: parent.right
                rightMargin: 14.5
                top: parent.top
                topMargin: 10.5
            }
            spacing: 14
            z: 10
            Repeater {
                model: [
                    { color: "#28c840", act: "max" },
                    { color: "#febc2e", act: "min" },
                    { color: "#ff5f57", act: "close" }
                ]
                delegate: Rectangle {
                    id: windowDot
                    required property var modelData
                    width: 14; height: 14; radius: 7
                    color: modelData.color
                    // P1-A6b: 键盘聚焦时给最小可见反馈（常态外观 0.85 不变）。
                    opacity: activeFocus ? 1.0 : 0.85
                    border.width: activeFocus ? 1 : 0
                    border.color: AppTheme.text
                    activeFocusOnTab: true
                    function activate() {
                        if (modelData.act === "min")
                            root.showMinimized()
                        else if (modelData.act === "max")
                            root.visibility === Window.Maximized
                                ? root.showNormal() : root.showMaximized()
                        else
                            root.close()
                    }
                    Keys.onReturnPressed: windowDot.activate()
                    Keys.onEnterPressed: windowDot.activate()
                    Keys.onSpacePressed: windowDot.activate()
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.act === "min" ? qsTr("Minimize")
                        : modelData.act === "max" ? qsTr("Zoom") : qsTr("Close")
                    MouseArea {
                        // P1-A6b: 命中区放大到 22×22 居中（中心距 28 不重叠），
                        // 视觉圆点仍是 14×14。
                        anchors.centerIn: parent
                        width: 22; height: 22
                        cursorShape: Qt.PointingHandCursor
                        onClicked: windowDot.activate()
                    }
                }
            }
        }

        Item {
            id: chromePlanes
            anchors.fill: parent
            Rectangle {
                id: windowPlane
                anchors.fill: parent
                color: root.design.contentPlane
            }
            Item {
                id: sidebarPlane
                objectName: "calendarSidebarBackground"
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: sidebar.width
                readonly property bool sampling: root.visible && width > 0
                    && !AppTheme.reduceTransparency && GraphicsInfo.api !== GraphicsInfo.Software
                opacity: sampling ? 0.95 : 1
                layer.enabled: sampling
                clip: true
                ShaderEffectSource {
                    id: sidebarSource
                    anchors.fill: parent
                    sourceItem: sidebarPlane.sampling ? windowPlane : null
                    sourceRect: Qt.rect(0, 0, sidebarPlane.width, sidebarPlane.height)
                    visible: false
                    live: sidebarPlane.sampling
                }
                MultiEffect {
                    anchors.fill: parent
                    source: sidebarSource
                    visible: sidebarPlane.sampling
                    blurEnabled: true
                    blur: 0.35
                    blurMax: 32
                    autoPaddingEnabled: false
                }
                Rectangle {
                    anchors.fill: parent
                    color: root.design.sidebarPlane
                    opacity: sidebarPlane.sampling ? 0.95 : 1
                }
            }

            Rectangle {
                anchors.left: sidebarPlane.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: root.design.contentPlane

                // L01: the sidebar and main canvas are one continuous plane pair
                // joined by a single hairline at their seam.
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: root.design.separator
                }
            }
        }
        LiquidBackdrop {
            id: chromeBackdrop
            sourceItem: chromePlanes
            registerAsDefault: false
            active: !AppTheme.reduceTransparency
            resolutionScale: 0.5
        }

        // L02: the unified toolbar. One 40px row directly under the 30px dot
        // band, floating above both planes (the planes still cover the whole
        // window from y=0). Left: sidebar toggle, add. Right: search toggle,
        // more. The segmented control is centred over the *current main
        // region* (L03): sidebar expanded → x sidebarWidth..width, collapsed
        // → x 0..width, with a binding-animated x so it follows the collapse.
        Item {
            id: toolbar
            objectName: "calendarToolbar"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: parent.topSafeInset
            height: root.design.toolbarHeight
            z: 5

            // Dynamic main-region centre: sidebar width animates, so the
            // centre binding tracks it continuously.
            readonly property real mainLeft: sidebar.width
            readonly property real mainWidth: width - mainLeft

            ToolbarButton {
                id: sidebarToggleButton
                objectName: "toolbarSidebarToggle"
                anchors.left: parent.left
                anchors.leftMargin: root.design.toolbarInsetLeft
                anchors.verticalCenter: parent.verticalCenter
                iconName: "panel"
                hint: root.sidebarExpanded ? qsTr("Hide sidebar")
                                           : qsTr("Show sidebar")

                onClicked: root.sidebarExpanded = !root.sidebarExpanded
            }

            ToolbarButton {
                id: addButton
                objectName: "toolbarAdd"
                anchors.left: sidebarToggleButton.right
                anchors.leftMargin: root.design.toolbarGap
                anchors.verticalCenter: parent.verticalCenter
                iconName: "plus"
                hint: qsTr("Add event")
                enabled: pim.connected && pim.writable

                onClicked: eventEditor.openForDate(root.selectedDate)
            }

            CalendarViewSelector {
                id: viewSegment
                objectName: "toolbarViewSegment"
                anchors.verticalCenter: parent.verticalCenter
                x: toolbar.mainLeft
                   + Math.max(0, (toolbar.mainWidth - width) / 2)
                width: root.design.segmentWidth
                height: root.design.segmentHeight
                // L05: strict mutual exclusion with the search field. The
                // segment is hidden the moment the search opens and only
                // reappears once the field has fully collapsed (width == 0) —
                // sequential transition, no cross-fade, so no frame ever
                // shows both text areas.
                opacity: toolbarSearch.active || toolbarSearch.width > 0 ? 0 : 1
                visible: opacity > 0
                // R100/C05+L03: the reference's segment reads Day · Week ·
                // Month · Year — granularity ascending, left to right — and
                // L03 words it "Day/week/month segment". Ours was the exact
                // reverse. `viewIndex` keeps its own published contract
                // (0=month / 1=week / 2=day / 3=year: `activeView` :255,
                // Ctrl+1..4, `--view` :1054, the page cache :2495
                // and the review harness), so the segment mirrors it instead
                // of redefining it: segment i = viewIndex (2 - i) for i <= 2,
                // and the 4th segment (i == 3) maps to the year view. Weeks
                // still land on segment 1, so the pill's measured geometry
                // (R097/R098) is untouched.
                backdrop: chromeBackdrop
                labels: [qsTr("Day"), qsTr("Week"), qsTr("Month"), qsTr("Year")]
                currentIndex: root.viewIndex <= 2 ? 2 - root.viewIndex : 3
                backgroundColor: root.design.segmentTrack
                selectionColor: root.design.segmentPill
                textColor: root.design.labelPrimary
                // R099/C05: the reference has NO muted label state here — all
                // four segment labels carry the same pure-black ink (peak 0,
                // top-5% mean 15–23) and the pill alone marks the selection.
                // `labelSecondary` (≈147 at 1:1) was 130 levels too light.
                mutedTextColor: root.design.labelPrimary
                onSelectionRequested: index =>
                    root.viewIndex = index <= 2 ? 2 - index : 3
            }

            ToolbarButton {
                id: searchToggleButton
                objectName: "toolbarSearchToggle"
                anchors.right: moreButton.left
                anchors.rightMargin: root.design.toolbarGap
                anchors.verticalCenter: parent.verticalCenter
                iconName: "search"
                hint: qsTr("Search")

                onClicked: toolbarSearch.toggle()
            }

            // L05: inline search, strictly inside the 40px toolbar. Opening
            // hides the segment (fade above) and grows the field leftward
            // from the search button; no second row, no overlap with the dots
            // band or the left button group. Idempotent open/close; Escape
            // closes and clears from anywhere in the window. z above the
            // segment so the width transition cross-fades cleanly instead of
            // compositing into it.
            Item {
                id: toolbarSearch
                objectName: "toolbarSearch"
                z: 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: searchToggleButton.left
                anchors.rightMargin: 6
                readonly property int maxWidth: Math.min(280, Math.max(0,
                    toolbar.mainWidth - 2 * root.design.toolbarButtonSize
                        - 3 * root.design.toolbarGap - 24))
                width: active ? maxWidth : 0
                height: root.design.toolbarButtonSize
                visible: width > 0
                property bool active: false
                // Deferred close for clicks elsewhere in the window: the blur
                // arrives during the press, but the click target may itself
                // want the field (the search toggle). Waiting one event-loop
                // turn lets the press target act first, and the deferred close
                // then no-ops if toggle() already handled it.
                property bool blurPending: false
                // True between open() and the field actually being visible
                // (width animation finished). The delayed focus below is
                // armed only in this window; a close() cancels it. Any blur
                // during "opening" is the field's own geometry settling —
                // the input must not close itself because forceActiveFocus
                // ran while width was still 0.
                property bool opening: false
                function open() {
                    blurPending = false
                    if (active) return
                    active = true
                    opening = true
                    // Focus once the field is actually on screen: while the
                    // width animates from 0 the item is not laid out yet, and
                    // an immediate forceActiveFocus lands on a zero-size item
                    // whose subsequent blur re-triggers the close path.
                    focusTimer.restart()
                }
                function close() {
                    blurPending = false
                    opening = false
                    focusTimer.stop()
                    if (!active) return
                    active = false
                    input.text = ""
                    root.searchQuery = ""
                    input.focus = false
                }
                function toggle() { active ? close() : open() }
                // Any blur-driven close clears the query: closing the search
                // must never leave a hidden filter running.
                function requestBlurClose() {
                    if (blurPending || opening) return
                    blurPending = true
                    Qt.callLater(function() {
                        if (!blurPending || !toolbarSearch.active) return
                        close()
                    })
                }

                // Focus after the width animation settles (motionFast ~150ms
                // plus one frame). If the search was closed before this fires
                // the timer is stopped and nothing happens.
                Timer {
                    id: focusTimer
                    interval: AppTheme.motionFast + 50
                    onTriggered: {
                        if (!toolbarSearch.active) return
                        toolbarSearch.opening = false
                        input.forceActiveFocus()
                    }
                }

                Behavior on width { NumberAnimation {
                    duration: AppTheme.motionFast; easing.type: Easing.OutCubic } }

                // The field is clipped by its own width, so the text/input
                // never leaks outside during the width animation.
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.design.searchFill
                    border.width: input.activeFocus ? 1 : 0
                    border.color: root.design.accent
                    clip: true

                    TextInput {
                        id: input
                        objectName: "toolbarSearchInput"
                        Accessible.name: qsTr("Search")
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: root.design.labelPrimary
                        font.pixelSize: root.design.controlFontSize
                        selectionColor: root.design.accent
                        text: root.searchQuery
                        onTextEdited: root.searchQuery = text
                        onActiveFocusChanged: {
                            // Blur from clicking elsewhere: defer one event-
                            // loop turn so the click target (e.g. the search
                            // toggle) acts first and the deferred close
                            // no-ops. Blurs while the field is still opening
                            // (geometry settling before the delayed focus)
                            // are ignored; blur caused by close() itself runs
                            // after active went false and is also ignored.
                            if (!activeFocus && toolbarSearch.active
                                    && !toolbarSearch.opening
                                    && !toolbarSearch.blurPending)
                                toolbarSearch.requestBlurClose()
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        visible: input.text.length === 0
                        text: qsTr("Search")
                        color: root.design.labelSecondary
                        font.pixelSize: root.design.controlFontSize
                    }
                }
            }

            // More: three small solid dots, no glyph font involved.
            AbstractButton {
                id: moreButton
                objectName: "toolbarMore"
                anchors.right: parent.right
                anchors.rightMargin: root.design.toolbarInsetRight
                anchors.verticalCenter: parent.verticalCenter
                width: root.design.toolbarButtonSize
                height: root.design.toolbarButtonSize
                hoverEnabled: true
                Accessible.name: qsTr("Calendar actions")
                ToolTip.visible: hovered
                ToolTip.text: Accessible.name
                onClicked: actionsMenu.popup(this, 0, height + 2)

                contentItem: Item {
                    // Three small solid dots in a fixed-size centred Row, so
                    // Control stretching the contentItem cannot shove the
                    // dots into a corner.
                    Row {
                        anchors.centerIn: parent
                        spacing: 3
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                required property int index
                                width: 3.5; height: 3.5; radius: 1.75
                                color: root.design.labelPrimary
                            }
                        }
                    }
                }

                background: GlassSurface {
                    opacity: moreButton.enabled ? 1 : 0.5

                    hovered: moreButton.hovered
                    pressed: moreButton.pressed
                }
            }

            // L05: Escape always reaches the open search, whichever item in
            // this window holds focus — the input's own key handler is not
            // enough once it has lost focus. Scoped to the toolbar, enabled
            // only while the search is open.
            Shortcut {
                sequence: "Escape"
                enabled: toolbarSearch.active
                onActivated: toolbarSearch.close()
            }

            Menu {
                id: actionsMenu
                objectName: "calendarActionsMenu"
                popupType: Popup.Item
                y: moreButton.height
                padding: 4
                implicitWidth: 210
                background: CalendarPopupSurface { scene: windowChrome }
                delegate: MenuItem {
                    id: menuAction
                    implicitHeight: 24
                    font.pixelSize: 13
                    contentItem: Label {
                        text: menuAction.text
                        color: !menuAction.enabled ? root.design.labelSecondary
                            : menuAction.highlighted ? "white" : root.design.labelPrimary
                        font: menuAction.font
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle { radius: 4; color: menuAction.highlighted ? root.design.accent : "transparent" }
                }
                MenuItem {
                    implicitHeight: 24
                    font.pixelSize: 13
                    text: qsTr("New task…")
                    enabled: pim.connected && pim.writable
                    onTriggered: taskEditor.openForTodo(null)
                }
                MenuSeparator {}
                MenuItem {
                    implicitHeight: 24
                    font.pixelSize: 13
                    text: qsTr("Import iCalendar…")
                    enabled: pim.connected && pim.writable
                    onTriggered: importDialog.open()
                }
                MenuItem {
                    implicitHeight: 24
                    font.pixelSize: 13
                    text: qsTr("Export iCalendar…")
                    enabled: pim.connected && pim.ready
                    onTriggered: exportDialog.open()
                }
                MenuSeparator {}
                MenuItem {
                    implicitHeight: 24
                    font.pixelSize: 13
                    text: qsTr("Calendar settings")
                    onTriggered: settingsDialog.open()
                }
            }
        }

        // Same collapse contract KosSidebar uses: the body keeps its expanded
        // geometry while the viewport closes, so filters, scroll position and
        // focus survive. Flush and square instead of a floating card.
        Item {
            id: sidebar
            objectName: "applicationSidebar"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: parent.topSafeInset + root.design.toolbarHeight
            anchors.bottom: parent.bottom
            width: root.sidebarExpanded ? root.design.sidebarWidth : 0
            // Clip only while collapsing/expanding so the animated width never
            // spills onto the content plane; fully expanded the clip is off,
            // so the top glass pill's shadow can reach into the safe area.
            clip: !root.sidebarExpanded || width < root.design.sidebarWidth
            enabled: root.sidebarExpanded

            Behavior on width {
                NumberAnimation {
                    duration: AppTheme.motionNormal
                    easing.type: Easing.InOutCubic
                }
            }

            ColumnLayout {
                width: root.design.sidebarWidth
                height: sidebar.height
                spacing: 0

                // L04: the sidebar no longer carries its own toolbar row or a
                // standing search field — those live in the unified toolbar.
                // The body starts with the Today row.

                SidebarRow {
                    id: todayNavigation

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.design.rowHeight
                    text: qsTr("Today")
                    detail: AppTheme.formatDate(root.now, "ddd")
                    markerColor: root.design.accent
                    markerFilled: true
                    onClicked: root.showToday()
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 3
                    Layout.bottomMargin: 3
                    color: root.design.separator
                }

                // S02/S03: categories and task lists directly under the
                // Today row; the mini calendar anchors the sidebar bottom
                // (M01). The mid section is one real scrolling viewport
                // (Flickable over a naturally-sized Column): fillHeight with
                // minimumHeight 0, so in a short window it is this area that
                // scrolls — every group heading, category row and task list
                // stays reachable — while the fixed mini-calendar block
                // below can never be pushed off-window.
                Flickable {
                    id: categoriesViewport
                    objectName: "calendarCategoriesViewport"

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    clip: true
                    contentWidth: width
                    contentHeight: categoriesColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: categoriesColumn
                        width: categoriesViewport.width
                        spacing: 0

                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: root.design.categoryInset
                            Layout.topMargin: root.design.categoryHeadingTop
                            Layout.bottomMargin: root.design.categoryHeadingBottom
                            Layout.preferredHeight: 16
                            text: qsTr("Calendars")
                            color: root.design.labelSecondary
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }

                        CategoryRow {
                            Layout.fillWidth: true
                            text: qsTr("Events")
                            checkable: true
                            boxColor: root.design.accent
                            checked: root.showEvents
                            onToggled: root.showEvents = checked
                        }

                        CategoryRow {
                            Layout.fillWidth: true
                            text: qsTr("Scheduled tasks")
                            checkable: true
                            boxColor: root.design.positive
                            checked: root.showTasks
                            onToggled: root.showTasks = checked
                        }

                        CategoryRow {
                            Layout.fillWidth: true
                            text: qsTr("Show completed")
                            checkable: true
                            nested: true
                            boxColor: root.design.warning
                            checked: root.showCompletedTasks
                            enabled: root.showTasks
                            Accessible.name: qsTr("Show completed tasks")
                            onToggled: root.showCompletedTasks = checked
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: root.design.categoryInset
                            Layout.topMargin: root.design.categoryHeadingTop
                            Layout.bottomMargin: root.design.categoryHeadingBottom
                            Layout.preferredHeight: 16
                            text: qsTr("Task lists")
                            color: root.design.labelSecondary
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }

                        Repeater {
                            model: pim.lists

                            delegate: CategoryRow {
                                id: listLegend

                                required property var modelData

                                Layout.fillWidth: true
                                swatchOnly: true
                                text: String(root.value(listLegend.modelData,
                                                        "name", qsTr("List")))
                                boxColor: String(root.value(listLegend.modelData,
                                    "color", root.design.accent))
                            }
                        }
                    }
                }

                // M01: the mini calendar is a fixed, never-compressed block
                // (26 heading + 18 weekday + 6*21 rows = 170) pinned to the
                // sidebar bottom with a 12px bottom margin. min/preferred/max
                // all pin the same height, so no layout state can shrink or
                // stretch it.
                Item {
                    id: miniCalendar

                    readonly property real fixedHeight:
                        headingRow.height + 18 + 6 * cellHeight

                    Layout.fillWidth: true
                    Layout.leftMargin: root.design.categoryInset
                    Layout.rightMargin: root.design.categoryInset
                    Layout.bottomMargin: 12
                    Layout.minimumHeight: fixedHeight
                    Layout.preferredHeight: fixedHeight
                    Layout.maximumHeight: fixedHeight
                    readonly property real cellWidth: width / 7
                    readonly property real cellHeight: 21

                    // M02: month title centred between two equal 28x28
                    // arrows; title and grid share the same inset area.
                    RowLayout {
                        id: headingRow
                        objectName: "miniCalendarHeading"
                        width: parent.width
                        height: 26
                        spacing: 2

                        KosToolButton {
                            id: prevMonthButton
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            text: ""
                            flat: true
                            Accessible.name: qsTr("Previous month")
                            onClicked: root.visibleMonth = root.monthDate(-1)

                            MiniMonthChevron {
                                anchors.centerIn: parent
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: AppTheme.formatDate(root.visibleMonth, "MMMM yyyy")
                            color: root.design.labelPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.weight: Font.DemiBold
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        KosToolButton {
                            id: nextMonthButton
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            text: ""
                            flat: true
                            Accessible.name: qsTr("Next month")
                            onClicked: root.visibleMonth = root.monthDate(1)

                            MiniMonthChevron {
                                anchors.centerIn: parent
                                rotation: 180
                            }
                        }
                    }

                    // Weekday row: 10px secondary, seven equal columns.
                    Repeater {
                        model: 7

                        delegate: Label {
                            required property int index
                            x: index * miniCalendar.cellWidth
                            y: headingRow.height
                            width: miniCalendar.cellWidth
                            height: 18
                            text: root.weekdayName(index, Locale.NarrowFormat)
                            color: root.design.labelSecondary
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
                            y: headingRow.height + 18
                                + Math.floor(index / 7) * miniCalendar.cellHeight
                            width: miniCalendar.cellWidth
                            height: miniCalendar.cellHeight
                            hoverEnabled: true
                            opacity: inVisibleMonth ? 1 : 0.5
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

                            // M03: Control stretches contentItem to the cell,
                            // which warped a direct circle of this size into an
                            // ellipse. So the contentItem is a plain filler
                            // Item and the fixed circle sits centred inside it.
                            // (R094: 20 -> 15, the ref's own disc. R117: ->
                            // tahoe.miniDisc = 18, M04's literal.)
                            contentItem: Item {
                                Rectangle {
                                    width: root.design.miniDisc
                                    height: root.design.miniDisc
                                    radius: width / 2
                                    anchors.centerIn: parent
                                    // P2-9: white 11px DemiBold on todayRed
                                    // #E5484D measured 3.91:1 and on
                                    // selectionDisc #8E8E93 3.26:1 (WCAG,
                                    // python3; small text needs 4.5). The
                                    // shared tokens stay untouched — today
                                    // markers and the year view depend on
                                    // them — so the mini month applies the
                                    // minimal Qt.darker factor that clears
                                    // 4.5: white-on-#D24247 = 4.56, white-
                                    // on-#76767A = 4.52. Slightly deeper
                                    // discs than the ref; deviation noted
                                    // in state.md.
                                    color: miniDay.today
                                        ? Qt.darker(AppTheme.todayRed, 1.09)
                                        : (miniDay.selected
                                            ? Qt.darker(root.design.selectionDisc, 1.20)
                                            : (miniDay.hovered
                                                ? root.design.rowHoverFill : "transparent"))

                                    Label {
                                        anchors.centerIn: parent
                                        text: String(miniDay.cellDate.getDate())
                                        color: miniDay.today || miniDay.selected
                                            ? "#FFFFFF"
                                            : root.design.labelPrimary
                                        font.pixelSize: 11
                                        font.weight: miniDay.today || miniDay.selected
                                            ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }

                            background: null
                        }
                    }
                }

                // S05: no standing status card. A small, low-key one-liner
                // only while the PIM service is unreachable — no placeholder
                // when healthy.
                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.design.categoryInset
                    Layout.rightMargin: root.design.categoryInset
                    Layout.bottomMargin: 6
                    visible: !pim.connected
                    text: qsTr("Waiting for the local PIM service")
                    color: root.design.labelSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        // Content plane: the unified toolbar sits above; below it a title row
        // (date heading + prev/Today/next, L06/L07 review later) and then the
        // view.
        ColumnLayout {
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: parent.topSafeInset + root.design.toolbarHeight
            anchors.bottom: parent.bottom
            spacing: 0

            // L06: 48px date heading band. Single 27px localised title on the
            // left (20 inset, strictly limited to the space before the
            // navigation group — long week/day titles elide, never squeeze
            // the nav); L07 subdued nav group on the right. No subtitle line.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.design.dateBandHeight

                Label {
                    id: dateTitle
                    objectName: "dateTitle"
                    anchors.left: parent.left
                    anchors.leftMargin: root.design.dateBandInset
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, dateNavGroup.x
                                       - root.design.dateBandInset - 16)
                    text: root.headerTitle()
                    color: root.design.labelPrimary
                    font.pixelSize: root.design.dateTitleSize
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                }

                BusyIndicator {
                    anchors.right: dateNavGroup.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    running: pim.busy
                    visible: running
                }

                RowLayout {
                    id: dateNavGroup
                    objectName: "dateNavGroup"
                    anchors.right: parent.right
                    anchors.rightMargin: root.design.dateBandInset
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    DateNavButton {
                        objectName: "dateNavPrevious"
                        hint: qsTr("Previous period")
                        arrowRotation: 90
                        onClicked: root.shiftView(-1)
                    }
                    DateNavButton {
                        objectName: "dateNavToday"
                        hint: qsTr("Show today")
                        text_: qsTr("Today")
                        onClicked: root.showToday()
                    }
                    DateNavButton {
                        objectName: "dateNavNext"
                        hint: qsTr("Next period")
                        arrowRotation: -90
                        onClicked: root.shiftView(1)
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
                    color: root.design.separator
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.statusMessage.length > 0 || (pim.errorMessage.length > 0 && pim.ready)

                // A5: the row clears itself after 3.5s, which a screen reader
                // can neither announce on appearance nor re-read afterwards.
                // The Alert role asks the platform to speak it, and hovering
                // the row pauses the timer so the text stays put while read.
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered)
                            statusTimer.stop()
                        else
                            statusTimer.restart()
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: pim.errorMessage.length > 0 ? pim.errorMessage : root.statusMessage
                    color: pim.errorMessage.length > 0
                        ? root.design.statusWarning : root.design.statusPositive
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.Alert
                    Accessible.name: text
                }
            }

            KosPageCache {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.viewIndex
                // Keep the active view and one recent view warm. Retaining all
                // four would only defer StackLayout's original memory cost.
                cacheLimit: 2
                pages: [monthPage, weekPage, dayPage, yearPage]

                Component {
                    id: monthPage
                    ColumnLayout {
                        spacing: 0

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

                        Pane {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.selectedItems.length === 0 ? 76
                                : Math.min(root.height < 680 ? 116 : 148,
                                    44 + root.selectedItems.length * 40)
                            padding: 12
                            topPadding: 8
                            background: Rectangle {
                                color: root.design.sidebarPlane
                                Rectangle { width: parent.width; height: 1; color: root.design.separator }
                            }

                            contentItem: ColumnLayout {
                                spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: AppTheme.formatDate(root.selectedDate, Locale.LongFormat)
                                    color: root.design.labelPrimary
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    font.weight: Font.DemiBold
                                }
                                Label {
                                    text: qsTr("%n item(s)", "", root.selectedItems.length)
                                    color: AppTheme.mutedText
                                    font.pixelSize: 11
                                }
                                Item { Layout.fillWidth: true }
                                CalendarButton {
                                    implicitHeight: 24
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
                                    implicitHeight: 36
                                    topPadding: 2
                                    bottomPadding: 2
                                    background: Rectangle {
                                        radius: 6
                                        color: agendaItem.hovered ? root.design.rowHoverFill : "transparent"
                                        border.width: agendaItem.activeFocus ? 1 : 0
                                        border.color: root.design.accent
                                    }
                                    onClicked: root.openItem(modelData)

                                    contentItem: RowLayout {
                                        spacing: 9
                                        AbstractButton {
                                            id: completionButton

                                            visible: root.itemTodoId(agendaItem.modelData).length > 0
                                            // P2-9: 24 was below the macOS
                                            // 28x28 default hit target.
                                            implicitWidth: 28
                                            implicitHeight: 28
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
                                            id: agendaTimeLabel
                                            // P1-2: locale 12h forms ("1:30PM")
                                            // run wider than the old 24h "HH:MM"
                                            // — grow past the 58px floor instead
                                            // of clipping.
                                            Layout.preferredWidth: Math.max(58, agendaTimeLabel.implicitWidth)
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
                                            color: root.design.labelSecondary
                                            font.pixelSize: 10
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
                        id: weekSchedule
                        firstDate: root.weekStart
                        currentTime: root.now
                        dayCount: 7
                        selectedDate: root.selectedDate
                        itemsForDate: root.itemsForDate
                        itemTitle: root.itemTitle
                        itemSecondary: root.itemSecondary
                        itemColor: root.itemColor
                        itemCompleted: root.itemCompleted
                        itemAllDay: root.itemAllDay
                        itemRecord: root.itemRecord
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
                        id: daySchedule
                        firstDate: root.selectedDate
                        currentTime: root.now
                        dayCount: 1
                        selectedDate: root.selectedDate
                        itemsForDate: root.itemsForDate
                        itemTitle: root.itemTitle
                        itemSecondary: root.itemSecondary
                        itemColor: root.itemColor
                        itemCompleted: root.itemCompleted
                        itemAllDay: root.itemAllDay
                        itemRecord: root.itemRecord
                        itemHour: root.itemHour
                        onDateSelected: function(date) { root.selectedDate = date }
                        onItemActivated: function(item) { root.openItem(item) }
                        onCreateRequested: function(date, hour) {
                            eventEditor.openForDate(date, hour)
                        }
                    }
                }

                Component {
                    id: yearPage

                    // R-YEAR step 1: 12-month skeleton from the mini-month
                    // idiom. Step 2: day-cell click selects (stays in year
                    // view; today red disc / selected gray disc, mini-month
                    // idiom), event dots per day, month-label click still
                    // routes to month view.
                    Item {
                        GridLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            columns: 3
                            columnSpacing: 16
                            rowSpacing: 12

                            Repeater {
                                model: 12

                                ItemDelegate {
                                    id: yearMonthCell
                                    required property int index
                                    readonly property date monthStart:
                                        new Date(root.visibleMonth.getFullYear(), index, 1)
                                    readonly property int firstOffset:
                                        (monthStart.getDay() - root.localeFirstDayOfWeek + 7) % 7
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    onClicked: {
                                        root.selectedDate = monthStart
                                        root.visibleMonth = monthStart
                                        root.viewIndex = 0
                                    }

                                    contentItem: ColumnLayout {
                                        spacing: 4

                                        Label {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: AppTheme.formatDate(
                                                yearMonthCell.monthStart, "MMMM")
                                            color: root.design.labelPrimary
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 7
                                            columnSpacing: 0
                                            rowSpacing: 0

                                            Repeater {
                                                model: 42

                                                Item {
                                                    id: yearDayCell
                                                    required property int index
                                                    readonly property date cellDate:
                                                        new Date(
                                                            yearMonthCell.monthStart.getFullYear(),
                                                            yearMonthCell.monthStart.getMonth(),
                                                            index - yearMonthCell.firstOffset + 1)
                                                    readonly property bool inMonth:
                                                        cellDate.getMonth()
                                                            === yearMonthCell.monthStart.getMonth()
                                                    readonly property bool isToday:
                                                        cellDate.getFullYear() === root.now.getFullYear()
                                                            && cellDate.getMonth() === root.now.getMonth()
                                                            && cellDate.getDate() === root.now.getDate()
                                                    readonly property bool isSelected:
                                                        yearDayCell.inMonth && root.sameDay(cellDate, root.selectedDate)
                                                    readonly property int eventCount:
                                                        yearDayCell.inMonth
                                                            ? root.itemsForDate(yearDayCell.cellDate).length
                                                            : 0
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 20

                                                    // P1-9 (A9): the year cell was
                                                    // pointer-only; add keyboard
                                                    // focus plus an accessible
                                                    // identity (date + item count).
                                                    activeFocusOnTab: yearDayCell.inMonth
                                                    Keys.onReturnPressed: yearDayCell.activate()
                                                    Keys.onSpacePressed: yearDayCell.activate()
                                                    function activate() {
                                                        if (yearDayCell.inMonth)
                                                            root.selectedDate = yearDayCell.cellDate
                                                    }
                                                    Accessible.role: yearDayCell.inMonth
                                                        ? Accessible.ListItem : Accessible.NoRole
                                                    Accessible.name: yearDayCell.inMonth
                                                        ? qsTr("%1; %2 items").arg(
                                                              AppTheme.formatDate(cellDate, Locale.LongFormat)).arg(eventCount)
                                                        : ""
                                                    Accessible.focusable: true
                                                    Accessible.onPressAction: yearDayCell.activate()

                                                    // Focus ring only: resting
                                                    // cell keeps its plain look.
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: "transparent"
                                                        border.color: root.design.accent
                                                        border.width: 1
                                                        visible: yearDayCell.activeFocus
                                                    }

                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 14
                                                        height: 14
                                                        radius: 7
                                                        color: yearDayCell.isToday
                                                            ? AppTheme.todayRed
                                                            : (yearDayCell.isSelected
                                                                ? root.design.selectionDisc
                                                                : "transparent")
                                                    }

                                                    Rectangle {
                                                        // Extrapolated (no year-view reference): mini-month idiom dot.
                                                        visible: yearDayCell.eventCount > 0
                                                        width: 3
                                                        height: 3
                                                        radius: 1.5
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        anchors.bottom: parent.bottom
                                                        color: root.design.accent
                                                    }

                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: yearDayCell.inMonth
                                                            ? String(yearDayCell.cellDate.getDate())
                                                            : ""
                                                        color: yearDayCell.isToday || yearDayCell.isSelected
                                                            ? "#FFFFFF"
                                                            : root.design.labelPrimary
                                                        font.pixelSize: 10
                                                        font.weight: yearDayCell.isToday || yearDayCell.isSelected
                                                            ? Font.DemiBold : Font.Normal
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        enabled: yearDayCell.inMonth
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.selectedDate = yearDayCell.cellDate
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: updateEventRange()
}
