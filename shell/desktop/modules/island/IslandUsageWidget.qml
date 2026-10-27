import QtQuick
import "../../../shared/qml/i18n"
import qs.desktop.modules.deskcenter

// IslandUsageWidget — today's screen time, the way Notchy's first home card
// shows it.
//
// The data is the shell's own activity snapshot (kos-data-service accounts
// foreground time per application), so this card costs the service nothing
// new: it reads the same snapshot the DeskCenter's activity card reads.
//
// Notchy is closed-source and its licence forbids derivative works, so this
// is a clean-room implementation of the idea from the observable behaviour,
// not a port of its code.
Rectangle {
    id: root

    required property string widgetId

    readonly property var apps: ActivityUsageService.todayApps()
    readonly property real totalSeconds: {
        let sum = 0
        for (let i = 0; i < apps.length; i++)
            sum += Number(apps[i].seconds) || 0
        return sum
    }

    // The longest app sets the bar scale, so the bars are comparable to each
    // other rather than to the total.
    readonly property real maxSeconds: apps.length > 0
        ? Math.max(1, Number(apps[0].seconds) || 0) : 1

    function formatDuration(seconds) {
        const total = Math.max(0, Math.round(seconds))
        const hours = Math.floor(total / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        if (hours > 0)
            return hours + "h " + minutes + "m"
        return minutes + "m"
    }

    color: "transparent"

    Column {
        anchors { fill: parent }
        spacing: 3

        Item {
            width: parent.width
            height: 12

            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: I18n.tr("Screen time")
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 9
            }

            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: root.formatDuration(root.totalSeconds)
                color: Qt.rgba(1, 1, 1, 0.75)
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }

        Repeater {
            model: root.apps.slice(0, 3)

            delegate: Item {
                required property var modelData

                width: parent.width
                height: 20

                Text {
                    anchors {
                        left: parent.left
                        right: durationText.left
                        rightMargin: 4
                        verticalCenter: parent.verticalCenter
                    }
                    text: modelData.name || modelData.id
                    color: Qt.rgba(1, 1, 1, 0.72)
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                // The bar: how long this app held the screen, relative to
                // the longest one.
                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        bottomMargin: 1
                    }
                    height: 2
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.08)

                    Rectangle {
                        width: Math.round(parent.width
                            * Math.max(0, Math.min(1, Number(modelData.seconds) / root.maxSeconds)))
                        height: parent.height
                        radius: parent.radius
                        color: Qt.rgba(0.29, 0.87, 0.5, 0.85)
                    }
                }

                Text {
                    id: durationText
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: root.formatDuration(Number(modelData.seconds) || 0)
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 9
                }
            }
        }

        Text {
            width: parent.width
            visible: root.apps.length === 0
            text: I18n.tr("No screen time yet")
            color: Qt.rgba(1, 1, 1, 0.3)
            font.pixelSize: 9
            elide: Text.ElideRight
        }
    }
}
