import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
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
// Visibility is animated: DockModelService flips `visible`, and this panel
// eases its own content in from the anchor with a spring, then eases out
// before the window is actually hidden.
PopupWindow {
    id: popup

    property Item anchorItem: null
    // DockInfoCarousel's page ids; -1 means "nothing to show".
    property int page: -1
    property bool pointerInside: false

    visible: false
    // Geometry is decided up front: a PopupWindow does not reflow its content
    // the way an in-window Item does.
    implicitWidth: 288
    implicitHeight: popup.rowCount > 0 ? popup.rowCount * 26 + 62 : 1
    color: "transparent"
    grabFocus: false

    anchor {
        item: popup.anchorItem
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
            return "时钟"
        if (popup.page === 1)
            return "天气"
        if (popup.page === 3)
            return "资源占用"
        return ""
    }

    // Spring reveal. 0 → 1 grows out of the anchor; 1 → 0 folds back into it.
    property real reveal: 0
    property bool closing: false

    Behavior on reveal {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutBack
            easing.overshoot: 1.35
        }
    }

    onVisibleChanged: {
        if (visible) {
            closing = false
            reveal = 1
        } else {
            reveal = 0
        }
    }

    // Ask to be hidden. The window stays mapped until the fold-out finishes,
    // otherwise the panel would blink away instead of animating out.
    function requestClose() {
        if (!visible || closing)
            return
        closing = true
        reveal = 0
        closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: 280
        repeat: false
        onTriggered: {
            if (popup.closing)
                popup.visible = false
        }
    }

    function percent(value) {
        return Math.round(Math.max(0, Math.min(1, Number(value))) * 100) + "%"
    }

    function thermalValue(milliC) {
        return Number(milliC) >= 0 ? Math.round(Number(milliC) / 1000) + "°" : "--°"
    }

    function weekdayName(date) {
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][date.getDay()]
    }

    function detailRows() {
        // Clock: the card can hide seconds, the date or the solar rows, but a
        // hover is an explicit request for everything it knows.
        if (popup.page === 2) {
            return [
                { label: "时间",
                    value: Qt.formatDateTime(clock.date, "HH:mm:ss") },
                { label: "日期",
                    value: Qt.formatDateTime(calendarClock.dayDate, "M月d日")
                        + " " + popup.weekdayName(calendarClock.dayDate) },
                { label: "日出", value: WeatherService.sunriseTime },
                { label: "日落", value: WeatherService.sunsetTime },
            ]
        }
        if (popup.page === 1) {
            return [
                { label: "天气", value: WeatherService.available
                    ? WeatherService.conditionText(WeatherService.weatherCode)
                    : "--" },
                { label: "气温", value: WeatherService.temperature },
                { label: "体感", value: WeatherService.apparentTemperature },
                { label: "湿度", value: WeatherService.humidity },
                { label: "风速", value: WeatherService.windSpeed },
            ]
        }
        if (popup.page === 3) {
            return [
                { label: "平均温度",
                    value: popup.thermalValue(MetricsService.currentMilliC) },
                { label: "最高温度",
                    value: popup.thermalValue(MetricsService.maximum5MinuteMilliC) },
                { label: "CPU", value: popup.percent(MetricsService.cpuUsage) },
                { label: "内存",
                    value: MetricsService.memoryTotalBytes > 0
                        ? popup.percent(MetricsService.memoryUsedBytes
                            / MetricsService.memoryTotalBytes) : "--" },
                { label: "存储",
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
        opacity: popup.reveal
        scale: 0.86 + 0.14 * popup.reveal
        transformOrigin: Item.Bottom

        LiquidGlassPanel {
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

                Text {
                    text: popup.title
                    color: ThemeService.foregroundColor
                    font {
                        family: "Noto Sans CJK SC"
                        pixelSize: 14
                        weight: Font.DemiBold
                    }
                }
                Text {
                    // Only the weather card has a scope worth naming.
                    visible: popup.page === 1
                    text: WeatherService.cityName
                    color: ThemeService.foregroundColor
                    opacity: 0.62
                    font {
                        family: "Noto Sans CJK SC"
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

                    Text {
                        text: modelData.label
                        color: ThemeService.foregroundColor
                        opacity: 0.62
                        font {
                            family: "Noto Sans CJK SC"
                            pixelSize: 12
                            weight: Font.Medium
                        }
                    }
                    Item { Layout.fillWidth: true; height: 1 }
                    Text {
                        text: modelData.value
                        color: ThemeService.foregroundColor
                        font {
                            family: "Noto Sans CJK SC"
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
