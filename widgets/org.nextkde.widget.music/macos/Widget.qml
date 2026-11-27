import QtQuick
import ".." as Shared

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null
    property var lastActionResult: null
    signal actionRequested(string action, var payload)

    readonly property var media: (host && !host.isPreview && host.media) ? host.media : snapshot
    readonly property string status: String(media?.status ?? "idle")
    readonly property bool ready: status === "ready" && Boolean(media?.hasPlayer)

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

    readonly property color fg: appearance?.foreground ?? "#ffffff"

    Shared.MusicContent {
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        mediaData: root.media
        host: root.host
        wavyProgress: false
        lastActionResult: root.lastActionResult
        onActionRequested: (action, payload) => root.actionRequested(action, payload)
        primaryInk: root.fg
        subtleInk: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.72)
        pillBackground: root.appearance?.transparent
            ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16)
            : (root.appearance?.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
        playButtonBackground: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.24)
        playButtonInk: root.fg
        progressTrackColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.20)
        progressActiveColor: root.fg
    }
}
