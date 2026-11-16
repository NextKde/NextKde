import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import qs.desktop.modules.weather
import "../../../Kos/Ui"

// One hover surface for the Dock information cards.
//
// It is anchored to the card under the pointer (DockInfoCarousel passes a
// zero-width Item tracking that card), not to the whole information slot, so
// the panel reads as belonging to the card it describes. Moving between cards
// swaps the content in place instead of closing and reopening.
//
AnimatedPopupWindow {
    id: popup

    property Item anchorItem: null
    // DockInfoCarousel's page ids; -1 means "nothing to show".
    property int page: -1
    property bool pointerInside: false

    motionOrigin: Item.Bottom
    openDuration: DockAnimation.infoPopupEntranceDuration
    // Geometry is decided up front: a PopupWindow does not reflow its content
    // the way an in-window Item does.
    implicitWidth: 288
    implicitHeight: popup.rowCount > 0 ? popup.rowCount * 26 + 62 : 1
    color: "transparent"
    grabFocus: false
    BackgroundEffect.blurRegion: popup.visible && popup.revealProgress > 0
        && AppearanceTokens.surface.usesKwinBlur ? infoSurface.blurRegion : null

    PopupAnchorBinding { popupAnchor: popup.anchor; sourceItem: popup.anchorItem }

    anchor {
        edges: Edges.Top
        gravity: Edges.Top
        margins.top: -12
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    DateProjection {
        id: calendarClock
        sourceDate: clock.date
    }

    readonly property var rows: detailRows()
    readonly property int rowCount: rows.length
    readonly property string title: {
        if (popup.page === 2)
            return I18n.tr("Clock")
        if (popup.page === 1)
            return I18n.tr("Weather")
        if (popup.page === 3)
            return I18n.tr("Resource Usage")
        return ""
    }

    function requestClose() { hide() }

    function percent(value) {
        return Math.round(Math.max(0, Math.min(1, Number(value))) * 100) + "%"
    }

    function thermalValue(milliC) {
        return Number(milliC) >= 0 ? Math.round(Number(milliC) / 1000) + "°" : "--°"
    }

    function weekdayName(date) {
        return [I18n.tr("Sun"), I18n.tr("Mon"), I18n.tr("Tue"), I18n.tr("Wed"),
            I18n.tr("Thu"), I18n.tr("Fri"), I18n.tr("Sat")][date.getDay()]
    }

    function detailRows() {
        // Clock: the card can hide seconds, the date or the solar rows, but a
        // hover is an explicit request for everything it knows.
        if (popup.page === 2) {
            return [
                { label: I18n.tr("Time"),
                    value: I18n.fmt(clock.date, "HH:mm:ss") },
                { label: I18n.tr("Date"),
                    value: I18n.fmt(calendarClock.dayDate, I18n.tr("MMMM d"))
                        + " " + popup.weekdayName(calendarClock.dayDate) },
                { label: I18n.tr("Sunrise"), value: WeatherService.sunriseTime },
                { label: I18n.tr("Sunset"), value: WeatherService.sunsetTime },
            ]
        }
        if (popup.page === 1) {
            return [
                { label: I18n.tr("Weather"), value: WeatherService.available
                    ? WeatherService.conditionText(WeatherService.weatherCode)
                    : "--" },
                { label: I18n.tr("Temperature"), value: WeatherService.temperature },
                { label: I18n.tr("Feels like"), value: WeatherService.apparentTemperature },
                { label: I18n.tr("Humidity"), value: WeatherService.humidity },
                { label: I18n.tr("Wind speed"), value: WeatherService.windSpeed },
            ]
        }
        if (popup.page === 3) {
            return [
                { label: I18n.tr("Avg temperature"),
                    value: popup.thermalValue(MetricsService.currentMilliC) },
                { label: I18n.tr("Max temperature"),
                    value: popup.thermalValue(MetricsService.maximum5MinuteMilliC) },
                { label: "CPU", value: popup.percent(MetricsService.cpuUsage) },
                { label: I18n.tr("Memory"),
                    value: MetricsService.memoryTotalBytes > 0
                        ? popup.percent(MetricsService.memoryUsedBytes
                            / MetricsService.memoryTotalBytes) : "--" },
                { label: I18n.tr("Storage"),
                    value: MetricsService.diskTotalBytes > 0
                        ? popup.percent(MetricsService.diskUsedBytes
                            / MetricsService.diskTotalBytes) : "--" },
            ]
        }
        return []
    }

    Item {
        id: panel
        anchors.fill: parent
        // Grow out of the anchor: the panel sits above the card, so it scales
        // from its own bottom edge.
        transformOrigin: Item.Bottom

        LiquidGlassPanel {
            id: infoSurface
            anchors.fill: parent
            radius: 18
            cornerExponent: 2.35
            baseColor: ThemeService.backgroundColor
            surfaceOpacity: 1.0
            scrimEnabled: AppearanceTokens.surface.usesBackdrop
            scrimLevel: "subtle"
        }

        ColumnLayout {
            anchors {
                fill: parent
                leftMargin: 16
                rightMargin: 16
                topMargin: 12
                bottomMargin: 12
            }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                GlassText {
                    text: popup.title
                    color: ThemeService.foregroundColor
                    font {
                        family: AppearanceTokens.typography.textFamily
                        pixelSize: 14
                        weight: Font.DemiBold
                    }
                }
                GlassText {
                    // Only the weather card has a scope worth naming.
                    visible: popup.page === 1
                    text: WeatherService.cityName
                    color: ThemeService.foregroundColor
                    opacity: 0.62
                    font {
                        family: AppearanceTokens.typography.textFamily
                        pixelSize: 11
                        weight: Font.Medium
                    }
                }
                Item { Layout.fillWidth: true; height: 1 }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: ThemeService.foregroundColor
                opacity: 0.12
            }

            Repeater {
                model: popup.rows

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    spacing: 12

                    GlassText {
                        text: modelData.label
                        color: ThemeService.foregroundColor
                        opacity: 0.62
                        font {
                            family: AppearanceTokens.typography.textFamily
                            pixelSize: 12
                            weight: Font.Medium
                        }
                    }
                    Item { Layout.fillWidth: true; height: 1 }
                    GlassText {
                        text: modelData.value
                        color: ThemeService.foregroundColor
                        font {
                            family: AppearanceTokens.typography.textFamily
                            pixelSize: 13
                            weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }

    HoverHandler {
        onHoveredChanged: popup.pointerInside = hovered
    }
}
