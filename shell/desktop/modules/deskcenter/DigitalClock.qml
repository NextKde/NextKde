import QtQuick
import qs.desktop.modules.common

Item {
    id: digitalClock
    required property date currentDate
    anchors.fill: parent
    anchors.margins: 14

    Column {
        anchors.centerIn: parent
        width: parent.width * 0.9
        spacing: Math.max(4, digitalClock.height * 0.025)

        Text {
            width: parent.width
            height: Math.max(24, digitalClock.height * 0.36)
            objectName: "desktop-clock-time"
            text: Qt.formatDateTime(digitalClock.currentDate, "HH:mm:ss")
            color: AppearanceTokens.content.ink("#ffffff")
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: "Noto Sans Mono"
            font.weight: Font.DemiBold
            font.pixelSize: Math.max(16, Math.min(digitalClock.width * 0.19, digitalClock.height * 0.27))
            fontSizeMode: Text.Fit
            minimumPixelSize: 12
        }

        Text {
            width: parent.width
            height: Math.max(16, digitalClock.height * 0.18)
            objectName: "desktop-clock-date"
            text: Qt.formatDateTime(digitalClock.currentDate, "yyyy-MM-dd") + " "
                + ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][digitalClock.currentDate.getDay()]
            color: AppearanceTokens.content.ink(Qt.rgba(1, 1, 1, 0.82), 0.82)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: "Noto Sans"
            font.pixelSize: Math.max(10, Math.min(18, digitalClock.height * 0.12))
            fontSizeMode: Text.Fit
            minimumPixelSize: 9
        }
    }
}
