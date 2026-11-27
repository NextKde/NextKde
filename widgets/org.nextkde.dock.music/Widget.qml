import QtQuick
import QtQuick.Effects

// Dock music card. Host owns the slot shell; macOS paints cover colours via
// `backgroundSpec`. Hidden while no MPRIS player exists.
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool vertical: host?.orientation === "vertical"
    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var mediaData: liveMode ? (host.media ?? snapshot) : snapshot
    readonly property bool material: appearance?.style === "material"
    readonly property var pal: appearance?.palette ?? ({})
    readonly property color ink: material ? (pal.onSurface ?? "#1e293b") : "white"
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property bool hasPlayer: Boolean(mediaData?.hasPlayer)
    readonly property bool playing: hasPlayer && Boolean(mediaData?.playing)
    readonly property string artworkUrl: String(mediaData?.artworkUrl ?? "")

    readonly property var backgroundSpec: {
        const colors = mediaData?.artworkColors
        if (!colors || !colors.ready) return null
        return {
            startColor: Qt.alpha(Qt.color(String(colors.primary)), 0.82),
            midColor: Qt.alpha(Qt.color(String(colors.secondary)), 0.64),
            endColor: Qt.alpha(Qt.color(String(colors.primary)), 0.38),
            orientation: "horizontal"
        }
    }

    function act(action) {
        if (liveMode) host.invokeAction(action, {})
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.act("media.raise-player")
    }

    Row {
        visible: !root.vertical
        anchors.fill: parent
        anchors.margins: 2
        spacing: Math.round(root.height * 0.18)

        Item {
            id: artBox
            width: parent.height
            height: parent.height

            Rectangle {
                id: artMask
                anchors.fill: parent
                radius: 6
                visible: false
                layer.enabled: true
            }

            Image {
                id: art
                anchors.fill: parent
                source: root.artworkUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                visible: root.artworkUrl.length > 0 && status === Image.Ready
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: artMask
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 6
                visible: !art.visible
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)
                Text {
                    anchors.centerIn: parent
                    text: "♫"
                    color: root.ink
                    font { pixelSize: Math.round(parent.height * 0.5); weight: Font.Bold }
                }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1, parent.width - artBox.width - controls.width - parent.spacing * 2)
            Text {
                width: parent.width
                text: String(root.mediaData?.title || (root.isZh ? "未在播放" : "Nothing playing"))
                color: root.ink
                elide: Text.ElideRight
                font { pixelSize: Math.max(10, Math.round(root.height * 0.30)); weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                text: String(root.mediaData?.artist || "")
                color: root.ink
                opacity: 0.70
                elide: Text.ElideRight
                font { pixelSize: Math.max(8, Math.round(root.height * 0.25)); weight: Font.Medium }
            }
        }

        Row {
            id: controls
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(root.height * 0.10)
            Repeater {
                model: [
                    { glyph: "⏮", action: "media.previous" },
                    { glyph: root.playing ? "⏸" : "▶", action: "media.toggle-play-pause" },
                    { glyph: "⏭", action: "media.next" }
                ]
                delegate: Item {
                    required property var modelData
                    width: Math.round(root.height * 0.46)
                    height: width
                    Text {
                        anchors.centerIn: parent
                        text: modelData.glyph
                        color: root.ink
                        font.pixelSize: Math.max(10, Math.round(root.height * 0.30))
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act(modelData.action)
                    }
                }
            }
        }
    }

    Text {
        visible: root.vertical
        anchors.centerIn: parent
        text: "♫"
        color: root.ink
        font { pixelSize: Math.max(12, Math.round(root.height * 0.5)); weight: Font.Bold }
    }
}
