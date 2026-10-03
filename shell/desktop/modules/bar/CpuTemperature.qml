import QtQuick
import qs.desktop.modules.dock
import qs.desktop.modules.common

// Compact CPU thermal indicator. Sampling, sensor enumeration, and the rolling
// history now live in kos-data-service; this indicator only formats the
// shared MetricsService snapshot (updated every ten seconds by the service).
// The hover tooltip and click-open sensor dashboard live in
// TemperatureSensorPopups, shared with the Dock temperature page.
Item {
    id: root

    property bool dockHosted: false

    property bool available: MetricsService.currentMilliC >= 0
        && MetricsService.maximum5MinuteMilliC >= 0
    readonly property int currentC: Math.round(MetricsService.currentMilliC / 1000)
    readonly property int maximum5MinuteC: Math.round(
        MetricsService.maximum5MinuteMilliC / 1000)

    implicitWidth: available ? content.implicitWidth : 0
    implicitHeight: 20
    width: implicitWidth
    height: implicitHeight
    visible: available

    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        // Reuse the Dock temperature page's dedicated glyph so the entry
        // point and its Stack page always identify the feature the same way.
        DockMetricGlyph {
            width: 19
            height: 19
            kind: "temperature"
            glyphColor: ThemeService.foregroundColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            spacing: 0
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: "平均温度 " + root.currentC + "°"
                color: ThemeService.foregroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.40)
                font {
                    family: "Noto Sans CJK SC, sans-serif"
                    pixelSize: 9
                    weight: Font.Normal
                }
            }

            Text {
                text: "最高温度 " + root.maximum5MinuteC + "°"
                color: ThemeService.foregroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.40)
                font {
                    family: "Noto Sans CJK SC, sans-serif"
                    pixelSize: 9
                    weight: Font.Normal
                }
            }
        }
    }

    TemperatureSensorPopups {
        anchors.fill: parent
        dockHosted: root.dockHosted
    }
}
