import QtQuick
import "../../../shared/qml/i18n"

// IslandBatteryWidget — ported from NookX's BatteryLevelView /
// BatteryIconView.
//
// The original reads IOKit power sources. NextKde's platform contract has no
// battery operation, and QML must not bypass the service boundary to read
// /sys directly, so the widget renders its frame with an explicit
// "no data source" state instead of a fabricated percentage. If a battery
// operation is ever added to the platform contract, this widget is where it
// plugs in.
Rectangle {
    id: root

    color: "transparent"

    Column {
        anchors.centerIn: parent
        spacing: 3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "--"
            color: Qt.rgba(1, 1, 1, 0.35)
            font.pixelSize: 20
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("No battery data source")
            color: Qt.rgba(1, 1, 1, 0.45)
            font.pixelSize: 9
        }
    }
}
