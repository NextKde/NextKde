pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Pim
import Kos.Ui

KosApplicationWindow {
    id: root

    visible: true
    title: qsTr("Calendar")

    property date visibleMonth: new Date()
    property date selectedDate: new Date()
    readonly property var selectedEvents: eventsForDate(selectedDate)

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        const result = record[key]
        return result === undefined || result === null ? fallback : result
    }

    function monthDate(offset) {
        return new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + offset, 1)
    }

    function dateForCell(index) {
        const first = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1)
        const mondayOffset = (first.getDay() + 6) % 7
        return new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(),
                        index - mondayOffset + 1)
    }

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear()
            && left.getMonth() === right.getMonth()
            && left.getDate() === right.getDate()
    }

    function dateKey(date) {
        return Qt.formatDate(date, "yyyy-MM-dd")
    }

    function eventStartKey(event) {
        return String(value(event, "start", "")).slice(0, 10)
    }

    function eventsForDate(date) {
        const key = dateKey(date)
        const matches = []
        const source = pim.occurrences ?? []
        for (let index = 0; index < source.length; index++) {
            const event = source[index]
            const start = eventStartKey(event)
            const end = String(value(event, "end", "")).slice(0, 10)
            if (start === key || (start < key && end > key))
                matches.push(event)
        }
        return matches
    }

    function eventTime(event) {
        if (Boolean(value(event, "allDay", false)))
            return qsTr("All day")
        const match = String(value(event, "start", "")).match(/T(\d{2}:\d{2})/)
        return match ? match[1] : "--:--"
    }

    function updateEventRange() {
        const first = dateForCell(0)
        const last = dateForCell(41)
        pim.setEventRange(dateKey(first), dateKey(last))
    }

    function showToday() {
        visibleMonth = new Date()
        selectedDate = new Date()
        Qt.callLater(updateEventRange)
    }

    onVisibleMonthChanged: Qt.callLater(updateEventRange)

    PimClient { id: pim }

    Connections {
        target: pim

        function onOperationSucceeded(operation, itemId) {
            if (operation === "createEvent" || operation === "updateEvent"
                    || operation === "removeEvent")
                Qt.callLater(root.updateEventRange)
        }
    }

    EventEditorDialog {
        id: eventEditor

        parent: root.contentItem
        onSaveRequested: function(uid, event) {
            if (uid.length > 0)
                pim.updateEvent(uid, event)
            else
                pim.createEvent(event)
        }
        onDeleteRequested: uid => pim.removeEvent(uid)
    }

    Shortcut {
        sequence: StandardKey.New
        onActivated: eventEditor.openForDate(root.selectedDate)
    }

    Shortcut {
        sequence: "Ctrl+T"
        onActivated: root.showToday()
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

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Month")
                    symbol: "▦"
                    checked: true
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Today")
                    symbol: "◉"
                    onClicked: root.showToday()
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
                    enabled: false
                }

                Item { Layout.fillHeight: true }

                Label {
                    Layout.fillWidth: true
                    text: pim.connected
                        ? qsTr("Local iCalendar service connected")
                        : qsTr("Waiting for the local PIM service")
                    color: pim.connected ? AppTheme.positive : AppTheme.warning
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("CalDAV and cloud accounts are not enabled in version 1.")
                    color: AppTheme.mutedText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 10
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: AppTheme.pageMargin
            spacing: 14

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 2

                    Label {
                        text: Qt.formatDate(root.visibleMonth, "MMMM yyyy")
                        color: AppTheme.text
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    Label {
                        text: qsTr("%n event(s) in this view", "", pim.occurrences.length)
                        color: AppTheme.mutedText
                    }
                }

                Item { Layout.fillWidth: true }

                BusyIndicator {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    running: pim.busy
                    visible: running
                }

                Button {
                    text: "‹"
                    Accessible.name: qsTr("Previous month")
                    onClicked: root.visibleMonth = root.monthDate(-1)
                }

                Button {
                    text: qsTr("Today")
                    onClicked: root.showToday()
                }

                Button {
                    text: "›"
                    Accessible.name: qsTr("Next month")
                    onClicked: root.visibleMonth = root.monthDate(1)
                }

                Button {
                    text: qsTr("New event")
                    highlighted: true
                    enabled: pim.connected && pim.writable
                    onClicked: eventEditor.openForDate(root.selectedDate)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: errorText.implicitHeight + 20
                radius: AppTheme.smallRadius
                color: AppTheme.withAlpha(AppTheme.warning, AppTheme.dark ? 0.16 : 0.12)
                border.width: 1
                border.color: AppTheme.withAlpha(AppTheme.warning, 0.35)
                visible: pim.errorMessage.length > 0 && pim.ready

                Label {
                    id: errorText
                    anchors.fill: parent
                    anchors.margins: 10
                    text: pim.errorMessage
                    color: AppTheme.text
                    wrapMode: Text.WordWrap
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
                            readonly property var dayEvents: root.eventsForDate(cellDate)

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 76
                            leftPadding: 8
                            rightPadding: 8
                            topPadding: 7
                            bottomPadding: 6
                            opacity: inVisibleMonth ? 1 : 0.42
                            Accessible.name: Qt.formatDate(cellDate, Locale.LongFormat)
                            onClicked: root.selectedDate = cellDate

                            contentItem: ColumnLayout {
                                spacing: 2

                                Label {
                                    Layout.fillWidth: true
                                    text: String(dayButton.cellDate.getDate())
                                    color: dayButton.today ? AppTheme.accent : AppTheme.text
                                    font.weight: dayButton.today || dayButton.selected
                                        ? Font.DemiBold : Font.Normal
                                }

                                Repeater {
                                    model: dayButton.dayEvents.slice(0, 2)

                                    delegate: Rectangle {
                                        id: eventChip

                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 17
                                        radius: 4
                                        color: AppTheme.withAlpha(AppTheme.accent,
                                            AppTheme.dark ? 0.24 : 0.15)

                                        Label {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 4
                                            text: String(root.value(eventChip.modelData,
                                                "title", qsTr("Untitled")))
                                            color: AppTheme.text
                                            font.pixelSize: 9
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("+%1 more").arg(dayButton.dayEvents.length - 2)
                                    color: AppTheme.mutedText
                                    font.pixelSize: 9
                                    visible: dayButton.dayEvents.length > 2
                                }

                                Item { Layout.fillHeight: true }
                            }

                            background: Rectangle {
                                radius: AppTheme.smallRadius
                                color: dayButton.selected
                                    ? AppTheme.withAlpha(AppTheme.accent,
                                        AppTheme.dark ? 0.20 : 0.12)
                                    : (dayButton.hovered ? AppTheme.cardHover : "transparent")
                                border.width: dayButton.today || dayButton.activeFocus ? 1 : 0
                                border.color: AppTheme.withAlpha(AppTheme.accent, 0.64)
                            }
                        }
                    }
                }
            }

            KosCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 150

                contentItem: ColumnLayout {
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: Qt.formatDate(root.selectedDate, Locale.LongFormat)
                            color: AppTheme.text
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: qsTr("Add")
                            flat: true
                            enabled: pim.connected && pim.writable
                            onClicked: eventEditor.openForDate(root.selectedDate)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: qsTr("No events for this day")
                        color: AppTheme.mutedText
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        visible: root.selectedEvents.length === 0
                    }

                    ListView {
                        id: dayAgenda
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.selectedEvents.length > 0
                        clip: true
                        spacing: 3
                        model: root.selectedEvents

                        delegate: ItemDelegate {
                            id: agendaItem

                            required property var modelData
                            width: dayAgenda.width
                            implicitHeight: 42
                            onClicked: eventEditor.openForEvent(modelData)

                            contentItem: RowLayout {
                                spacing: 10

                                Label {
                                    Layout.preferredWidth: 58
                                    text: root.eventTime(agendaItem.modelData)
                                    color: AppTheme.accent
                                    font.weight: Font.DemiBold
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: String(root.value(agendaItem.modelData,
                                        "title", qsTr("Untitled event")))
                                    color: AppTheme.text
                                    elide: Text.ElideRight
                                }

                                Label {
                                    text: String(root.value(agendaItem.modelData, "location", ""))
                                    color: AppTheme.mutedText
                                    visible: text.length > 0
                                    elide: Text.ElideRight
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
