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
    property var itemSecondary: function(item) { return "" }
    property var itemColor: function(item) { return AppTheme.accent }
    property var itemCompleted: function(item) { return false }
    property var itemAllDay: function(item) { return false }
    // A03: the all-day chip needs the item's record to know whether the item
    // runs on across this column's boundary — a multi-day strip rounds only its
    // two outer ends.
    property var itemRecord: function(item) { return ({}) }
    property var itemHour: function(item) { return 0 }
    // E04: the timed chip's minute offset inside its start hour, and its
    // duration in minutes (start/end per record; todos default to one hour).
    property var itemStartMinutes: function(item) { return 0 }
    property var itemDurationMinutes: function(item) { return 60 }

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
    // A01 (R006): the spec's literal numbers are the contract — row 18,
    // vertical gap 2, column inset 2–3, band minimum about 28. The earlier
    // 1.33 vertical-factor scaling (row 24) was dropped: the spec is written
    // in logical pixels for THIS window, not rescaled from the reference.
    readonly property int allDayRowHeight: 18
    readonly property int allDayRowGap: 2
    // A04's cap: the tallest band this view will draw before a column spends its
    // last slot on a `+N` remainder row.
    readonly property int allDayMaxRows: 3
    // A01 clause (a) (R106): the band's MINIMUM height. The reference's band hugs
    // its content — top rule y=124 with the first chip at y=126, last chip ending
    // y=181 against the separator at y=183-184, i.e. rows plus a ~1px inset each
    // side and nothing else. A hard 3-row box cannot do that: in a week whose
    // tallest column carries one all-day item it still reserved all three rows.
    // The row count is DERIVED from the content instead, floored at ONE row —
    // the spec's "min about 28" reads 1 + 24 + 1 = 26 here, against the
    // reference's own 1-row band (1 + 18 + 1 = 20) x our 1.33 vertical factor
    // = 26.6 — and capped at allDayMaxRows so A04's overflow row stays reachable.
    readonly property int allDayContentRows: {
        let height = 0
        for (let index = 0; index < dayCount; ++index)
            height = Math.max(height, allDayItems(dateForColumn(index)).length)
        return height
    }
    readonly property int allDayBandRows: Math.max(1,
        Math.min(allDayMaxRows, allDayContentRows))
    // Step 3 (A01): column inset 2 per side — the spec's 2–3 range, taken at
    // its lower edge so adjacent chips keep a 4px gutter between columns. It
    // feeds allDayBandHeight, so the band follows.
    readonly property int allDayBandInset: 2
    // R109 (A03 clause b): how far a continuing chip reaches back past its own
    // column edge. The joint is 2px of field plus the neighbour's 1px rule and
    // the field leftover is known only to ±1 (R108), so the reach is
    // deliberately one px larger than the measured 3px: the fill is opaque, so
    // the overlap is invisible and the slack costs nothing.
    // R006: the field gap between neighbouring chips is now 2 * inset 2 = 4px,
    // so a reach of 4 only MEETS the neighbour and the subpixel rounding of the
    // column origin leaves a 1px white seam (measured at x716/x835 on the R006
    // capture). 6 re-establishes a real 2px overlap; the fill is opaque, so it
    // is invisible.
    readonly property int allDayJointOverlap: 6
    // A01 (a): the band never drops below ~28 even on a single row, per spec.
    readonly property int allDayBandHeight: Math.max(28, allDayBandInset * 2
        + allDayBandRows * allDayRowHeight
        + (allDayBandRows - 1) * allDayRowGap)

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

    // R109 (A03 clause b): the field a chip is drawn on, so the chip fill can be
    // pre-blended to OPAQUE rather than laid down translucent. Must stay equal
    // to Root's `tahoe.contentPlane` (Main.qml:59) — both now read the same
    // AppTheme.neutralPlane token (M05), so they cannot drift.
    readonly property color scheduleField: AppTheme.neutralPlane
    // The backdrop is the field, or the field with the weekend tint already
    // composited into it. `weekendField` cannot be used directly: it is a
    // translucent white on the dark leg, and its alpha would be dropped.
    function allDayBackdrop(column) {
        if (!isWeekendColumn(column))
            return AppTheme.opaque(scheduleField)
        return AppTheme.dark
            ? AppTheme.mix(scheduleField, AppTheme.whiteSeed, 0.03)
            : AppTheme.opaque(weekendField)
    }
    // JS getDay(): 0 = Sunday, 6 = Saturday.
    function isWeekendColumn(column) {
        var day = dateForColumn(column).getDay()
        return day === 0 || day === 6
    }

    // W03: local marker tokens (today red like the macOS reference, subdued
    // grey for the ordinary selection). The red is the shared AppTheme token
    // (M04 hoisted it: the mini month's today disc is its second consumer).
    readonly property color todayRed: AppTheme.todayRed
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
    // P1-2: locale-aware — 24h locales keep zero-padded "HH:MM", 12h locales
    // get the compact form ("1:30PM"), same as the gutter and the agenda.
    readonly property string nowLabel: AppTheme.formatClock(
        (nowRow < 10 ? "0" + nowRow : nowRow) + ":"
        + (currentTime.getMinutes() < 10 ? "0" : "")
        + currentTime.getMinutes())
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
    // A03 (R006): the stored ALL-DAY end is the last covered day itself
    // (inclusive), NOT exclusive. Measured on kos-pim-service: a fixture
    // DTEND;VALUE=DATE:20261024 surfaces as end "2026-10-23", and the editor
    // writes the user's picked end date verbatim. Subtracting a day here
    // cost the strip its last column and broke the continuation test.
    function lastCoveredDay(record) {
        const end = String(record.end ?? "").slice(0, 10)
        return isoDayPattern(end) ? end : ""
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

    // R089: hoisted from the two chip delegates — R079's rule was written out
    // twice (timedChip R079, allDayChip R080) and the band's `+N` row is the
    // third consumer of the same ink. One expression, three reads.
    // The ref's chip ink is the calendar colour moved HALFWAY TO ITS OWN POLE —
    // hue and saturation untouched. Measured 1:1 on refs/macos-calendar.png as
    // ink CORES (not AA edges, which land anywhere in between): the red bar
    // (235,76,70) carries ink (117,37,34), the blue bar (59,134,247) carries
    // (26,67,123), an olive chip (254,204,0) carries (127,102,0) — 1:2 on all
    // three channels. Halving RGB is exactly halving the HSV value, because
    // S = (max-min)/max is invariant under a uniform scale, so the rule needs
    // no colour-space round trip. No separate "saturation/value mapping" is
    // needed: the plain scale reproduces both chips with one parameter.
    // Dark is the theme mirror the ref cannot anchor (it has no dark leg): the
    // same operation toward the other pole, half to white, which sits on the
    // 0.36 wash exactly as the light leg's half-to-black sits on the 0.19 wash.
    function chipInk(item) {
        const c = itemColor(item)
        const pole = AppTheme.dark ? 1 : 0
        return Qt.rgba(c.r + (pole - c.r) * 0.5,
                       c.g + (pole - c.g) * 0.5,
                       c.b + (pole - c.b) * 0.5, 1)
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

    // R091: the 450 ms delay used to be the ONLY path to a correct scroll, so
    // anything that observed the view inside that window (a capture, the user's
    // first look after navigating) still saw the PREVIOUS week's offset. That is
    // the whole R089-vs-R090 "one hour apart" pair: both legs report the same
    // contentY once settled, and the grid lines never move. Position on the
    // trigger itself; the timer stays as the settle-net for the one case the
    // immediate call cannot cover — a content item that is not laid out yet.
    function repositionTimeline() {
        root.positionTimeline()
        autoScrollTimer.restart()
    }

    onFirstDateChanged: repositionTimeline()
    onDayCountChanged: repositionTimeline()
    onVisibleChanged: {
        if (visible)
            repositionTimeline()
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
        // date mark is a 22px red disc for today (white number), a grey
        // disc for the ordinary selected date, nothing for ordinary days.
        // R086: 22 is the reference's own physical diameter, NOT a scaled
        // one. The ref's disc is 22 px around a day-number whose ink is
        // 9 px tall; our number (12px font) also renders 9 px of ink, so
        // the two number sizes are already 1:1 and the disc must be too.
        // (The older "22 ref px x1.33 = 29" note wrongly applied the
        // window-height ratio to a type element that does not scale.)
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
            // P1-7 (A1): the header cell is itself the selectable day target,
            // so the VoiceOver name (weekday + date) lives on the cell, not
            // the labels inside it.
            readonly property string accessibleText:
                Qt.locale().dayName((headerCell.headerDate.getDay() + 6) % 7 + 1,
                                    Locale.ShortFormat)
                + " " + headerCell.headerDate.toLocaleDateString(Qt.locale(),
                                                                 Locale.ShortFormat)

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

            // P1-7 (A1): keyboard focus ring — the cell is focusable (below),
            // and a bare focus without any visible state would be invisible.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: 6
                color: "transparent"
                visible: headerCell.activeFocus
                border.color: AppTheme.accent
                border.width: 1
            }

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
                    width: 22; height: 22; radius: 11
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

            // P1-7 (A1): keep the pointer path, add the keyboard one (Return /
            // Space select the day) and the accessibility surface.
            activeFocusOnTab: true
            Keys.onReturnPressed: root.dateSelected(headerCell.headerDate)
            Keys.onSpacePressed: root.dateSelected(headerCell.headerDate)
            Accessible.role: Accessible.ColumnHeader
            Accessible.name: headerCell.accessibleText
            Accessible.onPressAction: root.dateSelected(headerCell.headerDate)

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
                Layout.preferredHeight: root.allDayBandHeight
                text: qsTr("all-day")
                color: AppTheme.mutedText
                font.pixelSize: 10
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
                        id: allDayStack
                        // R089 (A04 step 2): the band box is allDayBandRows slots tall and
                        // must never drop an item silently. When a column holds MORE items
                        // than it has slots, the last slot is spent on a `+N` remainder row
                        // (the macOS week-view convention) instead of on a chip, so the
                        // column reports its overflow rather than hiding it.
                        // This is a spec/HIG-only design call: the ref
                        // (refs/macos-calendar.png) never exceeds 3 chips in any of its 7
                        // columns, so there is NO ref anchor for the overflow form.
                        // P0-1: overflow only when the items truly do not fit the
                        // band's slots. length == allDayBandRows must render every
                        // chip — the old `length - maxRows + 1` burned a slot on a
                        // "+1" that counted nothing. When it genuinely overflows,
                        // the "+N" row takes the last slot, so N (the hidden count
                        // per the +N row's own contract) is length - visible chips
                        // = length - (bandRows - 1).
                        readonly property int allDayOverflow:
                            allDayColumn.columnItems.length > root.allDayBandRows
                                ? allDayColumn.columnItems.length - root.allDayBandRows + 1
                                : 0
                        readonly property int allDayVisible:
                            root.allDayBandRows - (allDayOverflow > 0 ? 1 : 0)
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
                            // The band box is allDayBandRows slots tall, so it must render that many:
                            // a cap below the slot count is a pure defect, not a layout choice.
                            // R089: unless the column overflows, in which case the last slot
                            // belongs to the `+N` row below.
                            model: allDayColumn.columnItems.slice(0, allDayStack.allDayVisible)
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
                                // A03 clause (b): a continuing chip reaches back past its
                                // own column rule so the run reads as ONE bar. Only the
                                // LEFT side can do that: this column's separator belongs to
                                // this column's delegate, which stacks above the previous
                                // column's chips, so a right-extension could never cover it.
                                // The continuation is a date fact; there may be no
                                // column to its left to reach into (column 0 of the
                                // week), so the reach is gated on one existing.
                                Layout.leftMargin: continuesLeft && allDayColumn.index > 0
                                    ? -root.allDayJointOverlap : 0
                                // R109: the fill is OPAQUE — a pre-blend of itemColor over
                                // this column's own backdrop, not a translucent overlay.
                                // Translucent was unfixable at the joint: two overlapping
                                // chips composite twice and read 11% darker than the bar
                                // (R108, 191 against a 220 fill). Over white the blended
                                // value is identical to the old `withAlpha` fill (220).
                                color: AppTheme.mix(root.allDayBackdrop(allDayColumn.columnDate),
                                    root.itemColor(modelData),
                                    AppTheme.dark ? 0.32 : 0.17)
                                opacity: root.itemCompleted(modelData) ? 0.5 : 1
                                // R080: the band chip's ink is the same rule as the timed
                                // chip's (R079). R089 hoisted it to root.chipInk.
                                readonly property color inkColor: root.chipInk(modelData)

                                // R-H: hand-drawn ring icon — 12×12 outer, border 3 ⇒ 6 hole, 3 px in from the
                                // left, inked like the text. On a left-continuing chip the icon tracks the
                                // column rule (the chip itself reaches back past it by allDayJointOverlap).
                                Rectangle {
                                    x: 3 + (allDayChip.continuesLeft ? root.allDayJointOverlap : 0)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: "transparent"
                                    border.width: 3
                                    border.color: allDayChip.inkColor
                                    // A03: macOS prints the strip's title once, on
                                    // its first day — a continuing column carries
                                    // neither the ring icon nor a repeated label.
                                    visible: !allDayChip.continuesLeft
                                }

                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: 19
                                        + (allDayChip.continuesLeft ? root.allDayJointOverlap : 0)
                                    anchors.rightMargin: 4
                                    visible: !allDayChip.continuesLeft
                                    text: root.itemTitle(allDayChip.modelData)
                                    // R080: was AppTheme.text (grey) — the band chip is the
                                    // same chip family as the timed chip and the ref inks
                                    // both the same way.
                                    color: allDayChip.inkColor
                                    font.pixelSize: 10
                                    font.strikeout: root.itemCompleted(allDayChip.modelData)
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                // P1-7 (A1): the chip was pointer-only; add focus,
                                // keyboard activation and a VoiceOver identity.
                                // All-day items have no time of their own — the
                                // name carries an explicit "All-day" marker.
                                activeFocusOnTab: true
                                Keys.onReturnPressed: root.itemActivated(allDayChip.modelData)
                                Keys.onSpacePressed: root.itemActivated(allDayChip.modelData)
                                Accessible.role: Accessible.ListItem
                                Accessible.name: root.itemTitle(allDayChip.modelData)
                                    + " — " + qsTr("All-day")
                                Accessible.onPressAction: root.itemActivated(allDayChip.modelData)
                                // Focus ring only: R078/R109 keep the resting chip
                                // fill-only, so the border appears on focus alone.
                                border.color: allDayChip.inkColor
                                border.width: allDayChip.activeFocus ? 1 : 0

                                TapHandler {
                                    onTapped: root.itemActivated(allDayChip.modelData)
                                }
                            }
                        }

                        // R089 (A04 step 2): the overflow row. Plain ink text, no fill —
                        // the `+N` is a count of hidden items, not an item, so it must not
                        // read as a chip. It occupies the same 24-px slot a chip would and
                        // takes its ink from the FIRST hidden item, so a column with more
                        // items than slots stays inside the band's own colour family.
                        // Height is bound rather than left to the Label so the slot's
                        // geometry is identical to a chip's (allDayRowHeight, gap above).
                        Label {
                            visible: allDayStack.allDayOverflow > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight:
                                allDayStack.allDayOverflow > 0 ? root.allDayRowHeight : 0
                            text: "+" + allDayStack.allDayOverflow
                            color: allDayStack.allDayOverflow > 0
                                ? root.chipInk(allDayColumn.columnItems[allDayStack.allDayVisible])
                                : "transparent"
                            font.pixelSize: 10
                            leftPadding: 5
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
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

                        // P1-7 (A1): the day columns were pointer-only. Column 0 is
                        // the shared gutter (no date), so it stays out of the focus
                        // chain; the dated cells take Tab focus, arrows move between
                        // them, Space selects the day, Return starts a new event —
                        // the keyboard mirror of the MouseArea's click/double-click.
                        readonly property bool interactive: columnIndex > 0
                        activeFocusOnTab: interactive

                        function moveFocus(delta) {
                            const step = root.dayCount + 1
                            const t = index + delta
                            if (t < 0)
                                return
                            if (t % step === 0)  // column 0 is the gutter — not a target
                                return
                            const siblings = hourCell.parent ? hourCell.parent.children : []
                            if (t >= siblings.length)
                                return
                            const target = siblings[t]
                            if (target && target.rowIndex !== undefined)
                                target.forceActiveFocus()
                        }
                        Keys.onUpPressed: hourCell.moveFocus(-(root.dayCount + 1))
                        Keys.onDownPressed: hourCell.moveFocus(root.dayCount + 1)
                        Keys.onLeftPressed: hourCell.moveFocus(-1)
                        Keys.onRightPressed: hourCell.moveFocus(1)
                        Keys.onReturnPressed: {
                            if (hourCell.interactive)
                                root.createRequested(hourCell.columnDate, hourCell.rowIndex)
                        }
                        Keys.onSpacePressed: {
                            if (hourCell.interactive)
                                root.dateSelected(hourCell.columnDate)
                        }
                        Accessible.role: hourCell.interactive
                            ? Accessible.Cell : Accessible.NoRole
                        Accessible.name: hourCell.interactive
                            ? hourCell.columnDate.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
                              + ", " + hourCell.rowIndex + ":00"
                            : ""
                        Accessible.onPressAction: {
                            if (hourCell.interactive)
                                root.createRequested(hourCell.columnDate, hourCell.rowIndex)
                        }

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
                        // boundary, i.e. the grid line). rightMargin 2 + this
                        // font's ~6px digit side bearing puts the INK 8px from
                        // the line (r3-week-full.png measured ink gap 13 at
                        // margin 7 — spec wants 6–8 visual). The vertical offset is
                        // derived from implicitHeight because this font's line
                        // box is ~1.47em — a hardcoded -7 only centres font 9.
                        // Stays anchored, so it cannot inflate the 40px row.
                        // R-GUTTER: 12-hour two-tone — digits labelPrimary, smaller AM/PM, same baseline.
                        // The +1 (was +4; r9b measured ink centre 3px BELOW
                        // the tick at +4) shifts the whole label so the digit
                        // ink is centred ON the hour line (ref behaviour: ink
                        // centre = hour line); baseline-only centring leaves ink ~4px high.
                        Item {
                            id: hourLabel
                            anchors.top: parent.top
                            anchors.topMargin: -Math.round(digitText.implicitHeight / 2) + 1
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            width: meridiemText.width + 3 + digitText.width
                            height: digitText.implicitHeight
                            // R158: when the timeline is hour-aligned
                            // (positionTimeline always is), the topmost
                            // visible hour line sits ON the grid's top rule
                            // under the all-day band separator, and the clip
                            // slices its label in half — a glyph fragment
                            // floating under the band. Drop that label (the
                            // reference's topmost label sits fully below the
                            // band). 0.5 absorbs contentY rounding.
                            visible: hourCell.columnIndex === 0
                                && hourCell.rowIndex * root.hourHeight
                                   > timelineScroll.contentItem.contentY + 0.5
                                && (root.todayColumn < 0
                                    || Math.abs(hourCell.rowIndex * root.hourHeight
                                                - root.nowLineY)
                                       > root.nowLabelClearance)

                            Label {
                                id: meridiemText
                                anchors.right: parent.right
                                anchors.top: parent.top
                                // P1-1: 24-hour locales have no meridiem — the
                                // digit takes the full gutter edge instead.
                                visible: !AppTheme.localeUses24hClock()
                                text: hourCell.rowIndex < 12 ? AppTheme.meridiemText(0)
                                                             : AppTheme.meridiemText(12)
                                color: AppTheme.mutedText
                                font.pixelSize: 10
                            }
                            Label {
                                id: digitText
                                anchors.right: AppTheme.localeUses24hClock()
                                               ? parent.right : meridiemText.left
                                anchors.rightMargin: 3
                                anchors.baseline: meridiemText.baseline
                                text: {
                                    // P1-1: locale decides 12/24h (no 'h' in
                                    // the locale's short time format ⇒ 24h).
                                    if (AppTheme.localeUses24hClock())
                                        return hourCell.rowIndex + ""
                                    var h = hourCell.rowIndex % 12
                                    return (h === 0 ? 12 : h) + ""
                                }
                                color: AppTheme.text
                                font.pixelSize: 11
                            }
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
                            anchors.rightMargin: 2
                            y: Math.round(root.nowInHour) - height / 2
                            // P1-2: 12h compact labels ("11:30AM") run wider
                            // than the 24h "HH:MM" the 42px pill was sized for.
                            // The gutter is only 52px, so clamp the pill inside
                            // it instead of clipping at the window edge; the
                            // label stays centred and still fits ("11:06AM"
                            // ≈45px < 48px).
                            width: Math.min(
                                Math.max(42, nowPillLabel.implicitWidth + 12),
                                root.gutterWidth - 4)
                            height: 20
                            radius: height / 2
                            color: root.todayRed

                            Label {
                                id: nowPillLabel
                                anchors.centerIn: parent
                                text: root.nowLabel
                                color: "#FFFFFF"
                                font.pixelSize: 11
                                // C3: DemiBold matches the ref's bold capsule
                                // and moves white-on-todayRed onto the 3:1
                                // large-text threshold (same as the 12px
                                // DemiBold day numbers).
                                font.weight: Font.DemiBold
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: hourCell.columnIndex > 0
                            color: "transparent"
                            // P1-7 (A1): keyboard focus ring for the focused hour cell.
                            border.color: AppTheme.accent
                            border.width: hourCell.activeFocus ? 1 : 0

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

                            // T01: same-hour chips sit side-by-side in
                            // half-width lanes, never stacked
                            // (user ruling 2026-10-17).
                            // R-OVERFLOW (user ruling 2026-10-18): max 3
                            // lanes, then a plain +N count for the remainder —
                            // same overflow rules as R-MONTH / the all-day
                            // band's R089 row.
                            Item {
                                id: chipHost
                                anchors.fill: parent
                                anchors.margins: 3
                                readonly property var visibleItems: hourCell.cellItems.slice(0, 3)
                                readonly property bool hasOverflow: hourCell.cellItems.length > 3
                                readonly property int overflowCount: hourCell.cellItems.length - visibleItems.length
                                // 20 logical px reserved at the right edge for the +N label
                                readonly property int overflowReserve: chipHost.hasOverflow ? 20 : 0

                                Repeater {
                                    model: chipHost.visibleItems

                                    delegate: Rectangle {
                                        id: timedChip
                                        required property int index
                                        required property var modelData
                                        width: (chipHost.width
                                            - (chipHost.visibleItems.length - 1) * 2
                                            - chipHost.overflowReserve)
                                            / chipHost.visibleItems.length
                                        x: index * (width + 2)
                                        // E04: the chip starts at its minute
                                        // offset inside the start hour (the
                                        // host's 3px margin gives the top
                                        // inset) and spans its real duration
                                        // at the same 0.96/hour fill the ref
                                        // measures on its 1h chip (26 on 27).
                                        y: (root.itemStartMinutes(modelData)
                                            % 60) * root.hourHeight / 60
                                        // Minimum is one text row + the 2px
                                        // top margin, so a 15–30min block
                                        // still carries its single title line
                                        // (E03) instead of the old fixed 38.
                                        readonly property int durationMinutes:
                                            Math.max(15, root.itemDurationMinutes(modelData))
                                        height: Math.max(19, Math.round(
                                            root.hourHeight * 0.96
                                            * durationMinutes / 60))
                                        // R077: the ref marks every calendar-coloured chip with a
                                        // saturated same-hue bar at its left edge. Measured 1:1 on
                                        // refs/macos-calendar.png: the blue chip's bar reads x=409-411
                                        // = (59,134,247) and the red chip's x=328-330 = (235,76,70),
                                        // i.e. ~2.4 ref px of ink on an ~80 ref px column, its left
                                        // edge ~2 ref px inside the chip's fill (a sliver of the light
                                        // wash shows beside it) and capped round. R-SCALE (user
                                        // ruling 2026-10-17): the ref measures the bar at ~2.4
                                        // px and its inset sliver at ~2 px; x1.35 ⇒ 3 and 3.
                                        // Literal, no longer derived from chip height.
                                        // The inset reuses the measured "sliver ≈ bar width" ratio.
                                        readonly property int stripeWidth: 3
                                        readonly property int stripeInset: stripeWidth
                                        // R079: the ref's chip ink is the calendar colour moved
                                        // halfway to its own pole. R089 hoisted the expression to
                                        // root.chipInk — see there for the measurement.
                                        readonly property color inkColor: root.chipInk(modelData)
                                        // R124: 3, not 5. The chip's corner had been borrowing
                                        // the all-day pill's row/3 ratio (6 on an 18px row),
                                        // which is 0.33 x height. Re-measured on the ref's own
                                        // TIMED chip: the top row y331 never reaches full fill
                                        // across x489..492 (max coverage 0.76) ⇒ a cut of ~1-2
                                        // ref px on 26 = 0.08 x height, i.e. a different family
                                        // entirely. x1.33 ⇒ 2.7, and E01 says "radius about 3".
                                        // Scoped to the timed chip ONLY - the all-day pill keeps
                                        // row/3 and A01/A03 stay closed on it.
                                        radius: 3
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
                                        // bottom so it stays inside the chip's corner curve
                                        // (R124: radius 3; at x=4,y=2 the stripe's top-left is
                                        // 1.4px from the arc centre (3,3), still inside it).
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

                                        // E02 (R-CHIP user ruling 2026-10-17):
                                        // title near the TOP (ref: ink begins right
                                        // under the chip's top edge, never centred)
                                        // with a smaller secondary line under it —
                                        // the time range, same chip ink.
                                        Column {
                                            anchors.fill: parent
                                            // R077: clear the bar. The ref's text ink begins 7 ref px
                                            // from the chip's fill edge (chip x=326, ink x=333) ⇒ ~13
                                            // at our scale = inset + width + the 5 already here.
                                            anchors.leftMargin: timedChip.stripeInset
                                                + timedChip.stripeWidth + 5
                                            anchors.rightMargin: 4
                                            anchors.topMargin: 2
                                            anchors.bottomMargin: 2
                                            spacing: 1

                                            Label {
                                                width: parent.width
                                                text: root.itemTitle(timedChip.modelData)
                                                // R-CHIP: E02 title 11–12 medium.
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                // R079: was AppTheme.text (grey). The ref's ink is
                                                // the chip's own calendar colour at half value.
                                                color: timedChip.inkColor
                                                font.strikeout: root.itemCompleted(timedChip.modelData)
                                                elide: Text.ElideRight
                                            }
                                            // R246: the ref's 2-hour chips open their
                                            // secondary line with a small outlined clock
                                            // glyph (ring 8 ref px ⇒ 11 at our scale,
                                            // stroke 1.5, hands 12+3, same ink as the
                                            // text, ~5px gap, bottom aligned with the
                                            // digits' baseline).
                                            Row {
                                                width: parent.width
                                                // P2-9: the guard hid the secondary
                                                // line when a chip runs too short
                                                // to carry it. E04 made the height
                                                // duration-derived, so it is live
                                                // again: a 1h chip is 38 (shows
                                                // the time range), a 30min chip
                                                // is 19 (title only, E03).
                                                visible: secondaryLabel.text !== ""
                                                    && timedChip.height >= root.hourHeight - 8
                                                spacing: 5

                                                Item {
                                                    width: 11
                                                    height: 11
                                                    anchors.verticalCenter: secondaryLabel.verticalCenter

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 5.5
                                                        color: "transparent"
                                                        border.color: timedChip.inkColor
                                                        border.width: 1.5
                                                    }
                                                    // hand to 12
                                                    Rectangle {
                                                        x: (parent.width - 1.5) / 2
                                                        y: 2.5
                                                        width: 1.5
                                                        height: 4
                                                        color: timedChip.inkColor
                                                    }
                                                    // hand to 3
                                                    Rectangle {
                                                        x: parent.width / 2 - 0.75
                                                        y: parent.height / 2 - 0.75
                                                        width: 3.5
                                                        height: 1.5
                                                        color: timedChip.inkColor
                                                    }
                                                }
                                                Label {
                                                    id: secondaryLabel
                                                    width: parent.width - 16
                                                    text: root.itemSecondary(timedChip.modelData)
                                                    font.pixelSize: 10
                                                    color: timedChip.inkColor
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                        // P1-7 (A1): same keyboard/accessibility surface
                                        // as the all-day chip; the name is title + time
                                        // (itemSecondary carries the formatted time).
                                        activeFocusOnTab: true
                                        Keys.onReturnPressed: root.itemActivated(timedChip.modelData)
                                        Keys.onSpacePressed: root.itemActivated(timedChip.modelData)
                                        Accessible.role: Accessible.ListItem
                                        Accessible.name: root.itemTitle(timedChip.modelData)
                                            + (root.itemSecondary(timedChip.modelData) !== ""
                                               ? ", " + root.itemSecondary(timedChip.modelData) : "")
                                        Accessible.onPressAction: root.itemActivated(timedChip.modelData)
                                        // Focus ring only (R078: resting chip is fill-only).
                                        border.color: timedChip.inkColor
                                        border.width: timedChip.activeFocus ? 1 : 0

                                        TapHandler {
                                            onTapped: root.itemActivated(timedChip.modelData)
                                        }
                                    }
                                }

                                Label {
                                    visible: chipHost.hasOverflow
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: chipHost.overflowReserve - 2
                                    text: "+" + chipHost.overflowCount
                                    // R-OVERFLOW: same overflow form as the all-day
                                    // band's R089 row — plain ink text, no fill, ink
                                    // taken from the FIRST hidden item.
                                    color: chipHost.hasOverflow
                                        ? root.chipInk(hourCell.cellItems[3])
                                        : "transparent"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
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
