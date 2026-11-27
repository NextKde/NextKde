import QtQuick

Item {
    id: root

    required property var widgetSize
    required property var appearance
    required property var systemData

    property color cpuColor: "#ff375f"
    property color memoryColor: "#30d158"
    property color storageColor: "#64d2ff"
    property color ringTrackColor: Qt.rgba(0.19, 0.17, 0.20, 0.12)
    property color primaryInk: "#4c4a54"
    property color subtleInk: "#7d7782"
    property color dividerColor: Qt.rgba(0.19, 0.17, 0.20, 0.12)
    property bool heavyRings: false

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 2
    readonly property int spanRows: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[1]) : 1
    readonly property bool compact: spanCols <= 1
    readonly property bool tall: spanRows >= 2

    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property bool outlineText: Boolean(appearance?.transparent)
    readonly property int textStyle: outlineText ? Text.Outline : Text.Normal
    readonly property color textStyleColor: appearance?.isDark
        ? Qt.rgba(0, 0, 0, 0.58) : Qt.rgba(1, 1, 1, 0.68)

    readonly property real cpuValue: Math.max(0, Math.min(1, Number(systemData?.cpuUsage ?? 0)))
    readonly property real memUsed: Number(systemData?.memoryUsedBytes ?? 0)
    readonly property real memTotal: Number(systemData?.memoryTotalBytes ?? 0)
    readonly property real memoryValue: memTotal > 0 ? Math.max(0, Math.min(1, memUsed / memTotal)) : 0
    readonly property real diskUsed: Number(systemData?.diskUsedBytes ?? 0)
    readonly property real diskTotal: Number(systemData?.diskTotalBytes ?? 0)
    readonly property real storageValue: diskTotal > 0 ? Math.max(0, Math.min(1, diskUsed / diskTotal)) : 0
    readonly property real freqMhz: Number(systemData?.cpuFrequencyMhz ?? 0)
    readonly property real tempC: Number(systemData?.temperatureMilliC ?? -1) / 1000
    readonly property bool tempAvailable: tempC >= 0

    readonly property var cpuHistory: systemData?.cpuHistory ?? []
    readonly property var memoryHistory: systemData?.memoryHistory ?? []
    readonly property var frequencyHistory: systemData?.frequencyHistory ?? []

    property int hoveredMetric: -1

    function formatBytes(bytes) {
        const b = Number(bytes)
        if (!Number.isFinite(b) || b <= 0) return "0 GB"
        const gb = b / (1024 * 1024 * 1024)
        if (gb >= 100) return Math.round(gb) + " GB"
        if (gb >= 1) return gb.toFixed(1) + " GB"
        const mb = b / (1024 * 1024)
        return Math.round(mb) + " MB"
    }

    function metricName(idx) {
        if (idx === 0) return "CPU"
        if (idx === 1) return root.isZh ? "内存" : "Memory"
        return root.isZh ? "存储" : "Storage"
    }

    function metricValue(idx) {
        if (idx === 0) return root.cpuValue
        if (idx === 1) return root.memoryValue
        return root.storageValue
    }

    function metricDetail(idx) {
        if (idx === 0)
            return root.freqMhz > 0 ? (Math.round(root.freqMhz) + " MHz") : (Math.round(root.cpuValue * 100) + "%")
        if (idx === 1)
            return formatBytes(root.memUsed) + " / " + formatBytes(root.memTotal)
        return formatBytes(root.diskUsed) + " / " + formatBytes(root.diskTotal)
    }

    component ConcentricRings: Canvas {
        id: ringsCanvas
        property real cpuVal: root.cpuValue
        property real memVal: root.memoryValue
        property real storVal: root.storageValue
        property color cCpu: root.cpuColor
        property color cMem: root.memoryColor
        property color cStor: root.storageColor
        property color cTrack: root.ringTrackColor
        property bool heavy: root.heavyRings

        onCpuValChanged: requestPaint()
        onMemValChanged: requestPaint()
        onStorValChanged: requestPaint()
        onCCpuChanged: requestPaint()
        onCMemChanged: requestPaint()
        onCStorChanged: requestPaint()
        onCTrackChanged: requestPaint()
        onHeavyChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        function drawRing(ctx, radius, value, strokeColor) {
            if (radius <= 2) return
            const cx = width / 2
            const cy = height / 2
            const amount = Math.max(0, Math.min(1, value))
            const start = -Math.PI / 2
            ctx.lineWidth = heavy
                ? Math.max(5.5, width * 0.085)
                : Math.max(4.5, width * 0.068)
            ctx.lineCap = "round"
            ctx.strokeStyle = cTrack.toString()
            ctx.beginPath()
            ctx.arc(cx, cy, radius, 0, Math.PI * 2)
            ctx.stroke()

            if (amount > 0.004) {
                ctx.strokeStyle = strokeColor.toString()
                ctx.beginPath()
                ctx.arc(cx, cy, radius, start, start + Math.PI * 2 * amount)
                ctx.stroke()
            }
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (width <= 0 || height <= 0) return
            const base = Math.min(width, height)
            drawRing(ctx, base * 0.41, cpuVal, cCpu)
            drawRing(ctx, base * 0.295, memVal, cMem)
            drawRing(ctx, base * 0.18, storVal, cStor)
        }
    }

    component Sparkline: Canvas {
        id: sparkCanvas
        property var values: []
        property color lineColor: "#ff375f"
        property bool adaptiveRange: false
        property int maxPoints: 36
        property int smoothingWindow: 5

        onValuesChanged: requestPaint()
        onLineColorChanged: requestPaint()
        onAdaptiveRangeChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (width <= 2 || height <= 2) return

            const raw = values
            if (!raw || typeof raw === "string" || typeof raw.length !== "number" || raw.length < 2)
                return

            const startIdx = Math.max(0, raw.length - maxPoints)
            const slice = []
            for (let i = startIdx; i < raw.length; ++i) {
                const v = Number(raw[i])
                if (Number.isFinite(v)) slice.push(v)
            }
            if (slice.length < 2) return

            // Simple moving average smoothing matching UsageSparkline
            const smoothed = []
            const halfWin = Math.floor(smoothingWindow / 2)
            for (let i = 0; i < slice.length; ++i) {
                let sum = 0
                let cnt = 0
                for (let k = Math.max(0, i - halfWin); k <= Math.min(slice.length - 1, i + halfWin); ++k) {
                    sum += slice[k]
                    cnt++
                }
                smoothed.push(sum / Math.max(1, cnt))
            }

            let minV = 0
            let maxV = 1
            if (adaptiveRange) {
                minV = smoothed[0]
                maxV = smoothed[0]
                for (let i = 1; i < smoothed.length; ++i) {
                    if (smoothed[i] < minV) minV = smoothed[i]
                    if (smoothed[i] > maxV) maxV = smoothed[i]
                }
                const span = maxV - minV
                const pad = span > 0 ? span * 0.18 : Math.max(0.05, Math.abs(maxV) * 0.1)
                minV = Math.max(0, minV - pad)
                maxV = maxV + pad
            }
            const range = Math.max(1e-6, maxV - minV)

            const padY = 2
            const usableH = Math.max(1, height - padY * 2)
            const pts = []
            for (let i = 0; i < smoothed.length; ++i) {
                const px = (i / (smoothed.length - 1)) * width
                const norm = Math.max(0, Math.min(1, (smoothed[i] - minV) / range))
                const py = padY + (1 - norm) * usableH
                pts.push({ x: px, y: py })
            }

            // Soft area fill beneath line
            const grad = ctx.createLinearGradient(0, 0, 0, height)
            grad.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.22).toString())
            grad.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.0).toString())

            ctx.beginPath()
            ctx.moveTo(pts[0].x, height)
            ctx.lineTo(pts[0].x, pts[0].y)
            for (let i = 1; i < pts.length; ++i)
                ctx.lineTo(pts[i].x, pts[i].y)
            ctx.lineTo(pts[pts.length - 1].x, height)
            ctx.closePath()
            ctx.fillStyle = grad
            ctx.fill()

            // Crisp trend stroke
            ctx.beginPath()
            ctx.moveTo(pts[0].x, pts[0].y)
            for (let i = 1; i < pts.length; ++i)
                ctx.lineTo(pts[i].x, pts[i].y)
            ctx.strokeStyle = lineColor.toString()
            ctx.lineWidth = 1.8
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.stroke()
        }
    }

    // ── 1x1 Compact View ─────────────────────────────────────────────────
    Item {
        visible: root.compact
        anchors.fill: parent
        anchors.margins: 10

        Item {
            id: compactRingBox
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 2 }
            width: Math.min(parent.width * 0.78, parent.height * 0.74)
            height: width

            ConcentricRings { anchors.fill: parent }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                onEntered: root.hoveredMetric = 0
                onPositionChanged: mouse => {
                    const dx = mouse.x - width / 2
                    const dy = mouse.y - height / 2
                    const dist = Math.sqrt(dx * dx + dy * dy) / Math.max(1, width)
                    if (dist >= 0.335) root.hoveredMetric = 0
                    else if (dist >= 0.225) root.hoveredMetric = 1
                    else root.hoveredMetric = 2
                }
                onExited: root.hoveredMetric = -1
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: 0

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.hoveredMetric >= 0
                    ? (root.metricName(root.hoveredMetric) + " " + Math.round(root.metricValue(root.hoveredMetric) * 100) + "%")
                    : ("CPU " + Math.round(root.cpuValue * 100) + "%" + (root.tempAvailable ? (" · " + Math.round(root.tempC) + "°") : ""))
                color: root.primaryInk
                font { pixelSize: 11; weight: Font.DemiBold }
                elide: Text.ElideRight
                style: root.textStyle
                styleColor: root.textStyleColor
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.hoveredMetric >= 0
                    ? root.metricDetail(root.hoveredMetric)
                    : ((root.isZh ? "内存 " : "Mem ") + Math.round(root.memoryValue * 100) + "% · "
                        + (root.isZh ? "存储 " : "Disk ") + Math.round(root.storageValue * 100) + "%")
                color: root.subtleInk
                font.pixelSize: 9
                elide: Text.ElideRight
                style: root.textStyle
                styleColor: root.textStyleColor
            }
        }
    }

    // ── 2x1 / 2x2 Split View (Left: Rings + Temp, Right: Sparklines) ─────
    Item {
        visible: !root.compact
        anchors.fill: parent
        anchors.margins: root.tall ? 16 : 12

        // Left 40% column
        Item {
            id: leftCol
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * 0.40

            Item {
                id: splitRingBox
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: root.tall ? 12 : 2 }
                width: Math.min(parent.width * 0.90, parent.height * (root.tall ? 0.62 : 0.72))
                height: width

                ConcentricRings { anchors.fill: parent }

                // Hover center readout
                Text {
                    visible: root.hoveredMetric >= 0
                    anchors.centerIn: parent
                    width: parent.width * 0.56
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.hoveredMetric >= 0
                        ? (root.metricName(root.hoveredMetric) + "\n" + Math.round(root.metricValue(root.hoveredMetric) * 100) + "%")
                        : ""
                    color: root.primaryInk
                    font { pixelSize: Math.max(8, Math.round(parent.width * 0.095)); weight: Font.DemiBold }
                    style: root.textStyle
                    styleColor: root.textStyleColor
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true
                    onEntered: root.hoveredMetric = 0
                    onPositionChanged: mouse => {
                        const dx = mouse.x - width / 2
                        const dy = mouse.y - height / 2
                        const dist = Math.sqrt(dx * dx + dy * dy) / Math.max(1, width)
                        if (dist >= 0.335) root.hoveredMetric = 0
                        else if (dist >= 0.225) root.hoveredMetric = 1
                        else root.hoveredMetric = 2
                    }
                    onExited: root.hoveredMetric = -1
                }
            }

            // Bottom temperature & storage / hovered detail strip
            Item {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: root.tall ? 6 : 0 }
                height: root.tall ? 44 : 30

                Row {
                    anchors.centerIn: parent
                    spacing: root.tall ? 10 : 7

                    // Pure-QML thermometer badge + live temp
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Item {
                            width: 10; height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 1; width: 4; height: 11; radius: 2
                                color: "transparent"
                                border.width: 1.2
                                border.color: root.subtleInk
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 6; width: 2; height: 6; radius: 1
                                color: root.outlineText ? root.primaryInk : root.cpuColor
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 11; width: 7; height: 7; radius: 3.5
                                color: root.outlineText ? root.primaryInk : root.cpuColor
                            }
                        }

                        Column {
                            spacing: -1
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: root.tempAvailable ? (Math.round(root.tempC) + "°C") : "--"
                                color: root.primaryInk
                                font { pixelSize: root.tall ? 13 : 11; weight: Font.DemiBold }
                                style: root.textStyle
                                styleColor: root.textStyleColor
                            }
                            Text {
                                text: root.isZh ? "温度" : "Temp"
                                color: root.subtleInk
                                font.pixelSize: root.tall ? 9 : 8
                                style: root.textStyle
                                styleColor: root.textStyleColor
                            }
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: root.tall ? 24 : 18
                        color: root.dividerColor
                    }

                    Column {
                        spacing: -1
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: Math.round(root.storageValue * 100) + "%"
                            color: root.primaryInk
                            font { pixelSize: root.tall ? 13 : 11; weight: Font.DemiBold }
                            style: root.textStyle
                            styleColor: root.textStyleColor
                        }
                        Text {
                            text: root.isZh ? "存储" : "Disk"
                            color: root.subtleInk
                            font.pixelSize: root.tall ? 9 : 8
                            style: root.textStyle
                            styleColor: root.textStyleColor
                        }
                    }
                }
            }
        }

        // Right 56% column: 3 live trend sparklines
        Item {
            anchors {
                left: leftCol.right; right: parent.right
                top: parent.top; bottom: parent.bottom
                leftMargin: root.tall ? 14 : 10
            }

            Column {
                anchors {
                    left: parent.left; right: parent.right; top: parent.top
                    bottom: tallTotalsRow.visible ? tallTotalsRow.top : parent.bottom
                    bottomMargin: tallTotalsRow.visible ? 10 : 0
                }
                spacing: root.tall ? 10 : 4

                Item {
                    width: parent.width
                    height: Math.max(12, (parent.height - parent.spacing * 2) / 3)
                    Text {
                        id: memTitle
                        anchors { left: parent.left; top: parent.top }
                        text: (root.isZh ? "内存  " : "Memory  ") + Math.round(root.memoryValue * 100) + "%"
                        color: root.hoveredMetric === 1 && !root.outlineText ? root.memoryColor : root.primaryInk
                        font { pixelSize: root.tall ? 11 : 9; weight: Font.DemiBold }
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                    Sparkline {
                        anchors { left: parent.left; right: parent.right; top: memTitle.bottom; topMargin: 1; bottom: parent.bottom }
                        values: root.memoryHistory
                        lineColor: root.memoryColor
                        adaptiveRange: true
                    }
                }

                Item {
                    width: parent.width
                    height: Math.max(12, (parent.height - parent.spacing * 2) / 3)
                    Text {
                        id: cpuTitle
                        anchors { left: parent.left; top: parent.top }
                        text: "CPU  " + Math.round(root.cpuValue * 100) + "%"
                        color: root.hoveredMetric === 0 && !root.outlineText ? root.cpuColor : root.primaryInk
                        font { pixelSize: root.tall ? 11 : 9; weight: Font.DemiBold }
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                    Sparkline {
                        anchors { left: parent.left; right: parent.right; top: cpuTitle.bottom; topMargin: 1; bottom: parent.bottom }
                        values: root.cpuHistory
                        lineColor: root.cpuColor
                        adaptiveRange: false
                    }
                }

                Item {
                    width: parent.width
                    height: Math.max(12, (parent.height - parent.spacing * 2) / 3)
                    Text {
                        id: freqTitle
                        anchors { left: parent.left; top: parent.top }
                        text: (root.isZh ? "频率  " : "Freq  ") + Math.round(root.freqMhz) + " MHz"
                        color: root.primaryInk
                        font { pixelSize: root.tall ? 11 : 9; weight: Font.DemiBold }
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                    Sparkline {
                        anchors { left: parent.left; right: parent.right; top: freqTitle.bottom; topMargin: 1; bottom: parent.bottom }
                        values: root.frequencyHistory
                        lineColor: root.storageColor
                        adaptiveRange: true
                    }
                }
            }

            Column {
                id: tallTotalsRow
                visible: root.tall
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 4 }
                spacing: 2

                Text {
                    width: parent.width
                    text: (root.isZh ? "内存：" : "RAM: ") + root.metricDetail(1)
                    color: root.subtleInk
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    style: root.textStyle
                    styleColor: root.textStyleColor
                }
                Text {
                    width: parent.width
                    text: (root.isZh ? "磁盘：" : "Disk: ") + root.metricDetail(2)
                    color: root.subtleInk
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    style: root.textStyle
                    styleColor: root.textStyleColor
                }
            }
        }
    }
}
