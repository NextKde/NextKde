pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

// L01: flush root — no KosCard chrome; the month grid fills the canvas.
// Pane keeps the root-level contentItem contract; padding 0 and a null
// background remove the card look.
Pane {
    id: root

    padding: 0
    background: null

    required property date visibleDate
    required property date selectedDate
    required property date currentTime
    required property int firstDayOfWeek
    property var itemsForDate: function(date) { return [] }
    property var itemKey: function(item) { return "" }
    property var itemTitle: function(item) { return "" }
    property var itemColor: function(item) { return AppTheme.accent }
    property var itemCompleted: function(item) { return false }

    signal dateSelected(date date)
    signal itemActivated(var item)
    signal createRequested(date date)

    function dateForCell(index) {
        const first = new Date(visibleDate.getFullYear(), visibleDate.getMonth(), 1)
        const offset = (first.getDay() - firstDayOfWeek + 7) % 7
        return new Date(visibleDate.getFullYear(), visibleDate.getMonth(),
                        index - offset + 1)
    }

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear()
            && left.getMonth() === right.getMonth()
            && left.getDate() === right.getDate()
    }

    function weekdayName(column) {
        const jsDay = (firstDayOfWeek + column) % 7
        return Qt.locale().dayName(jsDay === 0 ? 7 : jsDay,
                                   Locale.ShortFormat)
    }

    // V03: a multi-day item appears in every covered day's bucket, but the
    // bucket crosses the itemsForDate property boundary (JS object → QVariant
    // copy), so object identity does not survive. Match on the item key
    // (series id + span start) instead: it is stable across the covered days
    // of one event, while daily recurring occurrences keep distinct starts and
    // therefore stay separate chips.
    function itemContinues(item, date, dayOffset) {
        const key = root.itemKey(item)
        if (key.length === 0)
            return false
        const other = new Date(date.getFullYear(), date.getMonth(),
                               date.getDate() + dayOffset)
        const list = root.itemsForDate(other)
        for (let index = 0; index < list.length; index++) {
            if (root.itemKey(list[index]) === key)
                return true
        }
        return false
    }

    contentItem: GridLayout {
        id: monthGrid
        // P2-9 (REVIEW clue 20 + :51): the day delegate's chip budget is
        // silently coupled to these literals — the weekday header's fixed
        // height, the 24px date disc and the 18px chip (each +2 spacing).
        // Naming them keeps a change in one place from silently misaligning
        // the other two.
        readonly property int headerHeight: 30
        readonly property int dayDiscSize: 24
        readonly property int chipHeight: 18
        // V01: the month grid is continuous. Cells butt together (no
        // spacing) and each one paints its own right/bottom hairline, so
        // the rules join into one uninterrupted 7-column grid at any size.
        readonly property real dayHeight: Math.max(0, (height - headerHeight) / 6)
        readonly property color lineColor: AppTheme.withAlpha(
            AppTheme.text, AppTheme.dark ? 0.13 : 0.085)
        columns: 7
        uniformCellWidths: true
        uniformCellHeights: false
        columnSpacing: 0
        rowSpacing: 0

        Repeater {
            model: 7

            delegate: Label {
                required property int index
                Layout.fillWidth: true
                Layout.preferredHeight: monthGrid.headerHeight
                Layout.minimumHeight: monthGrid.headerHeight
                Layout.maximumHeight: monthGrid.headerHeight
                text: root.weekdayName(index)
                color: AppTheme.mutedText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 11
                font.weight: Font.DemiBold

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: monthGrid.lineColor
                }
            }
        }

        Repeater {
            model: 42

            delegate: AbstractButton {
                id: dayButton

                required property int index
                readonly property date cellDate: root.dateForCell(index)
                readonly property bool inVisibleMonth:
                    cellDate.getMonth() === root.visibleDate.getMonth()
                readonly property bool selected: root.sameDay(cellDate, root.selectedDate)
                readonly property bool today: root.sameDay(cellDate, root.currentTime)
                readonly property var dayItems: root.itemsForDate(cellDate)

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: monthGrid.dayHeight
                Layout.maximumHeight: monthGrid.dayHeight
                Layout.minimumWidth: 0
                clip: true
                readonly property int visibleItemCount: Math.max(0, Math.min(3,
                    Math.floor((height - topPadding - bottomPadding
                        - (monthGrid.dayDiscSize + 2)) / (monthGrid.chipHeight + 2))))
                // V03: horizontal padding lives on the date row and on
                // single-day chips, not on the cell itself — a chip that
                // continues into the neighbouring column must be able to run
                // flush to the cell edge (0 margin) and butt against its
                // continuation with no canvas-coloured seam.
                leftPadding: 0
                rightPadding: 0
                topPadding: 5
                bottomPadding: 5
                opacity: inVisibleMonth ? 1 : 0.5
                Accessible.name: AppTheme.formatDate(cellDate, Locale.LongFormat)
                onClicked: root.dateSelected(cellDate)

                contentItem: ColumnLayout {
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        spacing: 2

                        Rectangle {
                            Layout.preferredWidth: monthGrid.dayDiscSize
                            Layout.preferredHeight: monthGrid.dayDiscSize
                            radius: 12
                            // C8: unified with the week header, now-pill and
                            // mini month's today disc — one M04 literal.
                            color: dayButton.today ? AppTheme.todayRed : "transparent"

                            Label {
                                anchors.centerIn: parent
                                text: String(dayButton.cellDate.getDate())
                                // P2-3a: today = white on todayRed, per reference
                                // (3.91:1 deviation accepted by human review).
                                color: dayButton.today ? "white" : AppTheme.text
                                font.pixelSize: 11
                                font.weight: dayButton.today || dayButton.selected
                                    ? Font.DemiBold : Font.Normal
                            }
                        }

                        Item { Layout.fillWidth: true }
                        Label {
                            text: "+" + (dayButton.dayItems.length - dayButton.visibleItemCount)
                            visible: dayButton.dayItems.length > dayButton.visibleItemCount
                            color: AppTheme.mutedText; font.pixelSize: 10
                            Accessible.name: qsTr("%1 items; select this date to view all").arg(dayButton.dayItems.length)
                        }


                        KosToolButton {
                            text: "+"
                            flat: true
                            visible: (dayButton.hovered || dayButton.activeFocus)
                                && dayButton.inVisibleMonth
                            implicitWidth: 24
                            implicitHeight: 24
                            Accessible.name: qsTr("Add event on %1").arg(
                                AppTheme.formatDate(dayButton.cellDate, Locale.LongFormat))
                            onClicked: {
                                root.dateSelected(dayButton.cellDate)
                                root.createRequested(dayButton.cellDate)
                            }
                        }
                    }

                    Repeater {
                        model: dayButton.dayItems.slice(0, dayButton.visibleItemCount)

                        delegate: Rectangle {
                            id: itemChip

                            required property var modelData
                            readonly property bool continuesLeft:
                                root.itemContinues(modelData, dayButton.cellDate, -1)
                            readonly property bool continuesRight:
                                root.itemContinues(modelData, dayButton.cellDate, 1)
                            Layout.fillWidth: true
                            Layout.preferredHeight: monthGrid.chipHeight
                            // V03: continued edges run flush to the cell
                            // boundary and drop their outer rounding so the
                            // two cells' chips read as one bar.
                            Layout.leftMargin: itemChip.continuesLeft ? 0 : 6
                            Layout.rightMargin: itemChip.continuesRight ? 0 : 6
                            radius: 5
                            topLeftRadius: itemChip.continuesLeft ? 0 : itemChip.radius
                            bottomLeftRadius: itemChip.continuesLeft ? 0 : itemChip.radius
                            topRightRadius: itemChip.continuesRight ? 0 : itemChip.radius
                            bottomRightRadius: itemChip.continuesRight ? 0 : itemChip.radius
                            color: AppTheme.withAlpha(root.itemColor(modelData),
                                AppTheme.dark ? 0.30 : 0.16)
                            opacity: root.itemCompleted(modelData) ? 0.52 : 1

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 3
                                radius: 2
                                // V03: the colour stripe marks the bar's
                                // first day only, not every continued cell.
                                visible: !itemChip.continuesLeft
                                color: root.itemColor(itemChip.modelData)
                            }

                            Label {
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 4
                                text: root.itemTitle(itemChip.modelData)
                                color: AppTheme.text
                                font.pixelSize: 10
                                font.strikeout: root.itemCompleted(itemChip.modelData)
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            // P1-8 (A1): the chip was pointer-only; add focus,
                            // keyboard activation and a VoiceOver identity —
                            // same surface as the P1-7 schedule-view chips.
                            activeFocusOnTab: true
                            Keys.onReturnPressed: {
                                root.dateSelected(dayButton.cellDate)
                                root.itemActivated(itemChip.modelData)
                            }
                            Keys.onSpacePressed: {
                                root.dateSelected(dayButton.cellDate)
                                root.itemActivated(itemChip.modelData)
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: root.itemTitle(itemChip.modelData)
                            Accessible.onPressAction: {
                                root.dateSelected(dayButton.cellDate)
                                root.itemActivated(itemChip.modelData)
                            }
                            // Focus ring only: the resting chip is fill-only,
                            // so the border appears on focus alone.
                            border.color: root.itemColor(itemChip.modelData)
                            border.width: itemChip.activeFocus ? 1 : 0

                            TapHandler {
                                onTapped: {
                                    root.dateSelected(dayButton.cellDate)
                                    root.itemActivated(itemChip.modelData)
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                background: Rectangle {
                    radius: AppTheme.smallRadius
                    color: dayButton.selected
                        ? AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.19 : 0.10)
                        : (dayButton.hovered ? AppTheme.cardHover : "transparent")
                    border.width: dayButton.selected || dayButton.activeFocus ? 1 : 0
                    border.color: AppTheme.withAlpha(AppTheme.accent,
                        dayButton.selected ? 0.62 : 0.38)

                    // V01: shared cell rules. Drawn on the background so the
                    // selected/hover fill stays inside them; the last column
                    // and last row have no outer edge.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: monthGrid.lineColor
                        visible: dayButton.index % 7 !== 6
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: monthGrid.lineColor
                        visible: dayButton.index < 35
                    }
                }
            }
        }
    }
}
