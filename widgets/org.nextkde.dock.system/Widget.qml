import QtQuick

// Dock system card: restored original DockTemperatureWidget layout with left
// thermal Avg/Max dot rows and right 3-layer concentric CPU/MEM/Storage rings.
// Host owns the outer slot shell; macOS paints thermal gradient via backgroundSpec.
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool vertical: host?.orientation === "vertical"
    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var sys: liveMode ? (host.system ?? snapshot) : snapshot
    readonly property bool material: appearance?.style === "material"
    readonly property var pal: appearance?.palette ?? ({})
    readonly property color ink: material ? (pal.onSurface ?? "#1e293b") : "white"

    readonly property real tempC: Number(sys?.temperatureMilliC ?? -1) >= 0
        ? Math.round(Number(sys.temperatureMilliC) / 1000) : -1
    readonly property real maxC: Number(sys?.temperatureMaxMilliC ?? -1) >= 0
        ? Math.round(Number(sys.temperatureMaxMilliC) / 1000) : -1
    readonly property real cpu: Math.max(0, Math.min(1, Number(sys?.cpuUsage ?? 0)))
    readonly property real mem: Number(sys?.memoryTotalBytes ?? 0) > 0
        ? Math.max(0, Math.min(1, Number(sys.memoryUsedBytes) / Number(sys.memoryTotalBytes))) : 0
    readonly property real disk: Number(sys?.diskTotalBytes ?? 0) > 0
        ? Math.max(0, Math.min(1, Number(sys.diskUsedBytes) / Number(sys.diskTotalBytes))) : 0

    function thermal(cool, warm, alpha) {
        const v = tempC >= 0 ? Math.max(0, Math.min(1, (tempC - 35) / 55)) : 0.25
        return Qt.rgba(cool.r + (warm.r - cool.r) * v, cool.g + (warm.g - cool.g) * v,
            cool.b + (warm.b - cool.b) * v, alpha)
    }
    readonly property var backgroundSpec: ({
        startColor: thermal(Qt.rgba(0.16, 0.38, 0.62, 1), Qt.rgba(0.68, 0.22, 0.18, 1), 0.68),
        endColor: thermal(Qt.rgba(0.20, 0.56, 0.68, 1), Qt.rgba(0.96, 0.52, 0.18, 1), 0.54),
        orientation: "horizontal"
    })

    // ── Horizontal Dock: Thermometer + Avg/Max + 3 Concentric Activity Rings ─
    Item {
        visible: !root.vertical
        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }

        Item {
            id: leftThermals
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: Math.round(parent.width * 0.58)
            height: Math.round(root.height * 0.84)

            Canvas {
                id: thermoGlyph
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: Math.max(14, Math.round(root.height * 0.40))
                height: width
                readonly property color glyphInk: root.ink
                onGlyphInkChanged: requestPaint()
                onWidthChanged: requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = glyphInk.toString()
                    ctx.fillStyle = glyphInk.toString()
                    ctx.lineWidth = Math.max(1.5, width * 0.11)
                    ctx.lineCap = "round"
                    const cx = width * 0.5
                    const tubeR = width * 0.13
                    const bulbR = width * 0.24
                    const topY = width * 0.14
                    const bulbY = height * 0.74
                    ctx.beginPath()
                    ctx.moveTo(cx - tubeR, bulbY - bulbR * 0.6)
                    ctx.lineTo(cx - tubeR, topY)
                    ctx.arc(cx, topY, tubeR, Math.PI, 0)
                    ctx.lineTo(cx + tubeR, bulbY - bulbR * 0.6)
                    ctx.arc(cx, bulbY, bulbR, -0.45, Math.PI + 0.45)
                    ctx.closePath()
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.arc(cx, bulbY, bulbR * 0.55, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.beginPath()
                    ctx.moveTo(cx, bulbY - bulbR * 0.4)
                    ctx.lineTo(cx, topY + tubeR * 1.4)
                    ctx.stroke()
                }
            }

            Column {
                anchors {
                    left: thermoGlyph.right
                    leftMargin: Math.max(4, Math.round(root.height * 0.10))
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                spacing: 0

                Repeater {
                    model: [
                        { label: "Avg", value: root.tempC, accent: "#64d2ff" },
                        { label: "Max", value: root.maxC, accent: "#ff6b62" }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: parent.height / 2

                        Rectangle {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: Math.max(4, Math.round(root.height * 0.10))
                            height: width
                            radius: width / 2
                            color: modelData.accent
                        }
                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: Math.max(8, Math.round(root.height * 0.18))
                                verticalCenter: parent.verticalCenter
                            }
                            text: modelData.label
                            color: root.ink
                            opacity: 0.82
                            font { pixelSize: Math.max(9, Math.round(root.height * 0.22)); weight: Font.Medium }
                        }
                        Text {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: modelData.value >= 0 ? (modelData.value + "°") : "--°"
                            color: root.ink
                            font { pixelSize: Math.max(10, Math.round(root.height * 0.28)); weight: Font.DemiBold }
                        }
                    }
                }
            }
        }

        Item {
            anchors {
                left: leftThermals.right
                leftMargin: 4
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }

            Canvas {
                id: activityCanvas
                anchors.centerIn: parent
                width: Math.min(parent.width, Math.round(root.height * 0.96))
                height: width

                readonly property real cpuVal: root.cpu
                readonly property real memVal: root.mem
                readonly property real diskVal: root.disk
                readonly property color trackCol: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)

                onCpuValChanged: requestPaint()
                onMemValChanged: requestPaint()
                onDiskValChanged: requestPaint()
                onTrackColChanged: requestPaint()
                onWidthChanged: requestPaint()
                Component.onCompleted: requestPaint()

                function drawRing(ctx, radius, value, color) {
                    const cx = width / 2
                    const start = -Math.PI / 2
                    ctx.lineWidth = Math.max(2.4, width * 0.08)
                    ctx.lineCap = "round"
                    ctx.strokeStyle = trackCol.toString()
                    ctx.beginPath()
                    ctx.arc(cx, cx, radius, 0, Math.PI * 2)
                    ctx.stroke()

                    if (value > 0.005) {
                        ctx.strokeStyle = color
                        ctx.beginPath()
                        ctx.arc(cx, cx, radius, start, start + Math.PI * 2 * value)
                        ctx.stroke()
                    }
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    if (width <= 8) return
                    drawRing(ctx, width * 0.39, cpuVal, "#ff375f")
                    drawRing(ctx, width * 0.285, memVal, "#30d158")
                    drawRing(ctx, width * 0.18, diskVal, "#64d2ff")
                }
            }
        }
    }

    // ── Side Dock ────────────────────────────────────────────────────────
    Text {
        visible: root.vertical
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.tempC >= 0 ? root.tempC + "°" : "--°"
        color: root.ink
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 6
        font { pixelSize: Math.max(10, Math.round(root.height * 0.5)); weight: Font.DemiBold }
    }
}
