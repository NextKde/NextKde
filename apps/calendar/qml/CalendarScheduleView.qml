pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosCard {
    id: root

    required property date firstDate
    property int dayCount: 7
    property var itemsForDate: function(date) { return [] }
    property var itemTitle: function(item) { return "" }
    property var itemColor: function(item) { return AppTheme.accent }
    property var itemCompleted: function(item) { return false }
    property var itemAllDay: function(item) { return false }
    property var itemHour: function(item) { return 0 }

    signal dateSelected(date date)
    signal itemActivated(var item)
    signal createRequested(date date, int hour)

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
        const now = new Date()
        let includesToday = false
        for (let day = 0; day < dayCount; day++) {
            if (sameDay(dateForColumn(day), now)) {
                includesToday = true
                break
            }
        }
        const currentHour = includesToday ? now.getHours() : 24
        if (currentHour >= 6 && currentHour <= 21)
            return Math.max(0, currentHour - 2)
        if (earliest < 24)
            return Math.max(0, earliest - 2)
        return 7
    }

    function positionTimeline() {
        if (timelineScroll.contentItem)
            timelineScroll.contentItem.contentY = usefulStartHour() * 54
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Item { Layout.preferredWidth: 58; Layout.preferredHeight: 48 }

            Repeater {
                model: root.dayCount

                delegate: Rectangle {
                    id: dayHeader
                    required property int index
                    readonly property date headerDate: root.dateForColumn(index)
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    color: root.sameDay(headerDate, new Date())
                        ? AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.14 : 0.08)
                        : "transparent"

                    Column {
                        anchors.centerIn: parent
                        spacing: 1

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.locale().dayName((dayHeader.headerDate.getDay() + 6) % 7 + 1,
                                Locale.ShortFormat)
                            color: AppTheme.mutedText
                            font.pixelSize: 10
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: String(dayHeader.headerDate.getDate())
                            color: root.sameDay(dayHeader.headerDate, new Date())
                                ? AppTheme.accent : AppTheme.text
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }
                    }

                    TapHandler { onTapped: root.dateSelected(dayHeader.headerDate) }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: AppTheme.border
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                Layout.preferredWidth: 58
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
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 2

                        Repeater {
                            model: allDayColumn.columnItems.slice(0, 2)
                            delegate: Rectangle {
                                id: allDayChip
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 18
                                radius: 5
                                color: AppTheme.withAlpha(root.itemColor(modelData),
                                    AppTheme.dark ? 0.32 : 0.17)
                                opacity: root.itemCompleted(modelData) ? 0.5 : 1

                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 4
                                    text: root.itemTitle(allDayChip.modelData)
                                    color: AppTheme.text
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
            Layout.preferredHeight: 1
            color: AppTheme.border
        }

        ScrollView {
            id: timelineScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            GridLayout {
                width: timelineScroll.availableWidth
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

                        Layout.preferredWidth: columnIndex === 0 ? 58 : 0
                        Layout.fillWidth: columnIndex > 0
                        Layout.preferredHeight: 54

                        Label {
                            anchors.top: parent.top
                            anchors.topMargin: -7
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: hourCell.rowIndex < 10
                                ? "0" + hourCell.rowIndex + ":00"
                                : hourCell.rowIndex + ":00"
                            color: AppTheme.mutedText
                            font.pixelSize: 9
                            visible: hourCell.columnIndex === 0
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: hourCell.columnIndex > 0
                            color: root.sameDay(hourCell.columnDate, new Date())
                                ? AppTheme.withAlpha(AppTheme.accent,
                                    AppTheme.dark ? 0.035 : 0.022)
                                : "transparent"
                            border.width: 1
                            border.color: AppTheme.border

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
                                        Layout.preferredHeight: 21
                                        radius: 5
                                        color: AppTheme.withAlpha(root.itemColor(modelData),
                                            AppTheme.dark ? 0.36 : 0.19)
                                        border.width: 1
                                        border.color: AppTheme.withAlpha(
                                            root.itemColor(modelData), 0.34)
                                        opacity: root.itemCompleted(modelData) ? 0.5 : 1

                                        Label {
                                            anchors.fill: parent
                                            anchors.leftMargin: 5
                                            anchors.rightMargin: 4
                                            text: root.itemTitle(timedChip.modelData)
                                            color: AppTheme.text
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

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                y: parent.height * new Date().getMinutes() / 60
                                height: 1
                                color: AppTheme.destructive
                                visible: root.sameDay(hourCell.columnDate, new Date())
                                    && hourCell.rowIndex === new Date().getHours()
                            }
                        }
                    }
                }
            }
        }
    }
}
