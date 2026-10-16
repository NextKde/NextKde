pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

// L01: flush root — the schedule fills the main canvas edge to edge with no
// card chrome (the old KosCard added 18 padding, a rounded surface and an
// outer shadow). Pane keeps the root-level contentItem contract; padding 0
// and a null background remove the card look. Content structure and signals
// are unchanged.
Pane {
    id: root

    padding: 0
    background: null

    required property date firstDate
    required property date currentTime
    // W03: the ordinary selected date (distinct from today), bound by the
    // week/day pages in Main.qml.
    property date selectedDate: invalidDate
    readonly property date invalidDate: new Date(NaN)
    property int dayCount: 7
    property var itemsForDate: function(date) { return [] }
    property var itemTitle: function(item) { return "" }
    property var itemColor: function(item) { return AppTheme.accent }
    property var itemCompleted: function(item) { return false }
    property var itemAllDay: function(item) { return false }
    // A03: the all-day chip needs the item's record to know whether the item
    // runs on across this column's boundary — a multi-day strip rounds only its
    // two outer ends.
    property var itemRecord: function(item) { return ({}) }
    property var itemHour: function(item) { return 0 }

    signal dateSelected(date date)
    signal itemActivated(var item)
    signal createRequested(date date, int hour)

    // W01: one shared geometry source. The gutter and every day column take
    // their widths from here, so the header, all-day and timed sections all
    // have identical column boundaries (including the last column at the
    // scrollbar edge). Columns are laid out from width, never from content
    // implicit widths; dayCount 1 gets the same gutter with no empty gap.
    readonly property real gutterWidth: 52
    readonly property real dayColumnWidth: dayCount > 0
        ? (scheduleSpanWidth - gutterWidth) / dayCount : 0
    readonly property real scheduleSpanWidth: width
    // T01: single source for the hour pitch of the timed grid. The hour-cell
    // delegate height and the initial scroll offset both derive from this, so
    // they can no longer drift apart.
    readonly property int hourHeight: 40

    // A01 step 2 (R072): the all-day band's row geometry, derived from one
    // anchor and measured off the reference at 1:1. Reference rows sit at
    // y126-143, y145-162, y164-181 => row 18, gap 1, pitch 19, three rows
    // spanning a 60px band (top rule y124, bottom separator y183-184).
    // Our vertical factor against the reference is 1.33 (40px hour pitch vs
    // 27), so row 18 -> 24, gap 1 -> 1, and the 60px band -> 80px. The band
    // height is DERIVED from the row height so the two can never drift.
    readonly property int allDayRowHeight: 24
    readonly property int allDayRowGap: 1
    readonly property int allDayBandRows: 3
    // Step 3: the reference's band inset, measured 1:1 (top rule y=124, the
    // first chip starting at y=126 => ~1 ref-px), x our 1.33 vertical factor
    // => ~1.3, taken as 1. It feeds allDayBandHeight, so the band follows.
    readonly property int allDayBandInset: 1
    readonly property int allDayBandHeight: allDayBandInset * 2
        + allDayBandRows * allDayRowHeight
        + (allDayBandRows - 1) * allDayRowGap

    // T02: the two grid-line weights. Neutral (no blue tint), 1px each;
    // the half-hour line is one step lighter than the hour line. The light
    // value is the reference's own measured hour-line colour, (237,237,237).
    readonly property color gridLine: AppTheme.dark
        ? Qt.rgba(1, 1, 1, 0.13) : "#EDEDED"
    readonly property color gridLineMinor: AppTheme.dark
        ? Qt.rgba(1, 1, 1, 0.06) : "#F4F4F4"

    // T04: the all-day band's bottom separator. Deliberately heavier than the
    // hour lines — the reference draws it at 2px (217,217,217), one step
    // stronger than its 1px (237,237,237) hour lines. Local token: do NOT
    // reuse AppTheme.border (app-wide, blue-tinted) and do NOT reuse gridLine.
    readonly property color allDaySeparator: AppTheme.dark
        ? Qt.rgba(1, 1, 1, 0.24) : "#D9D9D9"

    // R069: the all-day band's TOP boundary. The reference draws it at 1px
    // (242,242,242) — its LIGHTEST rule, lighter than the hour lines (237).
    // Do NOT reuse AppTheme.border (app-wide, blue-tinted, renders 223,225,228
    // and inverts the weight order) and do NOT reuse gridLine (237).
    readonly property color sectionRule: AppTheme.dark
        ? Qt.rgba(1, 1, 1, 0.04) : "#F2F2F2"

    // R070: the weekend columns carry a section tint over the whole schedule
    // field — the all-day band and the hour grid alike, but NOT the day-header
    // row. Re-measured on the reference (row-mode over empty columns, band
    // y126-181 and hour grid y500): weekday columns are 255, Sat/Sun are 249
    // in BOTH regions. There is no band-only tint: the earlier "weekday 249 /
    // weekend 244" reading was the half-strength row of the 242 boundary.
    readonly property color weekendField: AppTheme.dark
        ? Qt.rgba(1, 1, 1, 0.03) : "#F9F9F9"
    // JS getDay(): 0 = Sunday, 6 = Saturday.
    function isWeekendColumn(column) {
        var day = dateForColumn(column).getDay()
        return day === 0 || day === 6
    }

    // W03: local marker tokens (today red like the macOS reference, subdued
    // grey for the ordinary selection). Neutral, no shared-theme dependency.
    readonly property color todayRed: "#E5484D"
    readonly property color selectionGrey: AppTheme.dark
        ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color normalDateColor: AppTheme.dark
        ? "#F2F2F2" : "#1A1A1A"
    readonly property color weekendText: AppTheme.mutedText

    // N02: the current-time line is ONE object in four parts — a faint rule
    // across the whole grid, a full-strength rule and its dot on today's
    // column, and a saturated pill in the gutter at the true now-position.
    // Every part derives its geometry from this one group, so they cannot
    // drift apart; only today's column is resolved per hour-cell.
    readonly property int nowRow: currentTime.getHours()
    // Offset of the now-position inside its own hour row. Rows are exactly
    // hourHeight, so this is the line's local y as well as the offset the
    // gutter pill is centred on.
    readonly property real nowInHour: currentTime.getMinutes() * hourHeight / 60
    readonly property real nowLineY: nowRow * hourHeight + nowInHour
    readonly property string nowLabel: (nowRow < 10 ? "0" + nowRow : nowRow) + ":"
        + (currentTime.getMinutes() < 10 ? "0" : "")
        + currentTime.getMinutes()
    readonly property int todayColumn: {
        for (let column = 0; column < dayCount; column++)
            if (sameDay(dateForColumn(column), currentTime))
                return column
        return -1
    }
    // The pill is 20px tall and an hour label's ink is 9px, both centred on
    // their own y — closer than half their sum and the reference drops the
    // label rather than letting the two overlap.
    readonly property real nowLabelClearance: 14

    // The scrolling schedule viewport, exposed read-only for the header's
    // liquid-glass lens: the glass buttons sample a live, blurred strip of
    // this item (G01/G05). Sampling the viewport rather than the contentItem
    // means the strip is always the content currently visible under the
    // header, and follows real scrolling without any contentY binding.
    readonly property alias contentViewport: timelineScroll

    function dateForColumn(column) {
        return new Date(firstDate.getFullYear(), firstDate.getMonth(),
                        firstDate.getDate() + column)
    }

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear()
            && left.getMonth() === right.getMonth()
            && left.getDate() === right.getDate()
    }

    function allDayItems(date) {
        const source = itemsForDate(date)
        const result = []
        for (let index = 0; index < source.length; index++) {
            if (itemAllDay(source[index]))
                result.push(source[index])
        }
        return result
    }

    // A03: a multi-day all-day item is ONE strip, not one pill per day. Only the
    // run's two outer ends round; the corners where the item carries on into the
    // neighbouring column stay square. A chip therefore has to know whether its
    // item also covers the day before / after this column.
    //
    // Compared as ISO day strings. The stored all-day start/end are date-times in
    // the event's own zone, and `new Date("YYYY-MM-DD")` parses as UTC midnight,
    // which shifts the day in a negative-offset zone — so the date part is read
    // as text and only the "end − 1 day" step uses local components.
    function isoDay(date) {
        return date.getFullYear() + "-"
            + String(date.getMonth() + 1).padStart(2, "0") + "-"
            + String(date.getDate()).padStart(2, "0")
    }
    function isoDayPattern(text) {
        return /^\d{4}-\d{2}-\d{2}$/.test(text)
    }
    function allDayRecord(item) {
        return itemRecord(item) ?? ({})
    }
    // The stored all-day end is exclusive, so the last covered day is end − 1.
    function lastCoveredDay(record) {
        const end = String(record.end ?? "").slice(0, 10)
        if (!isoDayPattern(end))
            return ""
        const parts = end.split("-")
        return isoDay(new Date(Number(parts[0]), Number(parts[1]) - 1,
                               Number(parts[2]) - 1))
    }
    function allDayContinues(item, date, direction) {
        const record = allDayRecord(item)
        const today = isoDay(date)
        if (direction < 0) {
            const start = String(record.start ?? "").slice(0, 10)
            return isoDayPattern(start) && start < today
        }
        const last = lastCoveredDay(record)
        return isoDayPattern(last) && last > today
    }

    function hourItems(date, hour) {
        const source = itemsForDate(date)
        const result = []
        for (let index = 0; index < source.length; index++) {
            if (!itemAllDay(source[index]) && itemHour(source[index]) === hour)
                result.push(source[index])
        }
        return result
    }

    function usefulStartHour() {
        let earliest = 24
        for (let day = 0; day < dayCount; day++) {
            const source = itemsForDate(dateForColumn(day))
            for (let index = 0; index < source.length; index++) {
                if (!itemAllDay(source[index]))
                    earliest = Math.min(earliest, itemHour(source[index]))
            }
        }
        let includesToday = false
        for (let day = 0; day < dayCount; day++) {
            if (sameDay(dateForColumn(day), currentTime)) {
                includesToday = true
                break
            }
        }
        const currentHour = includesToday ? currentTime.getHours() : 24
        if (currentHour >= 6 && currentHour <= 21)
            return Math.max(0, currentHour - 2)
        if (earliest < 24)
            return Math.max(0, earliest - 2)
        return 7
    }

    function positionTimeline() {
        if (timelineScroll.contentItem)
            timelineScroll.contentItem.contentY = usefulStartHour() * root.hourHeight
    }

    onFirstDateChanged: autoScrollTimer.restart()
    onDayCountChanged: autoScrollTimer.restart()
    onVisibleChanged: {
        if (visible)
            autoScrollTimer.restart()
    }

    Timer {
        id: autoScrollTimer
        interval: 450
        onTriggered: root.positionTimeline()
    }

    contentItem: ColumnLayout {
        spacing: 0

        // W02/W03: compact 36px date header. Weekday (11px) and date (12px)
        // sit on one shared row, the pair centred in each day column; the
        // date mark is a 20px red disc for today (white number), a grey
        // disc for the ordinary selected date, nothing for ordinary days.
        // Weekend columns read one step dimmer. Column boundaries come from
        // the shared gutter/column geometry, so header, all-day and timed
        // sections align exactly.
        component DayHeaderCell: Item {
            id: headerCell

            required property date headerDate
            readonly property bool today: root.sameDay(headerCell.headerDate,
                                                       root.currentTime)
            readonly property bool selected: root.sameDay(
                headerCell.headerDate, root.selectedDate)
            readonly property bool weekend: headerCell.headerDate.getDay() === 0
                || headerCell.headerDate.getDay() === 6

            width: root.dayColumnWidth
            height: 36
            // Layout-managed: pin all three attached widths to the shared
            // column width so the RowLayout can never substitute cached
            // implicit/preferred sizes (an Item's implicitWidth is 0 — the
            // earlier resize bug came exactly from that fallback).
            Layout.minimumWidth: root.dayColumnWidth
            Layout.preferredWidth: root.dayColumnWidth
            Layout.maximumWidth: root.dayColumnWidth
            implicitWidth: root.dayColumnWidth
            objectName: "dayHeaderCell"

            Row {
                anchors.centerIn: parent
                spacing: 4

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.locale().dayName(
                        (headerCell.headerDate.getDay() + 6) % 7 + 1,
                        Locale.ShortFormat)
                    color: headerCell.weekend ? root.weekendText
                                              : AppTheme.text
                    font.pixelSize: 11
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 10
                    color: headerCell.today ? root.todayRed
                        : (headerCell.selected && !headerCell.today
                           ? root.selectionGrey : "transparent")

                    Label {
                        anchors.centerIn: parent
                        text: String(headerCell.headerDate.getDate())
                        color: headerCell.today ? "#FFFFFF"
                            : root.normalDateColor
                        font.pixelSize: 12
                        font.weight: headerCell.today
                            ? Font.DemiBold : Font.Normal
                    }
                }
            }

            TapHandler { onTapped: root.dateSelected(headerCell.headerDate) }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Item {
                objectName: "scheduleGutterHeader"
                Layout.preferredWidth: root.gutterWidth
                Layout.minimumWidth: root.gutterWidth
                Layout.maximumWidth: root.gutterWidth
                Layout.preferredHeight: 36
            }

            Repeater {
                model: root.dayCount

                delegate: DayHeaderCell {
                    required property int index
                    headerDate: root.dateForColumn(index)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.sectionRule
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                objectName: "scheduleGutterAllDay"
                Layout.preferredWidth: root.gutterWidth
                Layout.minimumWidth: root.gutterWidth
                Layout.maximumWidth: root.gutterWidth
                Layout.preferredHeight: 48
                text: qsTr("all-day")
                color: AppTheme.mutedText
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                topPadding: 8
            }

            Repeater {
                model: root.dayCount

                delegate: Item {
                    id: allDayColumn
                    required property int index
                    readonly property date columnDate: root.dateForColumn(index)
                    readonly property var columnItems: root.allDayItems(columnDate)
                    width: root.dayColumnWidth
                    implicitWidth: root.dayColumnWidth
                    Layout.minimumWidth: root.dayColumnWidth
                    Layout.preferredWidth: root.dayColumnWidth
                    Layout.maximumWidth: root.dayColumnWidth
                    Layout.preferredHeight: root.allDayBandHeight

                    // R070: the weekend section tint, behind the chips.
                    // Declared first so it stacks below every chip and below
                    // the column separators. Weekday columns stay transparent
                    // (the field is white there).
                    Rectangle {
                        anchors.fill: parent
                        color: root.isWeekendColumn(allDayColumn.index)
                            ? root.weekendField : "transparent"
                    }

                    // A01: the band carries the same column separators as the
                    // grid, so the two read as one continuous rule. The ref's
                    // separators run unbroken through the all-day band at its
                    // hour-line weight (measured 1:1: x=324/406/487 → 244/236/242,
                    // i.e. ONE line at three subpixel coverages, full coverage
                    // ≈236 = its own hour-line token). So this reuses gridLine —
                    // no band-only token. Same idiom as the hourCell below:
                    // one 1px LEFT edge per column (never a left+right pair, or
                    // neighbours stack into a 2px band), its LEFT pixel on the
                    // delegate's x so it lands on the grid's 502/652, and a
                    // right rim only on the last column.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: root.gridLine
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        visible: allDayColumn.index === root.dayCount - 1
                        color: root.gridLine
                    }

                    ColumnLayout {
                        // R072: hug the rows instead of filling the band. A
                        // ColumnLayout taller than its items does NOT leave the
                        // slack at the bottom — it spreads the surplus into its
                        // spacings (a leading half-spacing, the between-spacing,
                        // and a trailing half-spacing). Measured on the R072
                        // capture: inset 3 + gap 1 rendered as 7 / 13 / 6, i.e.
                        // the chips drifted apart. Binding the height to
                        // implicitHeight removes the surplus entirely, so the
                        // chips stack from the top on a true allDayRowGap.
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: root.allDayBandInset
                        height: implicitHeight
                        spacing: root.allDayRowGap

                        Repeater {
                            model: allDayColumn.columnItems.slice(0, 2)
                            delegate: Rectangle {
                                id: allDayChip
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.allDayRowHeight
                                // Ref radius ≈ 6 ref-px against an 18 ref-px row ⇒ 1/3 of the row height.
                                // Derived, not a literal: a row-height change must carry the corner with it.
                                readonly property int endRadius: Math.round(root.allDayRowHeight / 3)
                                // A03: only the strip's outer ends round. Where the item carries on
                                // into the next/previous column the corner is square, so a multi-day
                                // item reads as one continuous bar behind the column rules instead of
                                // as one pill per day. A single-day item continues neither way and so
                                // gets its radius on all four corners, unchanged.
                                readonly property bool continuesLeft: root.allDayContinues(modelData,
                                    allDayColumn.columnDate, -1)
                                readonly property bool continuesRight: root.allDayContinues(modelData,
                                    allDayColumn.columnDate, 1)
                                topLeftRadius: continuesLeft ? 0 : endRadius
                                bottomLeftRadius: continuesLeft ? 0 : endRadius
                                topRightRadius: continuesRight ? 0 : endRadius
                                bottomRightRadius: continuesRight ? 0 : endRadius
                                color: AppTheme.withAlpha(root.itemColor(modelData),
                                    AppTheme.dark ? 0.32 : 0.17)
                                opacity: root.itemCompleted(modelData) ? 0.5 : 1
                                // R080: the band chip's ink is the same rule as the timed
                                // chip's (R079) — the calendar colour halfway to its pole.
                                // Measured on the REF's band chips, 1:1, against their own
                                // coloured ring icon: purple ring (187,62,217) → ink core
                                // (93,30,108); blue-grey ring (133,148,173) → (67,74,86).
                                // Both are 1:2 on every channel (the .5 rounds down where
                                // the colour is odd), hue and saturation untouched.
                                readonly property color inkColor: {
                                    var c = root.itemColor(modelData)
                                    var pole = AppTheme.dark ? 1 : 0
                                    return Qt.rgba(c.r + (pole - c.r) * 0.5,
                                                   c.g + (pole - c.g) * 0.5,
                                                   c.b + (pole - c.b) * 0.5, 1)
                                }

                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 4
                                    text: root.itemTitle(allDayChip.modelData)
                                    // R080: was AppTheme.text (grey) — the band chip is the
                                    // same chip family as the timed chip and the ref inks
                                    // both the same way.
                                    color: allDayChip.inkColor
                                    font.pixelSize: 9
                                    font.strikeout: root.itemCompleted(allDayChip.modelData)
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                TapHandler {
                                    onTapped: root.itemActivated(allDayChip.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 2
            color: root.allDaySeparator
        }

        ScrollView {
            id: timelineScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            GridLayout {
                objectName: "scheduleTimedGrid"
                // The grid is exactly the viewport width — never wider. Pin
                // implicitWidth to the same value so the ScrollView's
                // Flickable contentWidth cannot adopt a stale implicit sum
                // (that runaway made the grid outlive the window on resize).
                width: timelineScroll.availableWidth
                implicitWidth: width
                columns: root.dayCount + 1
                columnSpacing: 0
                rowSpacing: 0

                Repeater {
                    model: 24 * (root.dayCount + 1)

                    delegate: Item {
                        id: hourCell
                        required property int index
                        readonly property int rowIndex: Math.floor(index / (root.dayCount + 1))
                        readonly property int columnIndex: index % (root.dayCount + 1)
                        readonly property date columnDate: root.dateForColumn(columnIndex - 1)
                        readonly property var cellItems: columnIndex > 0
                            ? root.hourItems(columnDate, rowIndex) : []

                        // W01: same shared gutter width, same dayColumnWidth
                        // for every timed column — identical boundaries to
                        // the header/all-day rows. min/preferred/max pinned
                        // so the grid distributes exactly; the vertical
                        // scrollbar overlays and never reshapes the columns.
                        Layout.minimumWidth: columnIndex === 0
                            ? root.gutterWidth : root.dayColumnWidth
                        Layout.preferredWidth: columnIndex === 0
                            ? root.gutterWidth : root.dayColumnWidth
                        Layout.maximumWidth: columnIndex === 0
                            ? root.gutterWidth : root.dayColumnWidth
                        Layout.fillWidth: false
                        Layout.preferredHeight: root.hourHeight

                        // R070: the same weekend section tint covers the hour
                        // grid, so the band and the grid agree on the column's
                        // field colour (reference: 249 on both, 255 on
                        // weekdays). Declared first: it must sit below the four
                        // edge rules and below the chips.
                        Rectangle {
                            anchors.fill: parent
                            color: hourCell.columnIndex > 0
                                && root.isWeekendColumn(hourCell.columnIndex - 1)
                                ? root.weekendField : "transparent"
                        }

                        // T03: hour labels 10-11px, right-aligned 7px from the
                        // grid's left edge (parent.right IS the gutter/day
                        // boundary, i.e. the grid line). The vertical offset is
                        // derived from implicitHeight because this font's line
                        // box is ~1.47em — a hardcoded -7 only centres font 9.
                        // Stays anchored, so it cannot inflate the 40px row.
                        Label {
                            anchors.top: parent.top
                            anchors.topMargin: -Math.round(implicitHeight / 2)
                            anchors.right: parent.right
                            anchors.rightMargin: 7
                            text: hourCell.rowIndex < 10
                                ? "0" + hourCell.rowIndex + ":00"
                                : hourCell.rowIndex + ":00"
                            color: AppTheme.mutedText
                            font.pixelSize: 11
                            // N02: the reference drops the hour label the
                            // now-pill would collide with (its 10 AM label is
                            // gone under the 9:41 pill while 9 AM survives).
                            // A week that does not contain today shows the
                            // line nowhere, so it keeps every label.
                            visible: hourCell.columnIndex === 0
                                && (root.todayColumn < 0
                                    || Math.abs(hourCell.rowIndex * root.hourHeight
                                                - root.nowLineY)
                                       > root.nowLabelClearance)
                        }

                        // N02: the now-pill. The reference puts the current
                        // time in a saturated red capsule in the gutter at the
                        // TRUE now-position — not snapped to a tick — sharing
                        // the hour labels' right edge, and in white.
                        Rectangle {
                            objectName: "nowPill"
                            visible: hourCell.columnIndex === 0
                                && root.todayColumn >= 0
                                && hourCell.rowIndex === root.nowRow
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            y: Math.round(root.nowInHour) - height / 2
                            width: 42
                            height: 20
                            radius: height / 2
                            color: root.todayRed

                            Label {
                                anchors.centerIn: parent
                                text: root.nowLabel
                                color: "#FFFFFF"
                                font.pixelSize: 11
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: hourCell.columnIndex > 0
                            color: "transparent"

                            // T02: exactly one 1px line per boundary. A cell
                            // draws only its own top and left edge, so two
                            // neighbours can never stack into a 2px band.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: 1
                                color: root.gridLine
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                y: Math.round(parent.height / 2)
                                height: 1
                                color: root.gridLineMinor
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 1
                                color: root.gridLine
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 1
                                visible: hourCell.columnIndex === root.dayCount
                                color: root.gridLine
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.dateSelected(hourCell.columnDate)
                                onDoubleClicked: {
                                    root.dateSelected(hourCell.columnDate)
                                    root.createRequested(hourCell.columnDate, hourCell.rowIndex)
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 3
                                spacing: 2

                                Repeater {
                                    model: hourCell.cellItems.slice(0, 2)

                                    delegate: Rectangle {
                                        id: timedChip
                                        required property var modelData
                                        Layout.fillWidth: true
                                        // T01: two chips plus spacing must fit
                                        // the 40px cell minus the 3px margins.
                                        Layout.preferredHeight: Math.round(
                                            root.hourHeight * 21 / 54)
                                        // R077: the ref marks every calendar-coloured chip with a
                                        // saturated same-hue bar at its left edge. Measured 1:1 on
                                        // refs/macos-calendar.png: the blue chip's bar reads x=409-411
                                        // = (59,134,247) and the red chip's x=328-330 = (235,76,70),
                                        // i.e. ~2.4 ref px of ink on an ~80 ref px column, its left
                                        // edge ~2 ref px inside the chip's fill (a sliver of the light
                                        // wash shows beside it) and capped round. Derived from the chip
                                        // it sits in — the icon/corner family's row/3 idiom — so a chip
                                        // height change carries the bar with it, and the inset reuses
                                        // the measured "sliver ≈ bar width" ratio.
                                        readonly property int stripeWidth: Math.round(
                                            Math.round(root.hourHeight * 21 / 54) / 4)
                                        readonly property int stripeInset: stripeWidth
                                        // R079: the ref's chip ink is the calendar colour moved
                                        // HALFWAY TO ITS OWN POLE — hue and saturation untouched.
                                        // Measured 1:1 on refs/macos-calendar.png as ink CORES (not
                                        // AA edges, which land anywhere in between): the red bar
                                        // (235,76,70) carries ink (117,37,34), the blue bar
                                        // (59,134,247) carries (26,67,123), an olive chip
                                        // (254,204,0) carries (127,102,0) — 1:2 on all three
                                        // channels. Halving RGB is exactly halving the HSV value,
                                        // because S = (max-min)/max is invariant under a uniform
                                        // scale, so the rule needs no colour-space round trip.
                                        // No separate "saturation/value mapping" is needed: the
                                        // plain scale reproduces both chips with one parameter.
                                        // Dark is the theme mirror the ref cannot anchor (it has
                                        // no dark leg): the same operation toward the other pole,
                                        // half to white, which sits on the 0.36 wash exactly as
                                        // the light leg's half-to-black sits on the 0.19 wash.
                                        readonly property color inkColor: {
                                            var c = root.itemColor(modelData)
                                            var pole = AppTheme.dark ? 1 : 0
                                            return Qt.rgba(c.r + (pole - c.r) * 0.5,
                                                           c.g + (pole - c.g) * 0.5,
                                                           c.b + (pole - c.b) * 0.5, 1)
                                        }
                                        radius: 5
                                        color: AppTheme.withAlpha(root.itemColor(modelData),
                                            AppTheme.dark ? 0.36 : 0.19)
                                        // R078: NO border. The ref's chip is fill-only, and its
                                        // edges only ever go LIGHTER than the fill, never darker.
                                        // Measured 1:1 on refs/macos-calendar.png at three
                                        // independent edges: Wed blue chip top 255 → 242 (rule) →
                                        // 249 → (230,242,254) AA → (222,237,254) fill; Wed blue
                                        // chip bottom fill → (224,235,248) AA → 242 (rule) → red
                                        // chip AA (253,242,241); Tue blue chip top 255 → 249 →
                                        // 236 (hour line) → (239,246,255) AA → fill. A 1px ring
                                        // at any alpha would land here as a row darker AND more
                                        // saturated than the fill — none of the three has one.
                                        // The left edge cannot prove this (it abuts the column
                                        // rule at x=406 and R077 red a 1px border there); a top
                                        // or bottom edge can, which is why both were read.
                                        opacity: root.itemCompleted(modelData) ? 0.5 : 1

                                        // R077: the calendar-colour bar. Full saturation, no
                                        // alpha — the ref's bars read (59,134,247) and
                                        // (235,76,70). A capsule stripeWidth wide, inset by
                                        // stripeInset, held 2px clear of the chip's top and
                                        // bottom so it stays inside the 5px corner curve.
                                        Rectangle {
                                            x: timedChip.stripeInset
                                            width: timedChip.stripeWidth
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.topMargin: 2
                                            anchors.bottomMargin: 2
                                            radius: Math.round(timedChip.stripeWidth / 2)
                                            color: root.itemColor(timedChip.modelData)
                                        }

                                        Label {
                                            anchors.fill: parent
                                            // R077: clear the bar. The ref's text ink begins 7 ref px
                                            // from the chip's fill edge (chip x=326, ink x=333) ⇒ ~13
                                            // at our scale = inset + width + the 5 already here.
                                            anchors.leftMargin: timedChip.stripeInset
                                                + timedChip.stripeWidth + 5
                                            anchors.rightMargin: 4
                                            text: root.itemTitle(timedChip.modelData)
                                            // R079: was AppTheme.text (grey). The ref's ink is
                                            // the chip's own calendar colour at half value.
                                            color: timedChip.inkColor
                                            font.pixelSize: 9
                                            font.strikeout: root.itemCompleted(timedChip.modelData)
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                        TapHandler {
                                            onTapped: root.itemActivated(timedChip.modelData)
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }

                            // N02: the current-time rule — 2px at the true
                            // now-position, full strength across today's column
                            // and 10% across the rest of the week. The reference
                            // starts it at the grid's left edge, so the gutter
                            // cell deliberately draws none of it.
                            Rectangle {
                                objectName: "nowLine"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                y: Math.round(root.nowInHour)
                                height: 2
                                color: hourCell.columnIndex - 1 === root.todayColumn
                                    ? root.todayRed
                                    : Qt.rgba(root.todayRed.r, root.todayRed.g,
                                              root.todayRed.b, 0.10)
                                visible: hourCell.columnIndex > 0
                                    && root.todayColumn >= 0
                                    && hourCell.rowIndex === root.nowRow
                            }

                            // N02: the dot sits ON today's left column rule, so
                            // it hangs half into the previous column — which is
                            // drawn first, leaving the dot on top.
                            Rectangle {
                                objectName: "nowDot"
                                x: -width / 2
                                y: Math.round(root.nowInHour) + 1 - height / 2
                                width: 9
                                height: 9
                                radius: width / 2
                                color: root.todayRed
                                visible: root.todayColumn >= 0
                                    && hourCell.columnIndex - 1 === root.todayColumn
                                    && hourCell.rowIndex === root.nowRow
                            }
                        }
                    }
                }
            }
        }
    }
}
