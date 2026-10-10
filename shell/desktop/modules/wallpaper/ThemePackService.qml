pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Installed theme packs (marketplace). Each pack is a directory under the
// packs root holding manifest.json, its entry QML and assets — the format is
// documented in docs/ThemePackFormat.md. The shell only needs id -> accent /
// entry / preview lookups; scene loading goes through
// ThemeWallpaperScene.packResolver, which this service feeds.
QtObject {
    id: root
    readonly property string packsDir: {
        const override = Quickshell.env("KOS_WALLPAPER_PACKS")
        return override && override.trim() ? override.trim()
            : Quickshell.env("HOME") + "/.local/share/kos/wallpaper-themes"
    }
    property var packs: []
    signal scanFinished()

    function pack(id) {
        return packs.find(item => item.id === id) || null
    }
    function has(id) { return pack(id) !== null }
    // Missing accent falls back to the shell's default so the Plasma
    // placeholder path never receives an empty color.
    function accent(id) {
        const item = pack(id)
        return item && item.accent ? item.accent : "#729bda"
    }
    function entryUrl(id) {
        const item = pack(id)
        return item ? "file://" + item.dir + "/" + item.entry : ""
    }
    function previewUrl(id) {
        const item = pack(id)
        return item && item.preview ? "file://" + item.dir + "/" + item.preview : ""
    }
    function rescan() {
        listing.command = ["sh", "-c",
            // One pass frames every pack as \x1e<dir>\x1f<raw manifest>; the
            // manifest may be multi-line, so records cannot be line-based.
            'for d in "$1"/*/; do m="${d}manifest.json"; [ -f "$m" ] && printf "\\036%s\\037" "$d" && cat "$m"; done',
            "kos-theme-packs", packsDir]
        listing.running = true
    }
    function _applyListing(text) {
        const records = String(text || "").split("\x1e").filter(record => record)
        const next = []
        for (const record of records) {
            const cut = record.indexOf("\x1f")
            if (cut < 0) continue
            const dir = record.slice(0, cut).replace(/\/$/, "")
            let manifest = null
            try { manifest = JSON.parse(record.slice(cut + 1)) } catch (_) { continue }
            if (!manifest || typeof manifest !== "object" || Array.isArray(manifest))
                continue
            // The id doubles as a directory name component elsewhere; keep it
            // strict and keep entry/preview inside the pack directory.
            const id = String(manifest.id || dir.split("/").pop()).trim()
            if (!/^[A-Za-z0-9_-]+$/.test(id)) continue
            const entry = String(manifest.entry || "main.qml")
            let preview = String(manifest.preview || "")
            if (!entry || entry.includes("/") || entry.includes("..")) continue
            if (preview && (preview.includes("/") || preview.includes(".."))) preview = ""
            const accent = String(manifest.accent || "")
            next.push({
                id: id, dir: dir,
                name: String(manifest.name || id),
                detail: String(manifest.detail || ""),
                accent: /^#[0-9a-fA-F]{6}$/.test(accent) ? accent.toUpperCase() : "",
                version: Number(manifest.version) || 1,
                entry: entry, preview: preview
            })
        }
        next.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
        packs = next
        scanFinished()
    }
    property Process listing: Process {
        stdout: StdioCollector {
            onStreamFinished: root._applyListing(text)
        }
    }
    // A slow periodic rescan picks up packs installed after shell start
    // without a dedicated IPC round trip.
    property Timer refresh: Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.rescan()
    }
    Component.onCompleted: rescan()
}
