import QtQuick
import QtQuick.Controls
import "org.nextkde.example.music" as Music

ApplicationWindow {
    id: root
    width: 560
    height: 480
    visible: true
    title: "音乐控制 · QML 组件原型 (R1 + R11)"

    readonly property int cellSize: 168
    readonly property int cellGap: 12
    readonly property var sizeList: [[1, 1], [2, 1]]
    readonly property var widgetSize: sizeList[sizeMode.currentIndex]
    readonly property bool live: dataMode.currentIndex === 1
    property bool playing: true
    property int trackIndex: 0
    property int positionSeconds: 42
    property var lastActionResult: null
    property string lastLog: "点击曲目头或播放控制键测试反向动作通道 (R11)"

    readonly property var tracks: [
        {
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            lengthSeconds: 243,
            lyric: "Waiting in a car",
            artworkColors: { ready: true, primary: "#6c3cc8", secondary: "#1f78c1" }
        },
        {
            title: "Clair de Lune",
            artist: "Claude Debussy",
            album: "Suite bergamasque",
            lengthSeconds: 312,
            lyric: "",
            artworkColors: { ready: true, primary: "#1b7f79", secondary: "#3b5998" }
        },
        {
            title: "Nightcall",
            artist: "Kavinsky",
            album: "OutRun",
            lengthSeconds: 258,
            lyric: "I'm giving you a night call",
            artworkColors: { ready: true, primary: "#c73866", secondary: "#f08a24" }
        }
    ]

    readonly property var appearance: ({
        isDark: root.palette.window.hsvValue < 0.5,
        foreground: root.palette.windowText,
        transparent: transparentMode.checked
    })

    readonly property var musicData: {
        if (!live) return snapshot.getSnapshot(widgetSize)
        const track = tracks[trackIndex]
        return {
            status: "ready",
            hasPlayer: true,
            playing: root.playing,
            loading: false,
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkUrl: "",
            artworkColors: track.artworkColors,
            positionSeconds: root.positionSeconds,
            lengthSeconds: track.lengthSeconds,
            canPrevious: true,
            canTogglePlayPause: true,
            canNext: true,
            canRaise: true,
            lyric: track.lyric
        }
    }

    Music.Snapshot { id: snapshot }

    Timer {
        interval: 1000
        repeat: true
        running: root.live && root.playing
        onTriggered: {
            const len = root.tracks[root.trackIndex].lengthSeconds
            root.positionSeconds = (root.positionSeconds + 1) % len
        }
    }

    function simulateAction(action, payload) {
        if (!root.live) {
            root.lastLog = "[样例模式] 已拦截动作: " + action
            return
        }
        if (action === "media.raise-player") {
            root.lastActionResult = { ok: true, code: "ok", message: "" }
            root.lastLog = "[R11 执行] " + action + " -> 聚焦当前播放器窗口"
            return
        }
        if (action === "media.toggle-play-pause") {
            root.playing = !root.playing
            root.lastActionResult = { ok: true, code: "ok", message: "" }
            root.lastLog = "[R11 执行] " + action + " -> ok"
            return
        }
        if (action === "media.next") {
            root.trackIndex = (root.trackIndex + 1) % root.tracks.length
            root.positionSeconds = 0
            root.lastActionResult = { ok: true, code: "ok", message: "" }
            root.lastLog = "[R11 执行] " + action + " -> ok"
            return
        }
        if (action === "media.previous") {
            root.trackIndex = (root.trackIndex - 1 + root.tracks.length) % root.tracks.length
            root.positionSeconds = 0
            root.lastActionResult = { ok: true, code: "ok", message: "" }
            root.lastLog = "[R11 执行] " + action + " -> ok"
            return
        }
        root.lastActionResult = { ok: false, code: "unknown-action", message: "Unknown action" }
        root.lastLog = "[R11 未知动作] " + action
    }

    header: ToolBar {
        Row {
            anchors.centerIn: parent
            spacing: 10
            ComboBox { id: sizeMode; model: ["1×1", "2×1"]; currentIndex: 1 }
            ComboBox { id: dataMode; model: ["样例", "实时"]; currentIndex: 1 }
            CheckBox { id: transparentMode; text: "透明模式" }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: transparentMode.checked
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#2d6a4f" }
            GradientStop { position: 0.5; color: "#f4a300" }
            GradientStop { position: 1; color: "#7209b7" }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.widgetSize[0] * root.cellSize + (root.widgetSize[0] - 1) * root.cellGap
        height: root.widgetSize[1] * root.cellSize + (root.widgetSize[1] - 1) * root.cellGap
        radius: 22
        clip: true
        color: "transparent"
        border.width: transparentMode.checked ? 0 : 1
        border.color: root.palette.mid

        Rectangle {
            id: cardBg
            anchors.fill: parent
            radius: 22
            visible: !transparentMode.checked && !!musicWidget.backgroundSpec
            readonly property var spec: musicWidget.backgroundSpec
            readonly property color resolvedStart: spec?.startColor ?? "transparent"
            readonly property color resolvedEnd: spec?.endColor ?? "transparent"
            readonly property bool hasMid: spec?.midColor !== undefined
                && spec?.midColor !== null && String(spec.midColor).length > 0
            readonly property color resolvedMid: hasMid
                ? spec.midColor
                : Qt.rgba(
                    (resolvedStart.r + resolvedEnd.r) * 0.5,
                    (resolvedStart.g + resolvedEnd.g) * 0.5,
                    (resolvedStart.b + resolvedEnd.b) * 0.5,
                    (resolvedStart.a + resolvedEnd.a) * 0.5
                )
            gradient: Gradient {
                orientation: cardBg.spec?.orientation === "horizontal"
                    ? Gradient.Horizontal : Gradient.Vertical
                GradientStop {
                    position: 0
                    color: cardBg.resolvedStart
                    Behavior on color { ColorAnimation { duration: 480; easing.type: Easing.InOutCubic } }
                }
                GradientStop {
                    position: Math.max(0.01, Math.min(0.99,
                        cardBg.spec?.midPosition !== undefined ? Number(cardBg.spec.midPosition) : 0.5))
                    color: cardBg.resolvedMid
                    Behavior on color { ColorAnimation { duration: 480; easing.type: Easing.InOutCubic } }
                }
                GradientStop {
                    position: 1
                    color: cardBg.resolvedEnd
                    Behavior on color { ColorAnimation { duration: 480; easing.type: Easing.InOutCubic } }
                }
            }
        }

        Music.Widget {
            id: musicWidget
            anchors.fill: parent
            snapshot: root.musicData
            widgetSize: root.widgetSize
            appearance: root.appearance
            lastActionResult: root.lastActionResult
            onActionRequested: (action, payload) => root.simulateAction(action, payload)
        }
    }

    footer: ToolBar {
        Label {
            anchors.centerIn: parent
            text: root.lastLog
            font.pixelSize: 11
        }
    }
}
