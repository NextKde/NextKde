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

    CalendarStyle { id: design }
    padding: 0
    background: null

    required property date visibleDate
    required property date selectedDate
    required property date currentTime
    required property int firstDayOfWeek
    property var itemsForDate: function(date) { return [] }
    property var itemTitle: function(item) { return "" }
    property var itemColor: function(item) { return AppTheme.accent }
    property var itemCompleted: function(item) { return false }

    signal dateSelected(date date)
    signal itemActivated(var item, Item anchor)
    signal createRequested(date date, Item anchor)

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

    contentItem: GridLayout {
        id: monthGrid
        // P2-9 (REVIEW clue 20 + :51): the day delegate's chip budget is
        // silently coupled to these literals — the weekday header's fixed
        // height, the 24px date disc and the 18px chip (each +2 spacing).
        // Naming them keeps a change in one place from silently misaligning
        // the other two.
        readonly property int headerHeight: 28
        readonly property int dayDiscSize: 20
        readonly property int dayHeaderHeight: 24
        readonly property int chipHeight: 18
        readonly property real dayHeight: Math.max(0, (height - headerHeight - 6 * rowSpacing) / 6)
        columns: 7
        uniformCellWidths: true
        uniformCellHeights: false
        columnSpacing: 1
        rowSpacing: 1

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
                font.weight: Font.Normal
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
                readonly property int visibleItemCount: Math.max(0, Math.min(5,
                    Math.floor((height - topPadding - bottomPadding
                        - (monthGrid.dayHeaderHeight + 2)) / (monthGrid.chipHeight + 2))))
                leftPadding: 6
                rightPadding: 6
                topPadding: 5
                bottomPadding: 5
                opacity: inVisibleMonth ? 1 : 0.5
                Accessible.name: AppTheme.formatDate(cellDate, Locale.LongFormat)
                onClicked: root.dateSelected(cellDate)
                onDoubleClicked: {
                    root.dateSelected(cellDate)
                    root.createRequested(cellDate, dayButton)
                }
                Keys.onReturnPressed: root.createRequested(cellDate, dayButton)

                contentItem: ColumnLayout {
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Rectangle {
                            Layout.preferredWidth: monthGrid.dayDiscSize
                            Layout.preferredHeight: monthGrid.dayDiscSize
                            radius: monthGrid.dayDiscSize / 2
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



                    }

                    Repeater {
                        model: dayButton.dayItems.slice(0, dayButton.visibleItemCount)

                        delegate: Rectangle {
                            id: itemChip

                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: monthGrid.chipHeight
                            radius: 5
                            color: AppTheme.withAlpha(root.itemColor(modelData),
                                AppTheme.dark ? 0.30 : 0.16)
                            opacity: root.itemCompleted(modelData) ? 0.52 : 1

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 3
                                radius: 2
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
                                root.itemActivated(itemChip.modelData, itemChip)
                            }
                            Keys.onSpacePressed: {
                                root.dateSelected(dayButton.cellDate)
                                root.itemActivated(itemChip.modelData, itemChip)
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: root.itemTitle(itemChip.modelData)
                            Accessible.onPressAction: {
                                root.dateSelected(dayButton.cellDate)
                                root.itemActivated(itemChip.modelData, itemChip)
                            }
                            // Focus ring only: the resting chip is fill-only,
                            // so the border appears on focus alone.
                            border.color: root.itemColor(itemChip.modelData)
                            border.width: itemChip.activeFocus ? 1 : 0

                            TapHandler {
                                onTapped: {
                                    root.dateSelected(dayButton.cellDate)
                                    root.itemActivated(itemChip.modelData, itemChip)
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                background: Rectangle {
                    radius: 0
                    color: dayButton.selected
                        ? design.selectionFill
                        : dayButton.hovered ? design.sidebarPlane : "transparent"
                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 1
                        color: design.separator
                    }
                    Rectangle {
                        anchors.right: parent.right
                        height: parent.height
                        width: 1
                        color: design.separator
                        visible: dayButton.index % 7 !== 6
                    }
                }
            }
        }
    }
}
