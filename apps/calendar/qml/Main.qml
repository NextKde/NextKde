pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosApplicationWindow {
    id: root

    visible: true
    title: qsTr("Calendar")

    property date visibleMonth: new Date()
    property date selectedDate: new Date()

    function monthDate(offset) {
        return new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + offset, 1)
    }

    function dateForCell(index) {
        const first = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1)
        const mondayOffset = (first.getDay() + 6) % 7
        return new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), index - mondayOffset + 1)
    }

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear()
            && left.getMonth() === right.getMonth()
            && left.getDate() === right.getDate()
    }

    Shortcut {
        sequence: "Ctrl+T"
        onActivated: root.visibleMonth = new Date()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 228
            color: AppTheme.withAlpha(AppTheme.sidebar, 0.92)
            border.width: 1
            border.color: AppTheme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 8

                Label {
                    text: qsTr("KOS Calendar")
                    color: AppTheme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    Layout.bottomMargin: 16
                }

                ButtonGroup { id: navigationGroup }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Calendar")
                    symbol: "▦"
                    checked: true
                    ButtonGroup.group: navigationGroup
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Agenda")
                    symbol: "≡"
                    ButtonGroup.group: navigationGroup
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Search")
                    symbol: "⌕"
                    ButtonGroup.group: navigationGroup
                }

                Label {
                    Layout.topMargin: 20
                    text: qsTr("MY CALENDARS")
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                CheckBox {
                    text: qsTr("Personal")
                    checked: true
                }

                Item { Layout.fillHeight: true }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Local calendar · synchronization is disabled")
                    color: AppTheme.mutedText
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

                Label {
                    text: Qt.formatDate(root.visibleMonth, "MMMM yyyy")
                    color: AppTheme.text
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "‹"
                    Accessible.name: qsTr("Previous month")
                    onClicked: root.visibleMonth = root.monthDate(-1)
                }

                Button {
                    text: qsTr("Today")
                    onClicked: {
                        root.visibleMonth = new Date()
                        root.selectedDate = new Date()
                    }
                }

                Button {
                    text: "›"
                    Accessible.name: qsTr("Next month")
                    onClicked: root.visibleMonth = root.monthDate(1)
                }

                Button {
                    text: qsTr("New event")
                    highlighted: true
                    enabled: false
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Event storage is added in the PIM milestone")
                }
            }

            KosCard {
                Layout.fillWidth: true
                Layout.fillHeight: true

                contentItem: GridLayout {
                    columns: 7
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: 7

                        delegate: Label {
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            text: Qt.locale().dayName(index + 1, Locale.ShortFormat)
                            color: AppTheme.mutedText
                            horizontalAlignment: Text.AlignHCenter
                            font.weight: Font.DemiBold
                        }
                    }

                    Repeater {
                        model: 42

                        delegate: Button {
                            id: dayButton

                            required property int index
                            readonly property date cellDate: root.dateForCell(index)
                            readonly property bool inVisibleMonth:
                                cellDate.getMonth() === root.visibleMonth.getMonth()
                            readonly property bool selected: root.sameDay(cellDate, root.selectedDate)
                            readonly property bool today: root.sameDay(cellDate, new Date())

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 70
                            leftPadding: 10
                            rightPadding: 10
                            topPadding: 8
                            bottomPadding: 8
                            text: String(cellDate.getDate())
                            opacity: inVisibleMonth ? 1 : 0.42
                            Accessible.name: Qt.formatDate(cellDate, Locale.LongFormat)
                            onClicked: root.selectedDate = cellDate

                            contentItem: Label {
                                text: dayButton.text
                                color: dayButton.today ? AppTheme.accent : AppTheme.text
                                verticalAlignment: Text.AlignTop
                                horizontalAlignment: Text.AlignLeft
                                font.weight: dayButton.today || dayButton.selected
                                    ? Font.DemiBold : Font.Normal
                            }

                            background: Rectangle {
                                radius: AppTheme.smallRadius
                                color: dayButton.selected
                                    ? AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.24 : 0.14)
                                    : (dayButton.hovered ? AppTheme.cardHover : "transparent")
                                border.width: dayButton.today || dayButton.activeFocus ? 1 : 0
                                border.color: AppTheme.withAlpha(AppTheme.accent, 0.64)
                            }
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Selected: %1").arg(Qt.formatDate(root.selectedDate, Locale.LongFormat))
                color: AppTheme.mutedText
            }
        }
    }
}
