import QtQuick

Item {
    id: root

    required property var data
    required property var widgetSize
    required property var appearance
    property var lastActionResult: null
    signal actionRequested(string action, var payload)

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 1
    readonly property int spanRows: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[1]) : 1
    readonly property bool compactSquare: spanCols <= 1 && spanRows <= 1
    readonly property bool compactRow: spanRows <= 1
    readonly property bool largeCard: spanCols >= 2 && spanRows >= 2
    readonly property string status: String(data?.status ?? "idle")
    readonly property bool ready: status === "ready" && Boolean(data?.hasPlayer)
    readonly property real progress: (ready && Number(data?.lengthSeconds ?? 0) > 0)
        ? Math.max(0, Math.min(1, Number(data?.positionSeconds ?? 0) / Number(data.lengthSeconds)))
        : 0

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
        const colors = data?.artworkColors
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
            ? ({ orientation: "horizontal", startColor: "#423052", midColor: "#2f2340", midPosition: 0.52, endColor: "#21192d" })
            : ({ orientation: "horizontal", startColor: "#efe4ff", midColor: "#e6e8ff", midPosition: 0.52, endColor: "#dcebff" })
    }

    property string _feedbackText: ""
    onLastActionResultChanged: {
        if (!lastActionResult || lastActionResult.ok) {
            _feedbackText = ""
            return
        }
        if (lastActionResult.code === "unavailable")
            _feedbackText = "当前播放器不可用"
        else
            _feedbackText = String(lastActionResult.message || "操作失败")
        feedbackClearTimer.restart()
    }

    function formatSeconds(total) {
        const value = Math.max(0, Math.floor(Number(total) || 0))
        const mins = Math.floor(value / 60)
        const secs = value % 60
        return mins + ":" + (secs < 10 ? "0" + secs : String(secs))
    }

    // Item.data is Qt Quick's default child list; keep SDK input named `data`
    // and attach visual items and helper objects through `children`/`resources`.
    resources: [
        Timer {
            id: feedbackClearTimer
            interval: 2600
            onTriggered: root._feedbackText = ""
        }
    ]

    children: Item {
        anchors.fill: parent
        anchors.margins: root.compactSquare ? 12 : (root.compactRow ? 14 : 18)

        readonly property color fg: root.appearance.foreground
        readonly property color subtleFg: Qt.rgba(fg.r, fg.g, fg.b, 0.72)
        readonly property color pillBg: root.appearance.transparent
            ? Qt.rgba(fg.r, fg.g, fg.b, 0.16)
            : (root.appearance.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
        readonly property int textStyle: root.appearance.transparent ? Text.Outline : Text.Normal
        readonly property color textStyleColor: root.appearance.isDark
            ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.65)

        // Idle state (no active player).
        Column {
            visible: !root.ready
            anchors.centerIn: parent
            width: parent.width
            spacing: 4

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "未在播放"
                color: parent.parent.fg
                font { pixelSize: 14; weight: Font.DemiBold }
                style: parent.parent.textStyle
                styleColor: parent.parent.textStyleColor
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "打开任意支持 MPRIS 的播放器后自动显示"
                color: parent.parent.subtleFg
                font.pixelSize: 11
                style: parent.parent.textStyle
                styleColor: parent.parent.textStyleColor
                wrapMode: Text.WordWrap
            }
        }

        // Ready state: header (artwork + metadata; tap to raise player) + progress + controls.
        Item {
            id: readyView
            visible: root.ready
            anchors.fill: parent

            Item {
                id: headerArea
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: root.compactSquare ? 44 : (root.compactRow ? 50 : 80)

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.actionRequested("media.raise-player", {})
                }

                Rectangle {
                    id: coverBox
                    width: headerArea.height
                    height: headerArea.height
                    radius: root.largeCard ? 14 : 10
                    clip: true
                    color: readyView.parent.pillBg

                    Image {
                        anchors.fill: parent
                        source: String(root.data?.artworkUrl ?? "")
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !root.data?.artworkUrl
                        text: "♫"
                        color: readyView.parent.fg
                        font { pixelSize: Math.max(16, Math.floor(coverBox.height * 0.45)); weight: Font.DemiBold }
                    }
                }

                Column {
                    anchors {
                        left: coverBox.right
                        leftMargin: root.compactSquare ? 8 : (root.compactRow ? 10 : 14)
                        right: parent.right
                        verticalCenter: coverBox.verticalCenter
                    }
                    spacing: 2

                    Text {
                        width: parent.width
                        text: String(root.data?.title || "未知曲目")
                        color: readyView.parent.fg
                        font { pixelSize: root.compactSquare ? 13 : (root.compactRow ? 15 : 19); weight: Font.DemiBold }
                        elide: Text.ElideRight
                        style: readyView.parent.textStyle
                        styleColor: readyView.parent.textStyleColor
                    }
                    Text {
                        width: parent.width
                        text: String(root.data?.artist || root.data?.album || "")
                        visible: text.length > 0
                        color: readyView.parent.subtleFg
                        font.pixelSize: root.compactSquare ? 11 : (root.compactRow ? 12 : 14)
                        elide: Text.ElideRight
                        style: readyView.parent.textStyle
                        styleColor: readyView.parent.textStyleColor
                    }
                    Text {
                        width: parent.width
                        visible: root.largeCard && String(root.data?.lyric ?? "").length > 0
                        text: String(root.data?.lyric ?? "")
                        color: readyView.parent.subtleFg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        style: readyView.parent.textStyle
                        styleColor: readyView.parent.textStyleColor
                    }
                }
            }

            // Progress bar (thin track on 1x1/2x1, full bar with time labels on 2x2).
            Item {
                id: progressSection
                visible: Number(root.data?.lengthSeconds ?? 0) > 0
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: controlsRow.top
                    bottomMargin: root.compactRow ? 10 : 14
                }
                height: root.compactRow ? 4 : 24

                Rectangle {
                    id: trackBg
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: root.compactRow ? 4 : 5
                    radius: height / 2
                    color: Qt.rgba(readyView.parent.fg.r, readyView.parent.fg.g, readyView.parent.fg.b, 0.20)

                    Rectangle {
                        width: parent.width * root.progress
                        height: parent.height
                        radius: parent.radius
                        color: readyView.parent.fg
                    }
                }
                Text {
                    visible: !root.compactRow
                    anchors { left: parent.left; top: trackBg.bottom; topMargin: 4 }
                    text: root.formatSeconds(root.data?.positionSeconds)
                    color: readyView.parent.subtleFg
                    font.pixelSize: 11
                }
                Text {
                    visible: !root.compactRow
                    anchors { right: parent.right; top: trackBg.bottom; topMargin: 4 }
                    text: root.formatSeconds(root.data?.lengthSeconds)
                    color: readyView.parent.subtleFg
                    font.pixelSize: 11
                }
            }

            // Playback controls (R11 reverse action requests).
            Row {
                id: controlsRow
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                }
                spacing: root.compactSquare ? 8 : (root.compactRow ? 14 : 18)

                Repeater {
                    model: [
                        { action: "media.previous", label: "⏮", enabled: Boolean(root.data?.canPrevious), primary: false },
                        { action: "media.toggle-play-pause", label: root.data?.playing ? "⏸" : "▶", enabled: Boolean(root.data?.canTogglePlayPause), primary: true },
                        { action: "media.next", label: "⏭", enabled: Boolean(root.data?.canNext), primary: false }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: root.compactSquare
                            ? (modelData.primary ? 34 : 30)
                            : (root.compactRow ? (modelData.primary ? 38 : 34) : (modelData.primary ? 48 : 40))
                        height: root.compactSquare
                            ? 30
                            : (root.compactRow ? 34 : (modelData.primary ? 44 : 38))
                        radius: height / 2
                        color: modelData.primary
                            ? Qt.rgba(readyView.parent.fg.r, readyView.parent.fg.g, readyView.parent.fg.b, 0.24)
                            : readyView.parent.pillBg
                        opacity: modelData.enabled ? (btnArea.pressed ? 0.65 : 1.0) : 0.42

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: readyView.parent.fg
                            font {
                                pixelSize: root.compactSquare
                                    ? (modelData.primary ? 13 : 11)
                                    : (root.compactRow ? (modelData.primary ? 14 : 12) : (modelData.primary ? 18 : 15))
                                weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            id: btnArea
                            anchors.fill: parent
                            enabled: modelData.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.actionRequested(modelData.action, {})
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
