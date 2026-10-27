import QtQuick
import qs.desktop.modules.common
import "../../../shared/qml/i18n"

// IslandSystemWidget — the port of NookX's 系统面板 widget.
//
// The original's catalogue carries a "systemPanel" entry alongside the
// calendar/weather, todo, photo, pomodoro, note and shortcut widgets (its
// enabled-widget map names them explicitly). This is the one of that set the
// shell can already serve: MetricsService owns a single sampled snapshot of
// CPU, memory and disk for the Bar, the Dock and the DeskCenter, so the island
// reads the same numbers instead of polling anything of its own.
Item {
    id: root

    required property string widgetId

    readonly property var metrics: MetricsService
    readonly property real cpu: Math.max(0, Math.min(1, metrics.cpuUsage))

    function share(used, total) {
        return total > 0 ? Math.max(0, Math.min(1, used / total)) : 0
    }

    // 0 = CPU, 1 = memory, 2 = disk. Kept as a function of the row index so
    // that only the value bindings depend on the metrics snapshot.
    function ratioFor(index) {
        switch (index) {
        case 0: return root.cpu
        case 1: return root.share(metrics.memoryUsedBytes, metrics.memoryTotalBytes)
        case 2: return root.share(metrics.diskUsedBytes, metrics.diskTotalBytes)
        default: return 0
        }
    }

    Column {
        anchors { fill: parent; topMargin: 2; bottomMargin: 2 }
        spacing: Math.max(4, Math.round(height * 0.06))

        Repeater {
            // A constant model, not an array built from the metrics: an array
            // literal that reads them makes a new model every ten seconds, and
            // a Repeater answers a new model by destroying and rebuilding every
            // delegate. The bars then appear at their final width and the
            // Behaviour below never has anything to animate.
            model: [I18n.tr("CPU"), I18n.tr("Memory"), I18n.tr("Disk")]

            delegate: Item {
                required property string modelData
                required property int index

                readonly property real ratio: root.ratioFor(index)

                width: parent.width
                height: Math.round(root.height * 0.26)

                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: Math.round(root.width * 0.34)
                    text: modelData
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                // The track and its fill. A bar rather than a number alone:
                // three percentages in a column read as text, three bars read
                // as a panel.
                Rectangle {
                    id: track
                    anchors {
                        left: parent.left
                        right: valueText.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: Math.round(root.width * 0.36)
                        rightMargin: 8
                    }
                    height: 5
                    radius: 2.5
                    color: Qt.rgba(1, 1, 1, 0.12)

                    Rectangle {
                        width: Math.round(parent.width * ratio)
                        height: parent.height
                        radius: parent.radius
                        color: ratio > 0.85
                            ? Qt.rgba(0.95, 0.45, 0.35, 0.95)
                            : Qt.rgba(0.29, 0.87, 0.5, 0.95)

                        Behavior on width { NumberAnimation { duration: 220 } }
                    }
                }

                Text {
                    id: valueText
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: Math.round(ratio * 100) + "%"
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.pixelSize: 10
                }
            }
        }
    }
}
