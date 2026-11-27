import QtQuick
import ".." as Shared

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool inDock: host?.container === "dock"
    readonly property bool verticalDock: inDock && host?.orientation === "vertical"
    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var clockData: liveMode ? (host.clock ?? snapshot) : snapshot
    readonly property bool format24h: host?.settings?.format24h !== false
    property string shapeOverride: ""
    readonly property string surfaceShape: inDock ? "roundedRect" : (shapeOverride || "roundedRect")

    readonly property var pal: appearance?.palette ?? ({})
    readonly property color inkCol: pal.onSurface ?? appearance?.foreground ?? "#1e293b"
    readonly property color accentCol: pal.primary ?? "#3b82f6"
    readonly property color pillBg: Qt.rgba(accentCol.r, accentCol.g, accentCol.b, 0.18)
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")

    readonly property string timeText: {
        const preferred = format24h ? clockData?.time24h : clockData?.time12h
        return String(preferred ?? clockData?.timeText ?? "--:--")
    }
    readonly property int weekdayIndex: Number(clockData?.weekday ?? 0)
    readonly property string weekdayText: {
        const zh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        const en = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        const idx = ((weekdayIndex % 7) + 7) % 7
        return isZh ? zh[idx] : en[idx]
    }
    readonly property string utcOffsetText: {
        const raw = clockData?.utcOffsetMinutes
        const mins = (raw !== undefined && raw !== null && Number.isFinite(Number(raw)))
            ? Math.round(Number(raw))
            : -new Date().getTimezoneOffset()
        if (!Number.isFinite(mins)) return ""
        const sign = mins > 0 ? "+" : mins < 0 ? "-" : "±"
        const absVal = Math.abs(mins)
        const rem = absVal % 60
        return "UTC" + sign + Math.floor(absVal / 60) + (rem ? ":" + (rem < 10 ? "0" : "") + rem : "")
    }

    // Desktop Clover Digital Clock (host paints clover silhouette)
    Column {
        visible: !root.inDock
        anchors.centerIn: parent
        width: Math.max(1, parent.width - 36)
        spacing: 4

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.weekdayText
            color: root.accentCol
            font { pixelSize: 12; weight: Font.Bold; letterSpacing: 1.2 }
        }

        Text {
            width: parent.width
            height: Math.max(34, root.height * 0.30)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 20
            font { pixelSize: 36; weight: Font.Bold; letterSpacing: -0.8 }
            color: root.inkCol
            text: root.timeText
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, offsetText.implicitWidth + 16)
            height: 20
            radius: 10
            color: root.pillBg

            Text {
                id: offsetText
                anchors.centerIn: parent
                text: root.utcOffsetText
                color: root.inkCol
                opacity: 0.90
                font { pixelSize: 10; weight: Font.DemiBold }
            }
        }
    }

    // Dock compact fallback reuses Shared.ClockContent
    Shared.ClockContent {
        visible: root.inDock
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        clockData: root.clockData
        clockStyle: "digital"
        format24h: root.format24h
        inDock: root.inDock
        verticalDock: root.verticalDock
        digitalTimeColor: root.appearance?.foreground ?? "#ffffff"
        digitalSubtleColor: root.appearance?.foreground ?? "#ffffff"
        digitalRingColor: root.appearance?.foreground ?? "#ffffff"
    }
}
