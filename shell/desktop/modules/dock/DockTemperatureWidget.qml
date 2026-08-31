import QtQuick
import QtQuick.Effects
import qs.desktop.modules.common

// Permanent thermal page for DockInfoCarousel. It is deliberately a pure
// MetricsService consumer: the Bar, Dock and DeskCenter all render the same
// shell-data-service snapshot and never start their own sensor pollers.
Item {
    id: widget

    property int iconSize: 44
    property int dockHeight: 60
    property int widthUnits: 4
    readonly property real backgroundGap: iconSize * 0.1
    readonly property real contentWidth: iconSize * widthUnits
    readonly property bool compact: iconSize < 32
    readonly property bool available: MetricsService.currentMilliC >= 0
        && MetricsService.maximum5MinuteMilliC >= 0
    readonly property int currentC: available
        ? Math.round(MetricsService.currentMilliC / 1000) : -1
    readonly property int maximum5MinuteC: available
        ? Math.round(MetricsService.maximum5MinuteMilliC / 1000) : -1
    readonly property real cpuValue: Math.max(0,
        Math.min(1, MetricsService.cpuUsage))
    readonly property real memoryValue: MetricsService.memoryTotalBytes > 0
        ? Math.max(0, Math.min(1, MetricsService.memoryUsedBytes
            / MetricsService.memoryTotalBytes)) : 0
    readonly property real storageValue: MetricsService.diskTotalBytes > 0
        ? Math.max(0, Math.min(1, MetricsService.diskUsedBytes
            / MetricsService.diskTotalBytes)) : 0

    width: contentWidth + backgroundGap * 2
    height: iconSize

    function thermalColor(cool, warm, alpha) {
        const value = available ? Math.max(0, Math.min(1,
            (currentC - 35) / 55)) : 0.25
        return ConfigService.styledDockColor(Qt.rgba(
            cool.r + (warm.r - cool.r) * value,
            cool.g + (warm.g - cool.g) * value,
            cool.b + (warm.b - cool.b) * value,
            alpha))
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: -widget.backgroundGap
        width: widget.width
        height: widget.iconSize + widget.backgroundGap * 2
        radius: widget.iconSize * 0.35
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: widget.thermalColor(
                    Qt.rgba(0.16, 0.38, 0.62, 1),
                    Qt.rgba(0.68, 0.22, 0.18, 1), 0.68)
            }
            GradientStop {
                position: 1
                color: widget.thermalColor(
                    Qt.rgba(0.20, 0.56, 0.68, 1),
                    Qt.rgba(0.96, 0.52, 0.18, 1), 0.54)
            }
        }
    }

    Row {
        id: temperatureRow
        anchors.centerIn: parent
        visible: !widget.compact
        // Keep the composition compact instead of letting the temperature
        // block absorb every spare pixel in the four-unit card.
        width: Math.min(parent.width - widget.backgroundGap * 2,
                        widget.iconSize * 3.44)
        height: Math.round(widget.iconSize * 0.82)
        spacing: Math.max(4, Math.round(widget.iconSize * 0.10))

        // Left: temperatures use two compact rows, with current above peak.
        // This keeps the card's left/right split while avoiding two narrow
        // side-by-side temperature columns.
        Item {
            id: temperatures
            width: Math.round(widget.iconSize * 2.18)
            height: parent.height

            DockMetricGlyph {
                id: temperatureIcon
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                width: Math.round(widget.iconSize * 0.42)
                height: width
                kind: "temperature"
                glyphColor: "white"
            }

            Column {
                anchors {
                    left: temperatureIcon.right
                    leftMargin: Math.max(3, Math.round(widget.iconSize * 0.09))
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                spacing: 0

                Repeater {
                    model: [
                        { label: "平均温度", value: widget.currentC,
                            accent: "#64d2ff" },
                        { label: "最高温度", value: widget.maximum5MinuteC,
                            accent: "#ff6b62" }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: parent.height / 2

                        Rectangle {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            width: Math.max(4,
                                Math.round(widget.iconSize * 0.09))
                            height: width
                            radius: width / 2
                            color: modelData.accent
                        }
                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: Math.round(widget.iconSize * 0.16)
                                verticalCenter: parent.verticalCenter
                            }
                            text: modelData.label
                            color: ThemeService.foregroundColor
                            opacity: 0.82
                            font {
                                family: "Noto Sans CJK SC"
                                pixelSize: Math.max(9,
                                    Math.round(widget.iconSize * 0.21))
                                weight: Font.Medium
                            }
                        }
                        Text {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            text: widget.available
                                ? modelData.value + "°" : "--°"
                            color: ThemeService.foregroundColor
                            font {
                                family: "SF Pro Display"
                                pixelSize: Math.max(11,
                                    Math.round(widget.iconSize * 0.27))
                                weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
        }

        // Keep the established left/right allocation while removing the
        // visual separator between the thermal summary and activity rings.
        Item {
            id: divider
            width: 1
            height: parent.height * 0.68
        }

        // Reserve the full remaining right region, then centre the rings in
        // it. The old ring item was only as wide as the rings themselves, so
        // its centre did not coincide with the right region's centre.
        Item {
            id: activityRegion
            width: parent.width - temperatures.width - divider.width
                - parent.spacing * 2
            height: parent.height

            // Right: the same nested Activity-ring contract as DeskCenter:
            // outer CPU, middle memory, inner storage, with identical colours.
            Item {
                id: activityRings
                width: Math.round(widget.iconSize * 0.96)
                height: width
                anchors.centerIn: parent

                Canvas {
                    id: activityCanvas
                    anchors.fill: parent

                    function drawRing(ctx, radius, value, color) {
                        const center = width / 2
                        const start = -Math.PI / 2
                        ctx.lineWidth = Math.max(2.4, width * 0.075)
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Qt.rgba(0.19, 0.17, 0.2, 0.16)
                        ctx.beginPath()
                        ctx.arc(center, center, radius, 0, Math.PI * 2)
                        ctx.stroke()
                        ctx.strokeStyle = color
                        ctx.beginPath()
                        ctx.arc(center, center, radius, start,
                            start + Math.PI * 2 * value)
                        ctx.stroke()
                    }

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        drawRing(ctx, width * 0.39, widget.cpuValue, "#ff375f")
                        drawRing(ctx, width * 0.285, widget.memoryValue, "#30d158")
                        drawRing(ctx, width * 0.18, widget.storageValue, "#64d2ff")
                    }
                    Component.onCompleted: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections {
                        target: widget
                        function onCpuValueChanged() { activityCanvas.requestPaint() }
                        function onMemoryValueChanged() { activityCanvas.requestPaint() }
                        function onStorageValueChanged() { activityCanvas.requestPaint() }
                    }
                }
            }
        }
    }

    Row {
        anchors.centerIn: parent
        visible: widget.compact
        height: parent.height
        spacing: Math.max(2, Math.round(widget.iconSize * 0.10))

        DockMetricGlyph {
            width: Math.max(9, Math.round(widget.iconSize * 0.52))
            height: width
            kind: "temperature"
            glyphColor: "white"
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: widget.available ? widget.currentC + "°" : "--°"
            color: "white"
            anchors.verticalCenter: parent.verticalCenter
            font {
                family: "SF Pro Display"
                pixelSize: Math.max(9, Math.round(widget.iconSize * 0.48))
                weight: Font.DemiBold
            }
        }
        Text {
            text: "· 峰值 " + (widget.available
                ? widget.maximum5MinuteC + "°" : "--°")
            color: "white"
            opacity: 0.68
            anchors.verticalCenter: parent.verticalCenter
            font {
                family: "Noto Sans CJK SC"
                pixelSize: Math.max(6, Math.round(widget.iconSize * 0.28))
                weight: Font.Medium
            }
        }
    }
}
