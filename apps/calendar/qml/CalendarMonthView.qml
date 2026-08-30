pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosCard {
    id: root

    required property date visibleDate
    required property date selectedDate
    property var itemsForDate: function(date) { return [] }
    property var itemTitle: function(item) { return "" }
    property var itemColor: function(item) { return AppTheme.accent }
    property var itemCompleted: function(item) { return false }

    signal dateSelected(date date)
    signal itemActivated(var item)
    signal createRequested(date date)

    function dateForCell(index) {
        const first = new Date(visibleDate.getFullYear(), visibleDate.getMonth(), 1)
        const mondayOffset = (first.getDay() + 6) % 7
        return new Date(visibleDate.getFullYear(), visibleDate.getMonth(),
                        index - mondayOffset + 1)
    }

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear()
            && left.getMonth() === right.getMonth()
            && left.getDate() === right.getDate()
    }

    contentItem: GridLayout {
        columns: 7
        columnSpacing: 3
        rowSpacing: 3

        Repeater {
            model: 7

            delegate: Label {
                required property int index
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                text: Qt.locale().dayName(index + 1, Locale.ShortFormat)
                color: AppTheme.mutedText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 11
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
                    cellDate.getMonth() === root.visibleDate.getMonth()
                readonly property bool selected: root.sameDay(cellDate, root.selectedDate)
                readonly property bool today: root.sameDay(cellDate, new Date())
                readonly property var dayItems: root.itemsForDate(cellDate)

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 54
                leftPadding: 6
                rightPadding: 6
                topPadding: 5
                bottomPadding: 5
                opacity: inVisibleMonth ? 1 : 0.42
                Accessible.name: Qt.formatDate(cellDate, Locale.LongFormat)
                onClicked: root.dateSelected(cellDate)

                contentItem: ColumnLayout {
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 12
                            color: dayButton.today ? AppTheme.accent : "transparent"

                            Label {
                                anchors.centerIn: parent
                                text: String(dayButton.cellDate.getDate())
                                color: dayButton.today ? "white" : AppTheme.text
                                font.pixelSize: 11
                                font.weight: dayButton.today || dayButton.selected
                                    ? Font.DemiBold : Font.Normal
                            }
                        }

                        Item { Layout.fillWidth: true }

                        ToolButton {
                            text: "+"
                            flat: true
                            visible: dayButton.hovered && dayButton.inVisibleMonth
                            implicitWidth: 24
                            implicitHeight: 24
                            Accessible.name: qsTr("Add event on %1").arg(
                                Qt.formatDate(dayButton.cellDate, Locale.LongFormat))
                            onClicked: {
                                root.dateSelected(dayButton.cellDate)
                                root.createRequested(dayButton.cellDate)
                            }
                        }
                    }

                    Repeater {
                        model: dayButton.dayItems.slice(0, 3)

                        delegate: Rectangle {
                            id: itemChip

                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
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
                                text: (root.itemCompleted(itemChip.modelData) ? "✓ " : "")
                                    + root.itemTitle(itemChip.modelData)
                                color: AppTheme.text
                                font.pixelSize: 9
                                font.strikeout: root.itemCompleted(itemChip.modelData)
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            TapHandler {
                                onTapped: {
                                    root.dateSelected(dayButton.cellDate)
                                    root.itemActivated(itemChip.modelData)
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("+%1 more").arg(dayButton.dayItems.length - 3)
                        color: AppTheme.mutedText
                        font.pixelSize: 9
                        visible: dayButton.dayItems.length > 3
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
                }
            }
        }
    }
}
