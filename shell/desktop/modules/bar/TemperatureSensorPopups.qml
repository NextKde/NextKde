import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Shared hover tooltip and click-open sensor dashboard for every compact
// thermal entry point (standalone Bar summary and the Dock carousel page).
// The host fills this overlay; sampling still lives in kos-data-service via
// MetricsService, and network rates come from NetworkService's snapshot.
Item {
    id: root

    // Bottom Dock hosts grow their popups upward; the standalone Bar grows
    // them downward. Only the bottom dock hosts this component today.
    property bool dockHosted: false

    // Dock hosts follow the other info cards (DockMusicPlayer contract):
    // hovering the card opens the dashboard after a 420 ms dwell, and
    // leaving closes it 260 ms later unless the pointer moved into the
    // popup itself. The Bar keeps the hover tooltip + click toggle instead.
    property bool popupPointerInside: false
    onPopupPointerInsideChanged: {
        if (!root.dockHosted)
            return
        if (popupPointerInside)
            dashboardCloseDelay.stop()
        else if (!hoverArea.containsMouse)
            dashboardCloseDelay.restart()
    }

    readonly property bool available: MetricsService.currentMilliC >= 0
        && MetricsService.maximum5MinuteMilliC >= 0
    readonly property int currentC: Math.round(MetricsService.currentMilliC / 1000)
    readonly property int maximum5MinuteC: Math.round(
        MetricsService.maximum5MinuteMilliC / 1000)
    readonly property real memoryUsage: MetricsService.memoryTotalBytes > 0
        ? MetricsService.memoryUsedBytes / MetricsService.memoryTotalBytes : 0
    readonly property real diskUsage: MetricsService.diskTotalBytes > 0
        ? MetricsService.diskUsedBytes / MetricsService.diskTotalBytes : 0

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // On the Dock the hover itself drives the dashboard; the Bar's click
        // toggle must not fight the hover timers by re-toggling.
        onClicked: if (!root.dockHosted)
            detailsPopup.requestedOpen = !detailsPopup.requestedOpen
        onContainsMouseChanged: {
            if (!root.dockHosted)
                return
            if (containsMouse) {
                dashboardCloseDelay.stop()
                dashboardOpenDelay.restart()
            } else if (!root.popupPointerInside) {
                dashboardOpenDelay.stop()
                dashboardCloseDelay.restart()
            }
        }
    }

    Timer {
        id: dashboardOpenDelay
        interval: 420
        repeat: false
        onTriggered: {
            if (root.dockHosted && hoverArea.containsMouse && root.available)
                DockModelService.openDockPopup(detailsPopup)
        }
    }

    Timer {
        id: dashboardCloseDelay
        interval: 260
        repeat: false
        onTriggered: {
            if (root.dockHosted && !hoverArea.containsMouse
                    && !root.popupPointerInside) {
                detailsPopup.hide()
                DockModelService.releaseDockPopup(detailsPopup)
            }
        }
    }

    AnimatedPopupWindow {
        id: temperatureTooltip
        motionOrigin: root.dockHosted ? Item.Bottom : Item.Top
        // Dock hosts go straight to the dashboard on hover, so the compact
        // tooltip only serves the standalone Bar.
        requestedOpen: !root.dockHosted && hoverArea.containsMouse
            && root.available && !detailsPopup.requestedOpen
        implicitWidth: tooltipText.implicitWidth + 16
        implicitHeight: tooltipText.implicitHeight + 10
        color: "transparent"

        anchor {
            item: hoverArea
            edges: root.dockHosted ? Edges.Top : Edges.Bottom
            gravity: root.dockHosted ? Edges.Top : Edges.Bottom
            margins.top: root.dockHosted ? -6 : 0
            margins.bottom: root.dockHosted ? 0 : -6
        }

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: ThemeService.tooltipBackground

            Text {
                id: tooltipText
                anchors.centerIn: parent
                text: "CPU 平均 " + root.currentC + "°C · 60 秒最高 "
                    + root.maximum5MinuteC + "°C"
                color: ThemeService.foregroundColor
                font {
                    family: "Noto Sans CJK SC"
                    pixelSize: 12
                    weight: Font.DemiBold
                }
            }
        }
    }

    // A click opens the persistent, iStat-style sensor dashboard. Hover still
    // keeps the compact one-line tooltip for a quick glance.
    AnimatedPopupWindow {
        id: detailsPopup
        motionOrigin: root.dockHosted ? Item.Bottom : Item.Top
        implicitWidth: 360
        implicitHeight: 670
        color: "transparent"
        onVisibleChanged: if (!visible && root.dockHosted)
            DockModelService.releaseDockPopup(detailsPopup)

        anchor {
            item: hoverArea
            edges: root.dockHosted ? Edges.Top : Edges.Bottom
            gravity: root.dockHosted ? Edges.Top : Edges.Bottom
            margins.top: root.dockHosted ? -6 : 0
            margins.bottom: root.dockHosted ? 0 : -6
        }

        LiquidGlassPanel {
            id: detailsSurface
            anchors.fill: parent
            radius: 16
            cornerExponent: AppearanceTokens.shape.cornerExponent
            // The blur region below supplies the real backdrop blur; this
            // richer translucent material adds the specular glass finish.
            baseColor: ThemeService.isDark
                ? Qt.rgba(0.04, 0.05, 0.07, 0.72)
                : Qt.rgba(0.94, 0.95, 0.98, 0.68)
            surfaceOpacity: 0.96
            materialDepth: 1.8
            material: "thick"

            HoverHandler {
                // Keeps the hover-opened dashboard alive while the pointer is
                // over the popup itself, same as the music popup's contract.
                onHoveredChanged: root.popupPointerInside = hovered
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Row {
                    width: parent.width

                    Column {
                        width: parent.width - closeButton.width
                        spacing: 2

                        GlassText {
                            text: "温度传感器"
                            color: ThemeService.foregroundColor
                            font { family: "Noto Sans CJK SC"; pixelSize: 16; weight: Font.DemiBold }
                        }

                        GlassText {
                            text: "每 10 秒更新 · " + MetricsService.sensors.length + " 个读数"
                            color: Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.62)
                            font { family: "Noto Sans CJK SC"; pixelSize: 11 }
                        }
                    }

                    Rectangle {
                        id: closeButton
                        width: 24
                        height: 24
                        radius: width / 2
                        color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"

                        GlassText {
                            anchors.centerIn: parent
                            text: "×"
                            color: ThemeService.foregroundColor
                            font.pixelSize: 20
                        }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: detailsPopup.hide()
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.12) }

                Row {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: [
                            { label: "平均 CPU", value: root.currentC + "°C" },
                            { label: "60 秒最高", value: root.maximum5MinuteC + "°C" }
                        ]
                        delegate: Rectangle {
                            width: (parent.width - 8) / 2
                            height: 55
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                GlassText { text: modelData.label; color: Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.65); font.pixelSize: 11 }
                                GlassText { text: modelData.value; color: ThemeService.foregroundColor; font { pixelSize: 19; weight: Font.DemiBold } }
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: [
                            { label: "下行", value: NetworkService.formatRate(NetworkService.downloadBytesPerSecond) },
                            { label: "上行", value: NetworkService.formatRate(NetworkService.uploadBytesPerSecond) }
                        ]
                        delegate: Rectangle {
                            width: (parent.width - 8) / 2
                            height: 55
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                GlassText { text: modelData.label; color: Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.65); font.pixelSize: 11 }
                                GlassText { text: modelData.value; color: ThemeService.foregroundColor; font { pixelSize: 19; weight: Font.DemiBold } }
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    UsageRing {
                        width: (parent.width - 8) / 2
                        label: "内存"
                        detail: root.formatBytes(MetricsService.memoryUsedBytes) + " / " + root.formatBytes(MetricsService.memoryTotalBytes)
                        value: root.memoryUsage
                        accentColor: "#5e5ce6"
                    }
                    UsageRing {
                        width: (parent.width - 8) / 2
                        label: "磁盘 /"
                        detail: root.formatBytes(MetricsService.diskUsedBytes) + " / " + root.formatBytes(MetricsService.diskTotalBytes)
                        value: root.diskUsage
                        accentColor: "#30d158"
                    }
                }

                Row {
                    width: parent.width
                    spacing: 12

                    Column {
                        width: (parent.width - 12) / 2
                        spacing: 3
                        GlassText {
                            text: "内存趋势 · 最近 " + MetricsService.memoryHistory.length * 10 + " 秒"
                            color: Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.62)
                            font { family: "Noto Sans CJK SC"; pixelSize: 10 }
                        }
                        UsageSparkline { width: parent.width; values: MetricsService.memoryHistoryValues; lineColor: "#5e5ce6"; adaptiveRange: true }
                    }
                    Column {
                        width: (parent.width - 12) / 2
                        spacing: 3
                        GlassText {
                            text: "CPU 趋势 · " + Math.round(MetricsService.cpuUsage * 100) + "% · 最近 " + MetricsService.cpuHistory.length * 10 + " 秒"
                            color: Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.62)
                            font { family: "Noto Sans CJK SC"; pixelSize: 10 }
                        }
                        UsageSparkline { width: parent.width; values: MetricsService.cpuHistoryValues; lineColor: "#ff9f0a" }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 3
                    GlassText {
                        text: "CPU 平均频率 · " + Math.round(MetricsService.cpuFrequencyMhz) + " MHz · 最近 " + MetricsService.frequencyHistory.length * 10 + " 秒"
                        color: Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.62)
                        font { family: "Noto Sans CJK SC"; pixelSize: 10 }
                    }
                    UsageSparkline {
                        width: parent.width
                        values: MetricsService.frequencyHistoryValues
                        lineColor: "#64d2ff"
                        adaptiveRange: true
                    }
                }

                GlassText {
                    text: "实时读数"
                    color: ThemeService.foregroundColor
                    font { family: "Noto Sans CJK SC"; pixelSize: 12; weight: Font.DemiBold }
                }

                ListView {
                    width: parent.width
                    height: parent.height - y
                    clip: true
                    model: MetricsService.sensors
                    spacing: 2
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 38
                        radius: 6
                        color: index % 2 ? "transparent" : Qt.rgba(1, 1, 1, 0.045)
                        GlassText {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: parent.width - valueText.width - 28
                            elide: Text.ElideRight
                            text: modelData.device + " · " + modelData.label
                            color: ThemeService.foregroundColor
                            font { family: "Noto Sans CJK SC"; pixelSize: 12 }
                        }
                        GlassText {
                            id: valueText
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: (modelData.milliC / 1000).toFixed(1) + "°C"
                            color: modelData.milliC >= 85000 ? "#ff453a" : modelData.milliC >= 70000 ? "#ff9f0a" : ThemeService.foregroundColor
                            font { family: "SF Pro Display"; pixelSize: 13; weight: Font.DemiBold }
                        }
                    }
                }
            }
        }

        BackgroundEffect.blurRegion: detailsPopup.visible
            ? detailsSurface.blurRegion : null
    }

    function formatBytes(value) {
        if (value >= 1073741824)
            return (value / 1073741824).toFixed(1) + " GiB"
        if (value >= 1048576)
            return (value / 1048576).toFixed(0) + " MiB"
        return Math.round(value / 1024) + " KiB"
    }
}
