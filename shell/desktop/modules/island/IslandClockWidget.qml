import QtQuick

// IslandClockWidget — ported from NookX's ClockView / DayProgressView.
// A large clock, the date, and the day-progress bar the original shows
// under the time.
Rectangle {
    id: root

    color: "transparent"

    property string nowText: ""
    property string dateText: ""

    // Fraction of the day elapsed, 0..1 — the original's DayProgressView.
    // Driven by the timer below, not a binding: `new Date()` inside a
    // binding is not reactive, so the bar would freeze at its first value.
    property real dayProgress: 0

    function refresh() {
        const now = new Date()
        root.nowText = Qt.formatTime(now, "HH:mm")
        root.dateText = Qt.formatDate(now, "M月d日 dddd")
        root.dayProgress = (now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()

    Column {
        anchors.centerIn: parent
        spacing: 3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.nowText
            color: "white"
            font.pixelSize: 20
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 9
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 80
            height: 3
            radius: 1.5
            color: Qt.rgba(1, 1, 1, 0.12)

            Rectangle {
                width: parent.width * root.dayProgress
                height: parent.height
                radius: 1.5
                color: Qt.rgba(0.29, 0.87, 0.5, 0.85)
            }
        }
    }
}
