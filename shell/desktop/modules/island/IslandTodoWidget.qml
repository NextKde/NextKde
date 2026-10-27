import QtQuick

// IslandTodoWidget — the week habit grid, ported from NookX's TodoView
// (the "S M T W T F S" card with a filled square per completed day).
//
// State lives in IslandConfigService.widgetState["todo"]:
//   { weekKey: "2026-W43", days: [false x 7] }
// A new week resets the grid, which is what the original's per-week card
// does. Tapping a square toggles that day and persists immediately.
Rectangle {
    id: root

    required property string widgetId

    readonly property var saved: IslandConfigService.widgetState[widgetId] || ({})
    readonly property var days: {
        const raw = saved.days
        return (Array.isArray(raw) && raw.length === 7) ? raw.slice()
                                                        : [false, false, false, false, false, false, false]
    }
    readonly property int doneCount: {
        let n = 0
        for (let i = 0; i < 7; i++)
            if (days[i])
                n++
        return n
    }

    // The original's header is S M T W T F S (Sunday first).
    readonly property var dayLetters: ["S", "M", "T", "W", "T", "F", "S"]

    color: "transparent"

    // Sunday-based week key, so the grid rolls over with the header.
    function weekKeyFor(date) {
        const d = new Date(date.getFullYear(), date.getMonth(), date.getDate())
        d.setDate(d.getDate() - d.getDay())
        const yearStart = new Date(d.getFullYear(), 0, 1)
        const week = Math.floor((d - yearStart) / (7 * 24 * 3600 * 1000)) + 1
        return d.getFullYear() + "-W" + week
    }

    function toggleDay(index) {
        const next = days.slice()
        next[index] = !next[index]
        IslandConfigService.setWidgetState(widgetId, {
            weekKey: saved.weekKey || weekKeyFor(new Date()),
            days: next
        })
    }

    // The stored configuration arrives asynchronously. Resetting the week
    // before it arrives would write an empty week over the stored one and
    // throw away the user's ticks, so the reset waits for the store.
    function resetIfStale() {
        if (!IslandConfigService.ready)
            return
        const key = weekKeyFor(new Date())
        if (saved.weekKey !== key)
            IslandConfigService.setWidgetState(widgetId, {
                weekKey: key,
                days: [false, false, false, false, false, false, false]
            })
    }

    Component.onCompleted: resetIfStale()

    Connections {
        target: IslandConfigService
        function onReadyChanged() { root.resetIfStale() }
    }

    Column {
        anchors.centerIn: parent
        spacing: 5

        Row {
            spacing: 3
            Repeater {
                model: root.dayLetters
                delegate: Text {
                    required property var modelData
                    width: 15
                    text: modelData
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Row {
            spacing: 3
            Repeater {
                model: 7
                delegate: Rectangle {
                    required property int index
                    readonly property bool done: root.days[index]
                    width: 15
                    height: 15
                    radius: 5
                    color: done ? Qt.rgba(0.29, 0.87, 0.5, 0.92) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    border.color: done ? Qt.rgba(0.29, 0.87, 0.5, 0.35) : Qt.rgba(1, 1, 1, 0.10)

                    Text {
                        anchors.centerIn: parent
                        visible: parent.done
                        text: "\u2713"
                        color: Qt.rgba(0.05, 0.25, 0.16, 1)
                        font.pixelSize: 9
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.toggleDay(index)
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.doneCount + " / 7"
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 9
        }
    }
}
