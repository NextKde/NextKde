import QtQuick
import "../../../shared/qml/i18n"
import qs.desktop.modules.common

Item {
    id: face

    objectName: "desktop-clock-digital-face"

    property date date: new Date()
    property string systemTimeZone: ""
    property string city: cityLabelForZone(systemTimeZone)
    property int utcOffsetMinutes: -date.getTimezoneOffset()
    property color cityColor: "#ffffff"
    property color timeColor: "#ffffff"
    property color offsetColor: "#ffffff"
    property color ringColor: "#ffffff"
    property color ringTrackColor: Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.20)
    property real cornerRadius: AppearanceTokens.widget.radius
    property bool monochrome: false

    readonly property real contentMargin: Math.max(24, Math.min(width, height) * 0.12)

    function ink(value) {
        if (!monochrome)
            return value
        const gray = value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722
        return Qt.rgba(gray, gray, gray, value.a)
    }

    function cityLabelForZone(zone) {
        const parts = String(zone || "").split("/")
        if (parts.length < 2 || ["Etc", "SystemV", "posix", "right"].indexOf(parts[0]) >= 0)
            return ""
        const city = parts[parts.length - 1].replace(/_/g, " ").trim()
        if (!city || /^(UTC|GMT|UCT|Zulu|Factory|localtime)$/i.test(city)) return ""
        return city.toUpperCase()
    }

    function formattedOffset() {

        const total = Math.round(Number(utcOffsetMinutes))
        if (!Number.isFinite(total)) return ""
        const sign = total > 0 ? "+" : total < 0 ? "-" : "±"
        const absolute = Math.abs(total)
        const minutes = absolute % 60
        return sign + Math.floor(absolute / 60)
            + (minutes ? ":" + (minutes < 10 ? "0" : "") + minutes : "")
    }

    function ringPoint(distance, width, height, radius) {
        const horizontal = width - radius * 2
        const vertical = height - radius * 2
        const arc = Math.PI * radius / 2
        let d = distance + horizontal / 2
        const perimeter = horizontal * 2 + vertical * 2 + arc * 4
        if (d >= perimeter) d -= perimeter
        if (d < horizontal)
            return { x: radius + d, y: 0, nx: 0, ny: -1 }
        d -= horizontal
        if (d < arc) {
            const angle = -Math.PI / 2 + d / radius
            return { x: width - radius + Math.cos(angle) * radius,
                y: radius + Math.sin(angle) * radius,
                nx: Math.cos(angle), ny: Math.sin(angle) }
        }
        d -= arc
        if (d < vertical)
            return { x: width, y: radius + d, nx: 1, ny: 0 }
        d -= vertical
        if (d < arc) {
            const angle = d / radius
            return { x: width - radius + Math.cos(angle) * radius,
                y: height - radius + Math.sin(angle) * radius,
                nx: Math.cos(angle), ny: Math.sin(angle) }
        }
        d -= arc
        if (d < horizontal)
            return { x: width - radius - d, y: height, nx: 0, ny: 1 }
        d -= horizontal
        if (d < arc) {
            const angle = Math.PI / 2 + d / radius
            return { x: radius + Math.cos(angle) * radius,
                y: height - radius + Math.sin(angle) * radius,
                nx: Math.cos(angle), ny: Math.sin(angle) }
        }
        d -= arc
        if (d < vertical)
            return { x: 0, y: height - radius - d, nx: -1, ny: 0 }
        d -= vertical
        const angle = Math.PI + d / radius
        return { x: radius + Math.cos(angle) * radius,
            y: radius + Math.sin(angle) * radius,
            nx: Math.cos(angle), ny: Math.sin(angle) }
    }

    Canvas {
        id: secondsRing
        objectName: "desktop-clock-digital-seconds-ring"
        anchors.fill: parent
        property int second: face.date.getSeconds()
        readonly property real inset: 10
        readonly property real cornerRadius: Math.max(0,
            Math.min(face.cornerRadius - inset, width / 2, height / 2))
        property color progressColor: face.ink(face.ringColor)
        property color trackColor: face.ink(face.ringTrackColor)
        onSecondChanged: requestPaint()
        onProgressColorChanged: requestPaint()
        onTrackColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onCornerRadiusChanged: requestPaint()

        function tickCompleted(index) { return index < second }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const inset = secondsRing.inset
            const width = secondsRing.width - inset * 2
            const height = secondsRing.height - inset * 2
            if (width <= 0 || height <= 0) return
            const radius = secondsRing.cornerRadius
            const perimeter = 2 * (width - radius * 2) + 2 * (height - radius * 2)
                + Math.PI * radius * 2
            ctx.lineWidth = Math.max(1.4, secondsRing.width / 220)
            ctx.lineCap = "round"
            for (let index = 0; index < 60; ++index) {
                const point = face.ringPoint(index * perimeter / 60, width, height, radius)
                ctx.strokeStyle = (secondsRing.tickCompleted(index) ? progressColor : trackColor).toString()
                ctx.beginPath()
                ctx.moveTo(inset + point.x + point.nx * 1.5, inset + point.y + point.ny * 1.5)
                ctx.lineTo(inset + point.x + point.nx * 7, inset + point.y + point.ny * 7)
                ctx.stroke()
            }
        }
    }

    Column {
        objectName: "desktop-clock-digital-content"
        anchors.centerIn: parent
        width: Math.max(0, face.width - face.contentMargin * 2)
        spacing: Math.max(3, face.height * 0.018)

        ShellText {
            width: parent.width
            height: Math.max(18, face.height * 0.12)
            objectName: "desktop-clock-digital-city"
            text: face.city.toUpperCase()
            visible: face.city.length > 0
            color: face.ink(face.cityColor)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 9
            font {
                family: AppearanceTokens.typography.textFamily
                pixelSize: Math.max(11, Math.min(face.width * 0.065, face.height * 0.09))
                weight: Font.Medium
                letterSpacing: 1.2
            }
        }

        ShellText {
            width: parent.width
            height: Math.max(48, face.height * 0.36)
            objectName: "desktop-clock-digital-time"
            text: I18n.fmt(face.date, "HH:mm")
            color: face.ink(face.timeColor)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 20
            font {
                family: AppearanceTokens.typography.displayFamily
                pixelSize: Math.max(28, Math.min(face.width * 0.27, face.height * 0.34))
                weight: Font.Bold
                letterSpacing: -1
            }
        }

        ShellText {
            width: parent.width
            height: Math.max(18, face.height * 0.12)
            objectName: "desktop-clock-digital-offset"
            text: face.formattedOffset()
            color: face.ink(face.offsetColor)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 9
            font {
                family: AppearanceTokens.typography.textFamily
                pixelSize: Math.max(10, Math.min(face.width * 0.06, face.height * 0.08))
                weight: Font.Medium
            }
        }
    }
}
