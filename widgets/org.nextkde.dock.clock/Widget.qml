import QtQuick

// Dock clock card: restored original DockClockWidget 2-column layout with big
// HH:mm:ss + date/weekday on the left (60%) and Sunset/Sunrise on the right (40%).
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool vertical: host?.orientation === "vertical"
    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var clockData: liveMode ? (host.clock ?? snapshot) : snapshot
    readonly property var weatherData: liveMode ? host.weather : snapshot
    readonly property bool format24h: host?.settings?.format24h !== false
    readonly property bool material: appearance?.style === "material"
    readonly property var pal: appearance?.palette ?? ({})
    readonly property color ink: material ? (pal.onSurface ?? "#1e293b") : "white"
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")

    // macOS slot paint (ignored by the Material host slot).
    readonly property var backgroundSpec: ({
        startColor: Qt.rgba(0.30, 0.38, 0.55, 0.74),
        endColor: Qt.rgba(0.42, 0.36, 0.60, 0.58),
        orientation: "horizontal"
    })

    function pad(n) { return (n < 10 ? "0" : "") + n }

    readonly property string timeShortText: String((format24h ? clockData?.time24h : clockData?.time12h)
        ?? clockData?.time24h ?? "--:--")
    readonly property string secondsText: pad(Number(clockData?.seconds ?? 0))
    readonly property string timeFullText: format24h
        ? (timeShortText.length >= 5 ? (timeShortText + ":" + secondsText) : timeShortText)
        : timeShortText
    readonly property string weekdayText: {
        const zh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        const en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        const idx = (((Number(clockData?.weekday ?? 0)) % 7) + 7) % 7
        return isZh ? zh[idx] : en[idx]
    }
    readonly property string fullDateText: {
        const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(clockData?.isoDate ?? ""))
        if (!m) return weekdayText
        return isZh
            ? (m[1] + "年" + Number(m[2]) + "月" + Number(m[3]) + "日 " + weekdayText)
            : (m[1] + "-" + m[2] + "-" + m[3] + " " + weekdayText)
    }
    readonly property string sunsetText: {
        const v = liveMode ? weatherData?.sunsetTime : snapshot?.sunsetTime
        return v && String(v).length > 0 ? String(v) : "--:--"
    }
    readonly property string sunriseText: {
        const v = liveMode ? weatherData?.sunriseTime : snapshot?.sunriseTime
        return v && String(v).length > 0 ? String(v) : "--:--"
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.liveMode) root.host.invokeAction("app.open-calendar", { view: "today" })
    }

    // ── Horizontal Dock: Time + Full Date (left) / Sunset & Sunrise (right) ─
    Item {
        visible: !root.vertical
        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }

        Column {
            id: leftCol
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: Math.round(parent.width * 0.58)
            height: Math.round(root.height * 0.88)
            spacing: Math.max(1, Math.round(root.height * 0.03))

            Text {
                width: parent.width
                height: Math.round(parent.height * 0.64)
                text: root.timeFullText
                color: root.ink
                style: root.material ? Text.Normal : Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.28)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 11
                font {
                    pixelSize: Math.max(15, Math.round(root.height * 0.43))
                    weight: Font.DemiBold
                    letterSpacing: 0.4
                }
            }

            Text {
                width: parent.width
                height: Math.round(parent.height * 0.30)
                text: root.fullDateText
                color: root.ink
                opacity: 0.82
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 7
                font {
                    pixelSize: Math.max(8, Math.round(root.height * 0.21))
                    weight: Font.Medium
                }
            }
        }

        Column {
            anchors {
                left: leftCol.right
                leftMargin: 4
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            height: Math.round(root.height * 0.88)
            spacing: 0

            Repeater {
                model: [
                    { label: root.isZh ? "日落" : "Sunset", value: root.sunsetText },
                    { label: root.isZh ? "日出" : "Sunrise", value: root.sunriseText }
                ]
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: parent.height / 2

                    Row {
                        anchors.centerIn: parent
                        spacing: Math.max(2, Math.round(root.height * 0.05))
                        Text {
                            text: modelData.label
                            color: root.ink
                            opacity: 0.72
                            font { pixelSize: Math.max(8, Math.round(root.height * 0.19)); weight: Font.Medium }
                        }
                        Text {
                            text: modelData.value
                            color: root.ink
                            opacity: modelData.value === "--:--" ? 0.48 : 0.92
                            font { pixelSize: Math.max(8, Math.round(root.height * 0.20)); weight: Font.DemiBold }
                        }
                    }
                }
            }
        }
    }

    // ── Side Dock ────────────────────────────────────────────────────────
    Text {
        visible: root.vertical
        anchors.centerIn: parent
        text: root.timeShortText
        color: root.ink
        fontSizeMode: Text.HorizontalFit
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        minimumPixelSize: 6
        font { pixelSize: Math.max(10, Math.round(root.height * 0.5)); weight: Font.DemiBold }
    }
}
