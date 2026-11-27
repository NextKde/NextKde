import QtQuick

Item {
    id: root

    required property var widgetSize
    required property var appearance
    required property var mediaData
    property var host: null
    property bool wavyProgress: false
    property color primaryInk: "#ffffff"
    property color subtleInk: Qt.rgba(1, 1, 1, 0.72)
    property color pillBackground: Qt.rgba(1, 1, 1, 0.14)
    property color playButtonBackground: Qt.rgba(1, 1, 1, 0.24)
    property color playButtonInk: "#ffffff"
    property color progressTrackColor: Qt.rgba(1, 1, 1, 0.22)
    property color progressActiveColor: "#ffffff"

    property var lastActionResult: null
    signal actionRequested(string action, var payload)

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 1
    readonly property int spanRows: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[1]) : 1
    readonly property bool compactSquare: spanCols <= 1 && spanRows <= 1
    readonly property bool compactRow: spanRows <= 1
    readonly property bool largeCard: spanCols >= 2 && spanRows >= 2

    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property bool outlineText: Boolean(appearance?.transparent)
    readonly property int textStyle: outlineText ? Text.Outline : Text.Normal
    readonly property color textStyleColor: appearance?.isDark
        ? Qt.rgba(0, 0, 0, 0.58) : Qt.rgba(1, 1, 1, 0.68)

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
    readonly property string displayLyric: ready ? String(mediaData?.lyric ?? "") : ""

    property string _feedbackText: ""
    function _handleActionResult(result) {
        if (!result || result.ok) {
            _feedbackText = ""
            return
        }
        if (result.code === "unavailable" && !root.ready) {
            _feedbackText = ""
            return
        }
        _feedbackText = result.code === "unavailable"
            ? (root.isZh ? "当前播放器不可用" : "Player unavailable")
            : String(result.message || (root.isZh ? "操作失败" : "Action failed"))
        feedbackClearTimer.restart()
    }
    function triggerAction(action, payload) {
        if (host && typeof host.invokeAction === "function") {
            _handleActionResult(host.invokeAction(action, payload))
            return
        }
        actionRequested(action, payload)
    }
    onLastActionResultChanged: _handleActionResult(lastActionResult)

    function formatSeconds(total) {
        const value = Math.max(0, Math.floor(Number(total) || 0))
        const mins = Math.floor(value / 60)
        const secs = value % 60
        return mins + ":" + (secs < 10 ? "0" + secs : String(secs))
    }

    Timer {
        id: feedbackClearTimer
        interval: 2600
        onTriggered: root._feedbackText = ""
    }

    // Whole-card click opens/raises the active player (or launches music app when idle).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.triggerAction("media.raise-player", {})
    }

    // Floating musical notes when actively playing.
    Item {
        id: musicNotes
        anchors { right: parent.right; top: parent.top; rightMargin: 16; topMargin: 12 }
        width: 56
        height: 48
        clip: true
        z: 2
        readonly property bool running: root.playing && Boolean(root.host ? root.host.active : true)
        visible: running && !root.compactSquare

        Repeater {
            model: ["♪", "♫", "♪"]
            delegate: Text {
                required property var modelData
                required property int index
                readonly property var offsets: [2, 24, 42]
                x: offsets[index]
                text: modelData
                color: Qt.rgba(root.primaryInk.r, root.primaryInk.g, root.primaryInk.b, 0.56)
                font { pixelSize: index === 1 ? 16 : 13; weight: Font.DemiBold }
                SequentialAnimation on y {
                    running: musicNotes.running
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 620 }
                    NumberAnimation { from: musicNotes.height - 12; to: -18; duration: 2200 + index * 180; easing.type: Easing.OutSine }
                }
                SequentialAnimation on opacity {
                    running: musicNotes.running
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 620 }
                    NumberAnimation { from: 0; to: 0.64; duration: 360 }
                    NumberAnimation { from: 0.64; to: 0; duration: 1840 + index * 180; easing.type: Easing.InSine }
                }
            }
        }
    }

    Item {
        id: musicBody
        anchors.fill: parent
        anchors.margins: root.compactSquare ? 12 : (root.compactRow ? 14 : 18)
        readonly property real splitGap: root.largeCard ? 16 : 12

        Item {
            id: coverPane
            x: 0
            y: 0
            width: root.compactSquare ? parent.width : (parent.width - musicBody.splitGap) * 0.34
            height: root.compactSquare ? Math.min(parent.width * 0.72, parent.height * 0.42) : parent.height

            Rectangle {
                id: coverBox
                anchors.centerIn: parent
                width: Math.min(coverPane.width, coverPane.height)
                height: width
                radius: Math.max(8, Math.round(width * 0.12))
                clip: true
                color: root.pillBackground

                Image {
                    anchors.fill: parent
                    source: root.ready ? String(root.mediaData?.artworkUrl ?? "") : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: root.ready && status === Image.Ready
                    asynchronous: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: !root.ready || !root.mediaData?.artworkUrl
                    text: "♫"
                    color: Qt.rgba(root.primaryInk.r, root.primaryInk.g, root.primaryInk.b, root.ready ? 0.88 : 0.48)
                    font { pixelSize: Math.max(16, Math.floor(coverBox.height * 0.44)); weight: Font.DemiBold }
                }
            }
        }

        Item {
            id: detailsPane
            x: root.compactSquare ? 0 : (coverPane.width + musicBody.splitGap)
            y: root.compactSquare ? (coverPane.height + 6) : 0
            width: parent.width - x
            height: parent.height - y

            Item {
                id: metadataArea
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    bottom: progressSection.visible ? progressSection.top : controlsRow.top
                    bottomMargin: root.compactSquare ? 4 : 6
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: root.largeCard ? 4 : 2

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.displayTitle
                        color: root.primaryInk
                        font {
                            pixelSize: root.compactSquare ? 12 : (root.largeCard ? 17 : 14)
                            weight: Font.DemiBold
                        }
                        elide: Text.ElideRight
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                    Text {
                        width: parent.width
                        visible: !root.compactSquare && root.displayArtist.length > 0
                        horizontalAlignment: Text.AlignHCenter
                        text: root.displayArtist
                        color: root.subtleInk
                        font.pixelSize: root.largeCard ? 13 : 11
                        elide: Text.ElideRight
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                    Text {
                        width: parent.width
                        visible: root.largeCard && root.displayLyric.length > 0
                        horizontalAlignment: Text.AlignHCenter
                        text: root.displayLyric
                        color: Qt.rgba(root.primaryInk.r, root.primaryInk.g, root.primaryInk.b, 0.84)
                        font { pixelSize: 11; weight: Font.Medium }
                        elide: Text.ElideRight
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                }
            }

            // Progress bar (thin track on 2x1, full/wavy track with timestamps on 2x2)
            Item {
                id: progressSection
                visible: !root.compactSquare && root.ready && Number(root.mediaData?.lengthSeconds ?? 0) > 0
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: controlsRow.top
                    bottomMargin: root.compactRow ? 8 : 12
                }
                height: root.compactRow ? 4 : 24

                Rectangle {
                    id: trackBg
                    visible: !(root.wavyProgress && root.largeCard)
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: root.compactRow ? 4 : 5
                    radius: height / 2
                    color: root.progressTrackColor

                    Rectangle {
                        width: parent.width * root.progress
                        height: parent.height
                        radius: parent.radius
                        color: root.progressActiveColor
                    }
                }

                Canvas {
                    id: wavyCanvas
                    visible: root.wavyProgress && root.largeCard
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 10
                    property real phase: 0
                    readonly property bool shouldAnimate: visible && root.playing
                        && Boolean(root.host ? root.host.active : true)

                    NumberAnimation on phase {
                        from: 0
                        to: Math.PI * 2
                        duration: 1800
                        loops: Animation.Infinite
                        running: wavyCanvas.shouldAnimate
                    }
                    onPhaseChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    Connections {
                        target: root
                        function onProgressChanged() { wavyCanvas.requestPaint() }
                        function onProgressActiveColorChanged() { wavyCanvas.requestPaint() }
                    }
                    Component.onCompleted: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const w = width
                        const h = height
                        if (w <= 0 || h <= 0) return
                        const cy = h / 2
                        const splitX = Math.max(0, Math.min(w, w * root.progress))
                        ctx.lineCap = "round"
                        ctx.lineWidth = 2.6

                        if (splitX < w) {
                            ctx.strokeStyle = root.progressTrackColor.toString()
                            ctx.beginPath()
                            ctx.moveTo(splitX, cy)
                            ctx.lineTo(w, cy)
                            ctx.stroke()
                        }

                        if (splitX > 1) {
                            ctx.strokeStyle = root.progressActiveColor.toString()
                            ctx.beginPath()
                            const amp = 2.2
                            const wl = 14
                            for (let x = 0; x <= splitX; x += 2) {
                                const y = cy + Math.sin((x / wl) * Math.PI * 2 - phase) * amp
                                if (x === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.stroke()
                        }
                    }
                }

                Text {
                    visible: !root.compactRow
                    anchors { left: parent.left; bottom: parent.bottom }
                    text: root.formatSeconds(root.mediaData?.positionSeconds)
                    color: root.subtleInk
                    font.pixelSize: 10
                }
                Text {
                    visible: !root.compactRow
                    anchors { right: parent.right; bottom: parent.bottom }
                    text: root.formatSeconds(root.mediaData?.lengthSeconds)
                    color: root.subtleInk
                    font.pixelSize: 10
                }
            }

            // Playback controls (always shown, muted when disabled/idle)
            Row {
                id: controlsRow
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                }
                spacing: root.compactSquare ? 8 : (root.compactRow ? 12 : 16)

                Repeater {
                    model: [
                        { action: "media.previous", label: "⏮", enabled: root.ready && Boolean(root.mediaData?.canPrevious), primary: false },
                        { action: "media.toggle-play-pause", label: root.playing ? "⏸" : "▶", enabled: root.ready && Boolean(root.mediaData?.canTogglePlayPause), primary: true },
                        { action: "media.next", label: "⏭", enabled: root.ready && Boolean(root.mediaData?.canNext), primary: false }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: root.compactSquare
                            ? (modelData.primary ? 32 : 28)
                            : (root.compactRow ? (modelData.primary ? 38 : 34) : (modelData.primary ? 46 : 40))
                        height: root.compactSquare
                            ? (modelData.primary ? 32 : 28)
                            : (root.compactRow ? (modelData.primary ? 38 : 34) : (modelData.primary ? 46 : 40))
                        radius: height / 2
                        color: modelData.primary ? root.playButtonBackground : root.pillBackground
                        opacity: modelData.enabled ? (btnArea.pressed ? 0.65 : 1.0) : 0.42

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: modelData.primary ? root.playButtonInk : root.primaryInk
                            font {
                                pixelSize: root.compactSquare
                                    ? (modelData.primary ? 13 : 11)
                                    : (root.compactRow ? (modelData.primary ? 15 : 13) : (modelData.primary ? 18 : 15))
                                weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            id: btnArea
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            enabled: modelData.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerAction(modelData.action, {})
                        }
                    }
                }
            }
        }

        // Inline action error banner
        Rectangle {
            visible: root._feedbackText.length > 0
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 2 }
            width: Math.min(parent.width, feedbackLabel.implicitWidth + 16)
            height: 22
            radius: 11
            color: Qt.rgba(0.15, 0.12, 0.18, 0.85)
            Text {
                id: feedbackLabel
                anchors.centerIn: parent
                text: root._feedbackText
                color: "white"
                font { pixelSize: 10; weight: Font.DemiBold }
            }
        }
    }
}
