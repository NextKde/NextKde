import QtQuick
import ".." as Shared

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 2
    readonly property bool compact: spanCols <= 1
    // 1x1 uses host-owned slantedOval silhouette; 2x1 and 3x1 keep standard roundedRect.
    readonly property string surfaceShape: compact ? "slantedOval" : "roundedRect"

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var weatherData: liveMode ? (host.weather ?? snapshot) : snapshot
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")

    readonly property var pal: appearance?.palette ?? ({})
    readonly property color onSurface: pal.onSurface ?? appearance?.foreground ?? "#1e293b"
    readonly property color onSurfaceVariant: pal.onSurfaceVariant ?? "#64748b"
    readonly property color accentCol: pal.primary ?? "#2563eb"

    readonly property string status: String(weatherData?.status ?? "unavailable")
    readonly property bool ready: status === "ready" || Boolean(weatherData?.available)
    readonly property bool loading: status === "loading" || Boolean(weatherData?.loading)

    // ── 1x1 Slanted Oval Weather Foreground (host paints surface) ────────
    Item {
        id: compactShape
        visible: root.compact
        anchors.fill: parent

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!root.host || root.host.isPreview || typeof root.host.invokeAction !== "function")
                    return
                const locId = String(root.weatherData?.locationId ?? "")
                root.host.invokeAction("app.open-weather", locId ? ({ location: locId }) : ({}))
            }
        }

        Column {
            visible: root.ready
            anchors.centerIn: parent
            width: Math.max(1, parent.width - 36)
            spacing: 2

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: String(root.weatherData?.conditionSymbol || "☀")
                color: root.accentCol
                font.pixelSize: 28
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: String(root.weatherData?.temperatureText || "--°")
                color: root.onSurface
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 22
                font { pixelSize: 36; weight: Font.Bold }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: String(root.weatherData?.locationName || (root.isZh ? "本地" : "Local"))
                color: root.onSurface
                font { pixelSize: 13; weight: Font.DemiBold }
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: String(root.weatherData?.conditionText || "")
                color: root.onSurfaceVariant
                font { pixelSize: 12; weight: Font.Medium }
                elide: Text.ElideRight
            }
        }

        Text {
            visible: !root.ready
            anchors.centerIn: parent
            width: Math.max(1, parent.width - 36)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.loading ? (root.isZh ? "更新中…" : "Updating…") : (root.isZh ? "不可用" : "Unavailable")
            color: root.onSurface
            font { pixelSize: 13; weight: Font.DemiBold }
        }
    }

    // ── 2x1 / 3x1 Standard Material Tonal Card ───────────────────────────
    Shared.WeatherContent {
        visible: !root.compact
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        weatherData: root.weatherData
        host: root.host
        showAmbientArtwork: false
        primaryInk: root.onSurface
        subtleInk: root.onSurfaceVariant
        accentInk: root.accentCol
    }
}
