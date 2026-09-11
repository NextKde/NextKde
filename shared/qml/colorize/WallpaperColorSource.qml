pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper colour source for Kos.Ui. It resolves the active KDE Plasma
// wallpaper and exposes its two sampled colours plus the derived Material
// scheme, without depending on any shell-side module.
//
// Layering contract: this file lives in `shared/`, so it must never import
// `qs.desktop.modules.*`. Everything the shell used to push in or pull out is
// expressed here as an injectable input or an outbound signal:
//   - in : `darkMode`         — the shell feeds its resolved light/dark state
//   - in : `wallpaperSeedSink`— optional callback invoked with the seed colour
//   - out: `paletteChanged`   — emitted when primary/secondary become ready
// Consumers wire these up in their own adapter (see shell's PaletteBridge).
//
// Plasma updates its wallpaper config through atomic file replacement on some
// versions. That can evade an inotify FileView watch, so we read this small
// config on a low-frequency timer and only sample when the URL truly changes.
QtObject {
    id: svc

    readonly property string configPath: Quickshell.env("HOME")
        + "/.config/plasma-org.kde.plasma.desktop-appletsrc"
    // Keep this aligned with shell.qml's primaryScreen selection.
    readonly property int preferredScreen: Quickshell.screens.length > 1 ? 1 : 0
    property url wallpaperUrl: ""
    property string configuredWallpaperUrl: ""
    // Keep a QML-owned reference while resolving a wallpaper package.
    property var _resolveProcess: null
    readonly property color primary: palette.primary
    readonly property color secondary: palette.secondary
    readonly property bool ready: palette.ready

    // Injected by the shell adapter: which scheme branch the wallpaper-derived
    // colours should be generated for. Defaults to the system palette so the
    // service stays usable stand-alone.
    property bool darkMode: false

    // Emitted once the sampled pair is available. The shell adapter listens and
    // persists the seed colour; `shared/` never touches shell config itself.
    signal paletteChanged(color primary, color secondary)

    // Emitted when no wallpaper is resolvable, so the adapter can reset any
    // persisted seed colour back to "transparent".
    signal paletteCleared()

    function _applyWallpaperUrl(nextUrl) {
        if (wallpaperUrl.toString() === nextUrl)
            return
        console.log("[WallpaperColorSource] sampling screen=" + preferredScreen
            + " " + nextUrl)
        wallpaperUrl = nextUrl
    }

    function _resolveWallpaperUrl(nextUrl) {
        if (!nextUrl.endsWith("/")) {
            _applyWallpaperUrl(nextUrl)
            return
        }

        if (_resolveProcess) {
            _resolveProcess.running = false
            _resolveProcess.destroy()
            _resolveProcess = null
        }

        const screen = Quickshell.screens[Math.min(preferredScreen,
            Math.max(0, Quickshell.screens.length - 1))]
        const targetAspect = screen && screen.height > 0
            ? screen.width / screen.height : 16 / 9
        const packagePath = decodeURIComponent(nextUrl
            .replace(/^file:\/\//, "").replace(/\/+$/, ""))
        const imageSet = svc.darkMode ? "images_dark" : "images"
        const requestedUrl = nextUrl
        const proc = _processFactory.createObject(svc, {
            command: ["sh", "-c",
                "base=\"$1/contents/$2\"; [ -d \"$base\" ] || base=\"$1/contents/images\"; "
                    + "find \"$base\" -maxdepth 1 -type f -print 2>/dev/null | "
                    + "awk -v target=\"$3\" 'match($0, /([0-9]+)x([0-9]+)/, size) { ratio=size[1]/size[2]; diff=ratio-target; if (diff<0) diff=-diff; area=size[1]*size[2]; if (!best || diff<bestDiff || (diff==bestDiff && area>bestArea)) { best=$0; bestDiff=diff; bestArea=area } } END { print best }'",
                "wallpaper-package-resolve", packagePath, imageSet,
                String(targetAspect)],
        })
        _resolveProcess = proc
        proc.exited.connect(function(code) {
            if (svc._resolveProcess === proc)
                svc._resolveProcess = null
            const resolvedPath = (proc.stdout?.text ?? "").trim()
            if (code === 0 && resolvedPath
                    && svc.configuredWallpaperUrl === requestedUrl)
                svc._applyWallpaperUrl("file://" + resolvedPath)
            else if (svc.configuredWallpaperUrl === requestedUrl)
                console.warn("[WallpaperColorSource] package image resolve failed "
                    + requestedUrl)
            proc.destroy()
        })
        proc.running = true
    }

    function _readWallpaperText(content) {
        const containmentScreens = ({})
        const wallpapers = ({})
        let containmentId = ""
        let wallpaperId = ""
        const lines = content.split("\n")

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            const containmentMatch = line.match(/^\[Containments\]\[(\d+)\]$/)
            const wallpaperMatch = line.match(/^\[Containments\]\[(\d+)\]\[Wallpaper\]\[org\.kde\.image\]\[General\]$/)

            if (containmentMatch) {
                containmentId = containmentMatch[1]
                wallpaperId = ""
                continue
            }
            if (wallpaperMatch) {
                wallpaperId = wallpaperMatch[1]
                containmentId = ""
                continue
            }
            if (containmentId && line.startsWith("lastScreen=")) {
                containmentScreens[containmentId] = Number(line.slice("lastScreen=".length))
            } else if (wallpaperId && line.startsWith("Image=")) {
                wallpapers[wallpaperId] = line.slice("Image=".length).trim()
            }
        }

        let nextUrl = ""
        for (const id in containmentScreens) {
            if (containmentScreens[id] === preferredScreen && wallpapers[id]) {
                nextUrl = wallpapers[id]
                break
            }
        }
        if (!nextUrl) {
            for (const id in wallpapers) {
                nextUrl = wallpapers[id]
                break
            }
        }

        if (nextUrl) {
            if (configuredWallpaperUrl === nextUrl)
                return
            configuredWallpaperUrl = nextUrl
            _resolveWallpaperUrl(nextUrl)
        } else {
            configuredWallpaperUrl = ""
            wallpaperUrl = ""
            paletteCleared()
            console.warn("[WallpaperColorSource] no image wallpaper found")
        }
    }

    function refresh() {
        _configFile.reload()
    }

    property FileView _configFile: FileView {
        path: svc.configPath
        preload: true
        // Keep the existing periodic reload: atomic replacement must not
        // depend on a watch of the old inode. Failed reads retain the palette.
        watchChanges: false
        onLoaded: svc._readWallpaperText(text())
        onLoadFailed: error => console.warn("[WallpaperColorSource] config read failed error=" + error)
    }

    property Component _processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }

    property Timer _refreshTimer: Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: svc.refresh()
    }

    property ArtworkColorSource _palette: ArtworkColorSource {
        id: palette
        source: svc.wallpaperUrl
        // LiquidGlassSurface owns the slow visual transition for wallpaper
        // adaptation. Keep the palette value immediate and unambiguous.
        transitionDuration: 0
    }

    property Connections _paletteLog: Connections {
        target: palette
        function onReadyChanged() {
            if (palette.ready) {
                console.log("[WallpaperColorSource] primary=" + palette.primary
                    + " secondary=" + palette.secondary)
                // The sampled primary is the seed for the Material scheme. It is
                // computed in-process, so no external tool has to re-read the image.
                ColorScheme.setSeed(palette.primary)
                svc.paletteChanged(palette.primary, palette.secondary)
            }
        }
    }

    // Re-resolve the wallpaper package when the requested scheme branch flips,
    // because packages ship separate `images` / `images_dark` sets.
    onDarkModeChanged: {
        if (svc.configuredWallpaperUrl.endsWith("/"))
            svc._resolveWallpaperUrl(svc.configuredWallpaperUrl)
    }

}
