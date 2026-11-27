import QtQuick
import QtQuick.Effects

// Hover detail: full now-playing surface with artwork ambient tint & seekable
// progress bar. Host owns the popup shell (300px wide).
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var mediaData: liveMode ? (host.media ?? snapshot) : snapshot
    readonly property bool material: appearance?.style === "material"
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property var pal: material ? (appearance?.palette ?? ({})) : ({})
    readonly property color ink: material
        ? (pal.onSurface ?? appearance?.foreground ?? "#1e293b")
        : (appearance?.foreground ?? (appearance?.isDark ? "#fbfcff" : "#0e1015"))
    readonly property color accent: material
        ? (pal.primary ?? "#2563eb")
        : (appearance?.isDark ? "#ffffff" : "#007aff")
    readonly property color accentInk: material
        ? (pal.onPrimary ?? "#ffffff")
        : (appearance?.isDark ? "#111318" : "#ffffff")
    readonly property string artworkUrl: String(mediaData?.artworkUrl ?? "")
    readonly property bool playing: Boolean(mediaData?.hasPlayer) && Boolean(mediaData?.playing)
    readonly property bool canSeek: Boolean(mediaData?.canSeek)
    readonly property real lengthSeconds: Number(mediaData?.lengthSeconds ?? 0)
    readonly property real progress: lengthSeconds > 0
        ? Math.max(0, Math.min(1, Number(mediaData?.positionSeconds ?? 0) / lengthSeconds))
        : 0

    function fmt(seconds) {
        const v = Math.max(0, Math.floor(Number(seconds) || 0))
        return Math.floor(v / 60) + ":" + String(v % 60).padStart(2, "0")
    }
    function act(action, payload) {
        if (liveMode) host.invokeAction(action, payload ?? ({}))
    }
    function artTint(hexStr, alpha) {
        if (!hexStr || String(hexStr).length === 0) return "transparent"
        return Qt.alpha(Qt.color(String(hexStr)), alpha)
    }

    implicitHeight: col.implicitHeight + 28

    // Cover-art ambient horizontal wash inside the host popup shell (macOS mode)
    Rectangle {
        anchors.fill: parent
        radius: 18
        visible: !root.material && Boolean(root.mediaData?.artworkColors?.ready)
        color: "transparent"
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root.artTint(root.mediaData?.artworkColors?.primary, 0.28) }
            GradientStop { position: 0.52; color: root.artTint(root.mediaData?.artworkColors?.secondary, 0.20) }
            GradientStop { position: 1.0; color: root.artTint(root.mediaData?.artworkColors?.primary, 0.10) }
        }
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 10

        Row {
            width: parent.width
            spacing: 12

            Item {
                width: 72
                height: 72

                Rectangle {
                    id: coverMask
                    anchors.fill: parent
                    radius: 8
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
                        maskSource: coverMask
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    visible: !art.visible
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.14)
                    Text {
                        anchors.centerIn: parent
                        text: "♫"
                        color: root.accent
                        font { pixelSize: 30; weight: Font.Bold }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.act("media.raise-player")
                }
            }

            Column {
                width: parent.width - 84
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    width: parent.width
                    text: String(root.mediaData?.title || (root.isZh ? "未播放曲目" : "No track playing"))
                    color: root.ink
                    elide: Text.ElideRight
                    font { pixelSize: 16; weight: Font.Bold }
                }
                Text {
                    width: parent.width
                    text: String(root.mediaData?.artist || (root.isZh ? "未知艺术家" : "Unknown artist"))
                    color: root.ink
                    opacity: 0.72
                    elide: Text.ElideRight
                    font.pixelSize: 12
                }
                Text {
                    width: parent.width
                    text: String(root.mediaData?.album || "")
                    color: root.ink
                    opacity: 0.62
                    elide: Text.ElideRight
                    font.pixelSize: 11
                }
            }
        }

        Item {
            id: progressArea
            width: parent.width
            height: 20

            Rectangle {
                id: track
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4 }
                height: 4
                radius: 2
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.22)
                Rectangle {
                    width: track.width * root.progress
                    height: parent.height
                    radius: 2
                    color: root.accent
                }
            }

            MouseArea {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 14
                acceptedButtons: Qt.LeftButton
                cursorShape: root.liveMode && root.canSeek && root.lengthSeconds > 0
                    ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: function(mouse) {
                    if (!root.liveMode || !root.canSeek || root.lengthSeconds <= 0 || width <= 0)
                        return
                    const ratio = Math.max(0, Math.min(1, mouse.x / width))
                    root.act("media.seek", { positionSeconds: Math.round(ratio * root.lengthSeconds) })
                }
            }

            Text {
                anchors { left: parent.left; bottom: parent.bottom }
                text: root.fmt(root.mediaData?.positionSeconds)
                color: root.ink
                opacity: 0.6
                font.pixelSize: 10
            }
            Text {
                anchors { right: parent.right; bottom: parent.bottom }
                text: root.fmt(root.lengthSeconds)
                color: root.ink
                opacity: 0.6
                font.pixelSize: 10
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18
            Repeater {
                model: [
                    { glyph: "⏮", action: "media.previous", size: 32 },
                    { glyph: root.playing ? "⏸" : "▶", action: "media.toggle-play-pause", size: 40 },
                    { glyph: "⏭", action: "media.next", size: 32 }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: modelData.size
                    height: modelData.size
                    radius: width / 2
                    color: modelData.size > 32 ? root.accent : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.14)
                    Text {
                        anchors.centerIn: parent
                        text: modelData.glyph
                        color: modelData.size > 32 ? root.accentInk : root.ink
                        font.pixelSize: modelData.size > 32 ? 16 : 13
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

        Text {
            width: parent.width
            visible: String(root.mediaData?.lyric ?? "").length > 0
            text: String(root.mediaData?.lyric ?? "")
            color: root.ink
            opacity: 0.78
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 12
        }
    }
}
