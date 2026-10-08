import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import qs.desktop.modules.dock

AnimatedPopupWindow {
    id: popup

    property Item anchorItem: null
    property bool pointerInside: popupMouse.containsMouse
    motionOrigin: Item.Bottom

    implicitWidth: 336
    implicitHeight: 196
    color: "transparent"
    grabFocus: false

    anchor {
        item: popup.anchorItem
        edges: Edges.Top
        gravity: Edges.Top
        margins.top: -10
    }

    LiquidGlassPanel {
        anchors.fill: parent
        radius: 18
        cornerExponent: AppearanceTokens.shape.cornerExponent
        baseColor: ThemeService.backgroundColor
        ambientPrimary: WeatherTheme.theme(WeatherService.weatherCode, WeatherService.isDay).primary
        ambientSecondary: WeatherTheme.theme(WeatherService.weatherCode, WeatherService.isDay).secondary
        ambientStrength: 0.45

        MouseArea {
            id: popupMouse
            anchors.fill: parent
            hoverEnabled: true
        }

        Row {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
            spacing: 14
            Text {
                text: WeatherService.conditionSymbol(WeatherService.weatherCode, WeatherService.isDay)
                color: ThemeService.foregroundColor
                font.pixelSize: 54
                width: 60
                horizontalAlignment: Text.AlignHCenter
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { text: WeatherService.cityName; color: ThemeService.foregroundColor; font.pixelSize: 14 }
                Text { text: WeatherService.temperature; color: ThemeService.foregroundColor; font.pixelSize: 32; font.weight: Font.Bold }
                Text { text: WeatherService.conditionText(WeatherService.weatherCode) + " · " + I18n.tr("Feels like %1").arg(WeatherService.apparentTemperature); color: ThemeService.foregroundColor; opacity: 0.72; font.pixelSize: 12 }
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                topMargin: 112
                margins: 16
            }
            height: 1
            color: ThemeService.dividerColor
        }
        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
            spacing: 20
            Repeater {
                model: [
                    { label: I18n.tr("Humidity"), value: WeatherService.humidity },
                    { label: I18n.tr("Wind speed"), value: WeatherService.windSpeed },
                    { label: I18n.tr("Wind direction"), value: WeatherService.windDirection }
                ]
                delegate: Column {
                    required property var modelData
                    spacing: 3
                    Text { text: modelData.label; color: ThemeService.foregroundColor; opacity: 0.55; font.pixelSize: 11 }
                    Text { text: modelData.value; color: ThemeService.foregroundColor; font.pixelSize: 13 }
                }
            }
            Item { width: 1; height: 1 }
            Text { text: WeatherService.errorMessage || (WeatherService.stale ? I18n.tr("Cached data") : I18n.tr("Just updated")); color: ThemeService.foregroundColor; opacity: 0.5; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
