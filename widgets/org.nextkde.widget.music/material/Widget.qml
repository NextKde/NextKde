import QtQuick

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null
    property var lastActionResult: null
    signal actionRequested(string action, var payload)

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 2
    readonly property bool compactSquare: spanCols <= 1
    // 1x1 defaults to standard roundedRect; expressive wrappers pass shapeOverride.
    property string shapeOverride: ""
    readonly property string surfaceShape: compactSquare ? (shapeOverride || "roundedRect") : "roundedRect"

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var mediaData: liveMode ? (host.media ?? snapshot) : snapshot
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")

    readonly property var pal: appearance?.palette ?? ({})
    readonly property color onSurface: pal.onSurface ?? appearance?.foreground ?? "#1e293b"
    readonly property color onSurfaceVariant: pal.onSurfaceVariant ?? "#64748b"
    readonly property color primaryCol: pal.primary ?? "#2563eb"
    readonly property color onPrimaryCol: pal.onPrimary ?? "#ffffff"
    readonly property color chipBg: Qt.rgba(onSurface.r, onSurface.g, onSurface.b, 0.14)
    readonly property color trackCol: Qt.rgba(onSurface.r, onSurface.g, onSurface.b, 0.22)

    readonly property string status: String(mediaData?.status ?? "idle")
    readonly property bool ready: status === "ready" && Boolean(mediaData?.hasPlayer)
    readonly property bool playing: ready && Boolean(mediaData?.playing)
    readonly property real progress: (ready && Number(mediaData?.lengthSeconds ?? 0) > 0)
        ? Math.max(0, Math.min(1, Number(mediaData?.positionSeconds ?? 0) / Number(mediaData.lengthSeconds)))
        : 0
    readonly property string displayTitle: {
        const title = String(mediaData?.title ?? "").trim()
        if (ready && title.length > 0) return title
        return isZh ? "未在播放" : "Nothing playing"
    }
    readonly property string displayArtist: ready ? String(mediaData?.artist || mediaData?.album || "") : ""
    readonly property string artworkUrl: ready ? String(mediaData?.artworkUrl ?? "") : ""

    function triggerAction(action, payload) {
        if (host && typeof host.invokeAction === "function")
            return host.invokeAction(action, payload)
        actionRequested(action, payload)
        return null
    }

    component CircleArtBadge: Item {
        property string url: ""

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.chipBg

            Image {
                id: artImg
                anchors.centerIn: parent
                width: parent.width * 0.72
                height: width
                source: parent.parent.url
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true
                visible: parent.parent.url.length > 0 && status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: !artImg.visible
                text: "♫"
                color: root.primaryCol
                font { pixelSize: Math.max(16, Math.round(parent.width * 0.44)); weight: Font.Bold }
            }
        }
    }

    // ── 1x1 Cookie8Sided Foreground (host paints cookie surface) ─────────
    Item {
        visible: root.compactSquare
        anchors.fill: parent

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.triggerAction("media.raise-player", {})
        }

        Column {
            anchors.centerIn: parent
            width: Math.max(1, parent.width - 32)
            spacing: 7

            CircleArtBadge {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 46; height: 46
                url: root.artworkUrl
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.displayTitle
                color: root.onSurface
                font { pixelSize: 13; weight: Font.DemiBold }
                elide: Text.ElideRight
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Rectangle {
                    width: 26; height: 26; radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.chipBg
                    Text {
                        anchors.centerIn: parent
                        text: "⏮"
                        color: root.onSurface
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.triggerAction("media.previous", {})
                    }
                }

                Rectangle {
                    width: 32; height: 32; radius: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.primaryCol
                    Text {
                        anchors.centerIn: parent
                        text: root.playing ? "⏸" : "▶"
                        color: root.onPrimaryCol
                        font.pixelSize: 14
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.triggerAction("media.toggle-play-pause", {})
                    }
                }

                Rectangle {
                    width: 26; height: 26; radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.chipBg
                    Text {
                        anchors.centerIn: parent
                        text: "⏭"
                        color: root.onSurface
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.triggerAction("media.next", {})
                    }
                }
            }
        }
    }

    // ── 2x1 Unified Material Card Layout ─────────────────────────────────
    Item {
        visible: !root.compactSquare
        anchors.fill: parent

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.triggerAction("media.raise-player", {})
        }

        Item {
            anchors.fill: parent
            anchors.margins: 16

            CircleArtBadge {
                id: vinylArt
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: Math.max(56, Math.min(parent.height, parent.width * 0.34))
                height: width
                url: root.artworkUrl
            }

            Item {
                anchors {
                    left: vinylArt.right; leftMargin: 14
                    right: parent.right; top: parent.top; bottom: parent.bottom
                }

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.displayTitle
                        color: root.onSurface
                        font { pixelSize: 15; weight: Font.Bold }
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: root.displayArtist.length > 0
                        text: root.displayArtist
                        color: root.onSurfaceVariant
                        font { pixelSize: 12; weight: Font.Medium }
                        elide: Text.ElideRight
                    }
                }

                // M3 Expressive wavy progress canvas
                Canvas {
                    id: wavyBar
                    anchors { left: parent.left; right: parent.right; bottom: controlsRow.top; bottomMargin: 10 }
                    height: 12
                    readonly property real ratio: root.progress
                    readonly property color colActive: root.primaryCol
                    readonly property color colTrack: root.trackCol
                    onRatioChanged: requestPaint()
                    onColActiveChanged: requestPaint()
                    onColTrackChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        if (width <= 4 || height <= 2) return
                        const cy = height / 2
                        const splitX = Math.max(0, Math.min(width, width * ratio))

                        if (splitX < width) {
                            ctx.strokeStyle = colTrack.toString()
                            ctx.lineWidth = 2.5
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(splitX, cy)
                            ctx.lineTo(width, cy)
                            ctx.stroke()
                        }

                        if (splitX > 2) {
                            ctx.strokeStyle = colActive.toString()
                            ctx.lineWidth = 2.8
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                            const amp = 2.8
                            const freq = 0.24
                            for (let x = 0; x <= splitX; x += 2) {
                                const y = cy + Math.sin(x * freq) * amp
                                if (x === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.stroke()
                        }
                    }
                }

                Row {
                    id: controlsRow
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    spacing: 12

                    Rectangle {
                        width: 32; height: 32; radius: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.chipBg
                        Text {
                            anchors.centerIn: parent
                            text: "⏮"
                            color: root.onSurface
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerAction("media.previous", {})
                        }
                    }

                    Rectangle {
                        width: 52; height: 34; radius: 17
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.primaryCol
                        Text {
                            anchors.centerIn: parent
                            text: root.playing ? "⏸" : "▶"
                            color: root.onPrimaryCol
                            font.pixelSize: 15
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerAction("media.toggle-play-pause", {})
                        }
                    }

                    Rectangle {
                        width: 32; height: 32; radius: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.chipBg
                        Text {
                            anchors.centerIn: parent
                            text: "⏭"
                            color: root.onSurface
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerAction("media.next", {})
                        }
                    }
                }
            }
        }
    }
}
