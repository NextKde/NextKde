import QtQuick

Item {
    id: root

    required property var widgetSize
    required property var appearance
    required property var clockData
    property string clockStyle: "analog"
    property bool format24h: true
    property bool inDock: false
    property bool verticalDock: false
    property color dialFaceColor: "transparent"
    property color dialRimColor: "transparent"
    property color numeralColor: "#242126"
    property color markColor: "#171717"
    property color hourColor: "#171717"
    property color minuteColor: "#171717"
    property color secondColor: "#ee7659"
    property color hubColor: "#ee7659"
    property color digitalTimeColor: "#ffffff"
    property color digitalSubtleColor: "#cbd5e1"
    property color digitalRingColor: "#ffffff"
    property real digitalCornerRadius: 24

    readonly property bool monochrome: Boolean(appearance?.transparent)
    readonly property int hours: Number(clockData?.hours ?? 9)
    readonly property int minutes: Number(clockData?.minutes ?? 41)
    readonly property int seconds: Number(clockData?.seconds ?? 0)
    readonly property string timeText: {
        const preferred = format24h ? clockData?.time24h : clockData?.time12h
        return String(preferred ?? clockData?.timeText ?? "--:--")
    }
    readonly property int weekdayIndex: Number(clockData?.weekday ?? 0)
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property string weekdayText: {
        const zh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        const en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        const idx = ((weekdayIndex % 7) + 7) % 7
        return isZh ? zh[idx] : en[idx]
    }
    readonly property int utcOffsetMinutes: {
        const raw = clockData?.utcOffsetMinutes
        if (raw !== undefined && raw !== null && Number.isFinite(Number(raw)))
            return Math.round(Number(raw))
        return -new Date().getTimezoneOffset()
    }
    readonly property string utcOffsetText: {
        const total = root.utcOffsetMinutes
        if (!Number.isFinite(total)) return ""
        const sign = total > 0 ? "+" : total < 0 ? "-" : "±"
        const absVal = Math.abs(total)
        const mins = absVal % 60
        return "UTC" + sign + Math.floor(absVal / 60)
            + (mins ? ":" + (mins < 10 ? "0" : "") + mins : "")
    }
    readonly property int textStyle: monochrome ? Text.Outline : Text.Normal
    readonly property color textStyleColor: appearance?.isDark
        ? Qt.rgba(0, 0, 0, 0.58) : Qt.rgba(1, 1, 1, 0.68)

    function monoInk(value) {
        if (!monochrome) return value
        const fg = appearance?.foreground ?? "#ffffff"
        return Qt.rgba(fg.r, fg.g, fg.b, value.a)
    }

    // ── Dock compact digital layout ──────────────────────────────────────
    Column {
        visible: root.inDock
        anchors.centerIn: parent
        width: parent.width * 0.88
        spacing: 1

        Text {
            width: parent.width
            height: root.verticalDock ? root.height * 0.60 : root.height * 0.72
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            font.pixelSize: Math.max(1, Math.floor(height * 0.78))
            font.weight: Font.DemiBold
            color: root.appearance?.foreground ?? "#ffffff"
            text: root.timeText
            style: root.textStyle
            styleColor: root.textStyleColor
        }
    }

    // ── Desktop Analog Clock (1x1 baseline DeskClockFace) ────────────────
    Item {
        visible: !root.inDock && root.clockStyle === "analog"
        anchors.fill: parent
        anchors.margins: 14

        Item {
            id: analogDial
            width: Math.min(parent.width, parent.height)
            height: width
            anchors.centerIn: parent

            readonly property real dialRadius: Math.max(0, Math.min(width, height) / 2 - 3)
            readonly property real numeralRadius: dialRadius * 0.68
            readonly property int numeralSize: Math.max(9, Math.round(dialRadius * 0.19))
            readonly property real strokeScale: Math.max(0.8, dialRadius / 80)

            Rectangle {
                anchors.centerIn: parent
                width: analogDial.dialRadius * 2
                height: width
                radius: width / 2
                color: root.monochrome ? "transparent" : root.dialFaceColor
                border.color: root.monochrome ? root.monoInk(Qt.rgba(1, 1, 1, 0.35)) : root.dialRimColor
                border.width: root.monochrome ? 1 : (root.dialRimColor.a > 0 ? 1 : 0)
                antialiasing: true
            }

            Repeater {
                model: 12
                delegate: Rectangle {
                    id: tickMark
                    required property int index
                    readonly property bool cardinal: index % 3 === 0
                    width: (cardinal ? 1.8 : 0.9) * analogDial.strokeScale
                    height: (cardinal ? 5.5 : 2.8) * analogDial.strokeScale
                    radius: width / 2
                    x: analogDial.width / 2 - width / 2
                    y: analogDial.height / 2 - analogDial.dialRadius + 4 * analogDial.strokeScale
                    color: root.monoInk(root.markColor)
                    antialiasing: true
                    transform: Rotation {
                        origin.x: tickMark.width / 2
                        origin.y: analogDial.dialRadius - 4 * analogDial.strokeScale
                        angle: tickMark.index * 30
                    }
                }
            }

            Repeater {
                model: 12
                delegate: Text {
                    required property int index
                    readonly property real angle: (index + 1) * Math.PI / 6
                    text: String(index + 1)
                    x: Math.round(analogDial.width / 2 + Math.sin(angle) * analogDial.numeralRadius - width / 2)
                    y: Math.round(analogDial.height / 2 - Math.cos(angle) * analogDial.numeralRadius - height / 2)
                    color: root.monoInk(root.numeralColor)
                    font.pixelSize: analogDial.numeralSize
                    font.weight: Font.Bold
                    style: root.textStyle
                    styleColor: root.textStyleColor
                }
            }

            Rectangle {
                id: hourHand
                width: 2.5 * analogDial.strokeScale
                height: analogDial.dialRadius * 0.48
                radius: width / 2
                x: analogDial.width / 2 - width / 2
                y: analogDial.height / 2 - height
                color: root.monoInk(root.hourColor)
                antialiasing: true
                transform: Rotation {
                    origin.x: hourHand.width / 2
                    origin.y: hourHand.height
                    angle: (root.hours % 12 + root.minutes / 60) * 30
                }
            }

            Rectangle {
                id: minuteHand
                width: 1.8 * analogDial.strokeScale
                height: analogDial.dialRadius * 0.58
                radius: width / 2
                x: analogDial.width / 2 - width / 2
                y: analogDial.height / 2 - height
                color: root.monoInk(root.minuteColor)
                antialiasing: true
                transform: Rotation {
                    origin.x: minuteHand.width / 2
                    origin.y: minuteHand.height
                    angle: root.minutes * 6
                }
            }

            Rectangle {
                id: secondHand
                width: Math.max(1, analogDial.strokeScale)
                height: analogDial.dialRadius * 0.76
                radius: width / 2
                x: analogDial.width / 2 - width / 2
                y: analogDial.height / 2 - height
                color: root.monoInk(root.secondColor)
                antialiasing: true
                transform: Rotation {
                    origin.x: secondHand.width / 2
                    origin.y: secondHand.height
                    angle: root.seconds * 6
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 4.4 * analogDial.strokeScale
                height: width
                radius: width / 2
                color: root.monoInk(root.hubColor)
                antialiasing: true
            }
        }
    }

    // ── Desktop Digital Clock (1x1 baseline DeskDigitalClockFace) ────────
    Item {
        visible: !root.inDock && root.clockStyle === "digital"
        anchors.fill: parent

        Canvas {
            id: secondsRing
            anchors.fill: parent
            readonly property int currentSecond: root.seconds
            readonly property real inset: 14
            readonly property real ringRadius: Math.max(4, Math.min(root.digitalCornerRadius - inset, width / 2, height / 2))
            readonly property color activeColor: root.monoInk(root.digitalRingColor)
            readonly property color trackColor: Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.20)

            onCurrentSecondChanged: requestPaint()
            onActiveColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()

            function ringPoint(distance, w, h, r) {
                const horiz = Math.max(0, w - r * 2)
                const vert = Math.max(0, h - r * 2)
                const arc = Math.PI * r / 2
                const perimeter = Math.max(1, horiz * 2 + vert * 2 + arc * 4)
                let d = (distance + horiz / 2) % perimeter
                if (d < horiz)
                    return { x: r + d, y: 0, nx: 0, ny: -1 }
                d -= horiz
                if (d < arc) {
                    const a = -Math.PI / 2 + d / r
                    return { x: w - r + Math.cos(a) * r, y: r + Math.sin(a) * r, nx: Math.cos(a), ny: Math.sin(a) }
                }
                d -= arc
                if (d < vert)
                    return { x: w, y: r + d, nx: 1, ny: 0 }
                d -= vert
                if (d < arc) {
                    const a = d / r
                    return { x: w - r + Math.cos(a) * r, y: h - r + Math.sin(a) * r, nx: Math.cos(a), ny: Math.sin(a) }
                }
                d -= arc
                if (d < horiz)
                    return { x: w - r - d, y: h, nx: 0, ny: 1 }
                d -= horiz
                if (d < arc) {
                    const a = Math.PI / 2 + d / r
                    return { x: r + Math.cos(a) * r, y: h - r + Math.sin(a) * r, nx: Math.cos(a), ny: Math.sin(a) }
                }
                d -= arc
                if (d < vert)
                    return { x: 0, y: h - r - d, nx: -1, ny: 0 }
                d -= vert
                const a = Math.PI + d / r
                return { x: r + Math.cos(a) * r, y: r + Math.sin(a) * r, nx: Math.cos(a), ny: Math.sin(a) }
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const w = width - inset * 2
                const h = height - inset * 2
                if (w <= 0 || h <= 0) return
                const r = ringRadius
                const perimeter = Math.max(1, 2 * (w - r * 2) + 2 * (h - r * 2) + Math.PI * r * 2)
                ctx.lineWidth = Math.max(1.4, width / 220)
                ctx.lineCap = "round"
                for (let i = 0; i < 60; ++i) {
                    const pt = ringPoint(i * perimeter / 60, w, h, r)
                    ctx.strokeStyle = (i < currentSecond ? activeColor : trackColor).toString()
                    ctx.beginPath()
                    ctx.moveTo(inset + pt.x + pt.nx * 1.5, inset + pt.y + pt.ny * 1.5)
                    ctx.lineTo(inset + pt.x + pt.nx * 7, inset + pt.y + pt.ny * 7)
                    ctx.stroke()
                }
            }
        }

        Column {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 36)
            spacing: Math.max(2, parent.height * 0.02)

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.weekdayText.toUpperCase()
                color: root.monoInk(root.digitalSubtleColor)
                font { pixelSize: Math.max(10, Math.round(root.height * 0.085)); weight: Font.Medium; letterSpacing: 1.2 }
                style: root.textStyle
                styleColor: root.textStyleColor
            }

            Text {
                width: parent.width
                height: Math.max(34, root.height * 0.34)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 18
                font { pixelSize: Math.max(26, Math.round(Math.min(root.width * 0.27, root.height * 0.32))); weight: Font.Bold; letterSpacing: -1 }
                color: root.monoInk(root.digitalTimeColor)
                text: root.timeText
                style: root.textStyle
                styleColor: root.textStyleColor
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.utcOffsetText
                color: root.monoInk(root.digitalSubtleColor)
                font { pixelSize: Math.max(10, Math.round(root.height * 0.075)); weight: Font.Medium }
                style: root.textStyle
                styleColor: root.textStyleColor
            }
        }
    }
}
