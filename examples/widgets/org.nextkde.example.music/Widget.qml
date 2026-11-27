import QtQuick

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null
    property var lastActionResult: null
    signal actionRequested(string action, var payload)

    readonly property var media: (host && !host.isPreview && host.media) ? host.media : snapshot
    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 1
    readonly property int spanRows: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[1]) : 1
    readonly property bool compactSquare: spanCols <= 1 && spanRows <= 1
    readonly property bool compactRow: spanRows <= 1
    readonly property bool largeCard: spanCols >= 2 && spanRows >= 2
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")

    readonly property string status: String(media?.status ?? "idle")
    readonly property bool ready: status === "ready" && Boolean(media?.hasPlayer)
    readonly property bool playing: ready && Boolean(media?.playing)
    readonly property real progress: (ready && Number(media?.lengthSeconds ?? 0) > 0)
        ? Math.max(0, Math.min(1, Number(media?.positionSeconds ?? 0) / Number(media.lengthSeconds)))
        : 0
    readonly property string displayTitle: {
        const title = String(media?.title ?? "").trim()
        if (ready && title.length > 0) return title
        return isZh ? "未在播放" : "Nothing playing"
    }
    readonly property string displayArtist: ready ? String(media?.artist || media?.album || "") : ""
    readonly property string displayLyric: ready ? String(media?.lyric ?? "") : ""

    function blendHex(hex, targetHex, ratio) {
        const parse = str => {
            const s = String(str ?? "").replace(/^#/, "")
            const full = s.length === 8 ? s.slice(2) : s
            if (full.length !== 6) return null
            const r = parseInt(full.slice(0, 2), 16)
            const g = parseInt(full.slice(2, 4), 16)
            const b = parseInt(full.slice(4, 6), 16)
            if (isNaN(r) || isNaN(g) || isNaN(b)) return null
            return [r, g, b]
        }
        const a = parse(hex)
        const b = parse(targetHex)
        if (!a || !b) return targetHex
        const t = Math.max(0, Math.min(1, ratio))
        const toHex = n => {
            const clamped = Math.max(0, Math.min(255, Math.round(n)))
            return (clamped < 16 ? "0" : "") + clamped.toString(16)
        }
        return "#"
            + toHex(a[0] + (b[0] - a[0]) * t)
            + toHex(a[1] + (b[1] - a[1]) * t)
            + toHex(a[2] + (b[2] - a[2]) * t)
    }

    readonly property bool _lightForeground: {
        const fg = appearance?.foreground
        if (fg && typeof fg.r === "number")
            return (fg.r * 0.2126 + fg.g * 0.7152 + fg.b * 0.0722) >= 0.5
        return Boolean(appearance?.isDark)
    }

    readonly property var backgroundSpec: {
        const colors = media?.artworkColors
        if (ready && colors?.ready && colors.primary && colors.secondary) {
            if (_lightForeground) {
                return {
                    orientation: "horizontal",
                    startColor: blendHex(colors.primary, "#14101c", 0.24),
                    midColor: blendHex(colors.secondary, "#14101c", 0.36),
                    midPosition: 0.52,
                    endColor: blendHex(colors.primary, "#0f0d16", 0.58)
                }
            }
            return {
                orientation: "horizontal",
                startColor: blendHex(colors.primary, "#ffffff", 0.42),
                midColor: blendHex(colors.secondary, "#ffffff", 0.52),
                midPosition: 0.52,
                endColor: blendHex(colors.primary, "#f4f6fb", 0.66)
            }
        }
        return _lightForeground
            ? ({ orientation: "horizontal", startColor: "#4b327a", midColor: "#2b3b6b", midPosition: 0.52, endColor: "#221b40" })
            : ({ orientation: "horizontal", startColor: "#efe4ff", midColor: "#e6e8ff", midPosition: 0.52, endColor: "#dcebff" })
    }

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

    readonly property color fg: root.appearance.foreground
    readonly property color subtleFg: Qt.rgba(fg.r, fg.g, fg.b, 0.72)
    readonly property color pillBg: root.appearance.transparent
        ? Qt.rgba(fg.r, fg.g, fg.b, 0.16)
        : (root.appearance.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
    readonly property int textStyle: root.appearance.transparent ? Text.Outline : Text.Normal
    readonly property color textStyleColor: root.appearance.isDark
        ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.65)

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
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.56)
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
                color: root.pillBg

                Image {
                    anchors.fill: parent
                    source: root.ready ? String(root.media?.artworkUrl ?? "") : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: root.ready && status === Image.Ready
                    asynchronous: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: !root.ready || !root.media?.artworkUrl
                    text: "♫"
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.ready ? 0.88 : 0.48)
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
                        color: root.fg
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
                        color: root.subtleFg
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
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.84)
                        font { pixelSize: 11; weight: Font.Medium }
                        elide: Text.ElideRight
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                }
            }

            // Progress bar (thin track on 2x1, full bar with timestamps on 2x2).
            Item {
                id: progressSection
                visible: !root.compactSquare && root.ready && Number(root.media?.lengthSeconds ?? 0) > 0
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: controlsRow.top
                    bottomMargin: root.compactRow ? 8 : 12
                }
                height: root.compactRow ? 4 : 24

                Rectangle {
                    id: trackBg
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: root.compactRow ? 4 : 5
                    radius: height / 2
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.20)

                    Rectangle {
                        width: parent.width * root.progress
                        height: parent.height
                        radius: parent.radius
                        color: root.fg
                    }
                }
                Text {
                    visible: !root.compactRow
                    anchors { left: parent.left; bottom: parent.bottom }
                    text: root.formatSeconds(root.media?.positionSeconds)
                    color: root.subtleFg
                    font.pixelSize: 10
                }
                Text {
                    visible: !root.compactRow
                    anchors { right: parent.right; bottom: parent.bottom }
                    text: root.formatSeconds(root.media?.lengthSeconds)
                    color: root.subtleFg
                    font.pixelSize: 10
                }
            }

            // Playback controls (always shown, muted when disabled/idle).
            Row {
                id: controlsRow
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                }
                spacing: root.compactSquare ? 8 : (root.compactRow ? 12 : 16)

                Repeater {
                    model: [
                        { action: "media.previous", label: "⏮", enabled: root.ready && Boolean(root.media?.canPrevious), primary: false },
                        { action: "media.toggle-play-pause", label: root.playing ? "⏸" : "▶", enabled: root.ready && Boolean(root.media?.canTogglePlayPause), primary: true },
                        { action: "media.next", label: "⏭", enabled: root.ready && Boolean(root.media?.canNext), primary: false }
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
                        color: modelData.primary
                            ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.24)
                            : root.pillBg
                        opacity: modelData.enabled ? (btnArea.pressed ? 0.65 : 1.0) : 0.42

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.fg
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

        // Inline feedback banner when a reverse action fails.
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
