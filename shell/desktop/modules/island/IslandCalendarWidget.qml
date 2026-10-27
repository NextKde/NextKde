import QtQuick
import QtQuick.Layouts

// IslandCalendarWidget — ported from NookX's CalendarView: a month grid with
// a Sunday-first header (S M T W T F S, same as the original) and the
// current day highlighted. The viewed month is kept in widget state so it
// survives island reloads.
Rectangle {
    id: root

    required property string widgetId

    readonly property var saved: IslandConfigService.widgetState[widgetId] || ({})

    property int viewYear: 0
    property int viewMonth: 0

    // The current day, refreshed by a timer. A binding that calls
    // `new Date()` has no reactive dependency, so it would freeze on the
    // day the component was created and the "today" highlight would be
    // wrong after midnight.
    property var today: new Date()

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.today = new Date()
    }
    readonly property var dayLetters: ["S", "M", "T", "W", "T", "F", "S"]

    color: "transparent"

    function monthLength(year, month) {
        return new Date(year, month + 1, 0).getDate()
    }

    // Leading blanks so the 1st lands under its weekday letter.
    readonly property int leadingBlanks: {
        if (viewYear === 0)
            return 0
        return new Date(viewYear, viewMonth, 1).getDay()
    }
    readonly property int daysInMonth: {
        if (viewYear === 0)
            return 0
        return monthLength(viewYear, viewMonth)
    }

    function shiftMonth(delta) {
        let m = viewMonth + delta
        let y = viewYear
        if (m < 0) { m = 11; y -= 1 }
        if (m > 11) { m = 0; y += 1 }
        viewYear = y
        viewMonth = m
        IslandConfigService.setWidgetState(widgetId, {
            viewYear: viewYear,
            viewMonth: viewMonth
        })
    }

    // The stored configuration arrives asynchronously. Reading the saved
    // month before it lands would silently show the current month instead
    // of the one the user navigated to.
    function applySavedMonth() {
        if (!IslandConfigService.ready)
            return
        const now = new Date()
        viewYear = Number(saved.viewYear) || now.getFullYear()
        viewMonth = Number.isInteger(saved.viewMonth) ? saved.viewMonth : now.getMonth()
    }

    Component.onCompleted: applySavedMonth()

    Connections {
        target: IslandConfigService
        function onReadyChanged() { root.applySavedMonth() }
    }

    Column {
        anchors.centerIn: parent
        spacing: 4

        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            Text {
                text: "<"
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 10
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.shiftMonth(-1)
                }
            }

            Text {
                text: root.viewYear + "/" + (root.viewMonth + 1)
                color: Qt.rgba(1, 1, 1, 0.85)
                font.pixelSize: 10
                font.bold: true
            }

            Text {
                text: ">"
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 10
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.shiftMonth(1)
                }
            }
        }

        Row {
            spacing: 2
            Repeater {
                model: root.dayLetters
                delegate: Text {
                    required property var modelData
                    width: 13
                    text: modelData
                    color: Qt.rgba(1, 1, 1, 0.4)
                    font.pixelSize: 8
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 7
            spacing: 2

            Repeater {
                model: root.leadingBlanks + root.daysInMonth
                delegate: Rectangle {
                    required property int index
                    readonly property int day: index - root.leadingBlanks + 1
                    readonly property bool isToday: day >= 1
                        && root.viewYear === root.today.getFullYear()
                        && root.viewMonth === root.today.getMonth()
                        && day === root.today.getDate()
                    width: 13
                    height: 13
                    radius: 4
                    color: isToday ? Qt.rgba(0.29, 0.87, 0.5, 0.9) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        visible: parent.day >= 1
                        text: parent.day >= 1 ? parent.day : ""
                        color: isToday ? Qt.rgba(0.05, 0.25, 0.16, 1) : Qt.rgba(1, 1, 1, 0.7)
                        font.pixelSize: 8
                    }
                }
            }
        }
    }
}
