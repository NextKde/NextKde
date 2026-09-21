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
// versions. That can evade an inotify FileView watch, so we read the small
// configs on a low-frequency timer and only sample when the URL truly changes.
// Which file that is depends on the session's shell package, so `plasmashellrc`
// is read on the same timer; see `configPath` below.
QtObject {
    id: svc

    // Which applets config holds the wallpaper is NOT a constant. Plasma names
    // it after the shell package the session runs — `plasmashellrc`
    // `[Shell] ShellPackage` -> `plasma-<package>-appletsrc` — and KOS ships its
    // own shell package for the lock screen, which `kosctl` points that key at.
    // The desktop wallpapers then live in `plasma-org.kos.desktop-appletsrc`
    // while this service kept reading `plasma-org.kde.plasma.desktop-appletsrc`:
    // a file Plasma had stopped writing. The resolved URL therefore never
    // changed, nothing was ever re-sampled, and every colour source stayed
    // frozen no matter which wallpaper the user picked. Resolve the name instead
    // of hardcoding it, and keep the KDE desktop shell's file as the fallback
    // for sessions that never picked a package.
    readonly property string configDirectory: Quickshell.env("HOME") + "/.config"
    readonly property string shellConfigPath: configDirectory + "/plasmashellrc"
    readonly property string defaultConfigPath: configDirectory
        + "/plasma-org.kde.plasma.desktop-appletsrc"
    // Most authoritative first. The index walks forward when a candidate turns
    // out not to exist; see `_fallBackToNextConfig`.
    property var configCandidates: [defaultConfigPath]
    property int configCandidateIndex: 0
    property string configPath: defaultConfigPath
    // Keep this aligned with shell.qml's primaryScreen selection.
    readonly property int preferredScreen: Quickshell.screens.length > 1 ? 1 : 0
    property url wallpaperUrl: ""
    property string configuredWallpaperUrl: ""
    // Last file text each FileView delivered. The timer reloads whether or not
    // Plasma touched the file, so the full line-by-line parse only runs when
    // the bytes actually changed. `null` is the never-loaded sentinel: it can
    // never equal real content, so the first load — even of an empty file —
    // always processes, which keeps the paletteCleared path reachable.
    property var _lastShellConfigText: null
    property var _lastConfigText: null
    // Poll decimation state. While a wallpaper is resolved the config almost
    // never changes, so only every (_pollSkip + 1)-th tick reloads the files;
    // the countdown lives here and `_pollSkip` is the re-arm value.
    property int _pollPhase: 0
    readonly property int _pollSkip: 4
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
        // A fresh URL pulls the poll back to the full rate so the wallpaper
        // that comes after this one is noticed within one tick, not five.
        _pollPhase = 0
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

    // Parse the two Plasma keys this service needs. Pure, so the fixture can
    // feed it synthetic configs (see tests/traditional-color/shell.qml and the
    // dock's test_wallpaper_color_source.mjs).
    //
    // Two things keep the blocks apart, and both are load-bearing.
    //
    // 1. The block header regexp accepts ANY plugin name. The version that
    //    matched only `org.kde.image` fell through to the generic branch on
    //    every other block, so that block's keys were attributed to the last
    //    image block it had seen. Real configs keep one
    //    `[Wallpaper][<plugin>][General]` block per plugin ever configured —
    //    image first, then the retired ones side by side:
    //
    //      [Containments][55][Wallpaper][org.kde.image][General]
    //      Image=/home/…/spider.jpeg
    //      [Containments][55][Wallpaper][org.kde.potd][General]
    //      [Containments][55][Wallpaper][org.kde.slideshow][General]
    //      Image=file:///home/…/a2.jpg
    //
    //    That stray slideshow `Image` overwrote the real wallpaper, so the
    //    resolved URL never changed, the palette was never re-sampled, and all
    //    three colour sources looked frozen after a wallpaper change.
    //
    // 2. Every section header resets the cursor, so a block this parser does
    //    not model at all cannot leak its keys into the previous one.
    //
    // Keys are kept per plugin so the active one can be chosen afterwards
    // (`_pickWallpaperUrl`) instead of hardcoding `org.kde.image` — a user who
    // switches to the slideshow plugin deserves the slideshow's image, not the
    // stale image plugin's.
    function _parseWallpaperConfig(content) {
        const screens = ({})
        const plugins = ({})
        const wallpapers = ({})
        let containmentId = ""
        let wallpaperId = ""
        let pluginId = ""
        const lines = content.split("\n")

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            if (line.startsWith("[")) {
                containmentId = ""
                wallpaperId = ""
                pluginId = ""
                const containmentMatch = line.match(/^\[Containments\]\[(\d+)\]$/)
                if (containmentMatch) {
                    containmentId = containmentMatch[1]
                } else {
                    const wallpaperMatch = line.match(
                        /^\[Containments\]\[(\d+)\]\[Wallpaper\]\[([^\]]+)\]\[General\]$/)
                    if (wallpaperMatch) {
                        wallpaperId = wallpaperMatch[1]
                        pluginId = wallpaperMatch[2]
                    }
                }
                continue
            }
            if (containmentId && line.startsWith("lastScreen=")) {
                screens[containmentId] = Number(line.slice("lastScreen=".length))
            } else if (containmentId && line.startsWith("wallpaperplugin=")) {
                plugins[containmentId] = line.slice("wallpaperplugin=".length).trim()
            } else if (wallpaperId && line.startsWith("Image=")) {
                if (!wallpapers[wallpaperId])
                    wallpapers[wallpaperId] = ({})
                wallpapers[wallpaperId][pluginId] = line.slice("Image=".length).trim()
            }
        }

        return { screens: screens, plugins: plugins, wallpapers: wallpapers }
    }

    // The image a containment is actually showing, or "" when none carried one.
    // `wallpaperplugin=` decides which of the containment's blocks is current.
    // Containments on the preferred screen win; the rest are the fallback, which
    // keeps the previous behaviour for a config whose screen ids do not line up.
    function _pickWallpaperUrl(parsed, screen) {
        const ids = []
        for (const id in parsed.wallpapers) {
            if (parsed.screens[id] === screen)
                ids.push(id)
        }
        for (const id in parsed.wallpapers) {
            if (parsed.screens[id] !== screen)
                ids.push(id)
        }
        for (const id of ids) {
            const byPlugin = parsed.wallpapers[id]
            const active = parsed.plugins[id]
            // A video-wallpaper plugin keeps `LastVideo=`, not `Image=`, so it
            // simply has no entry here and the search moves on.
            if (active && byPlugin[active])
                return byPlugin[active]
            if (byPlugin["org.kde.image"])
                return byPlugin["org.kde.image"]
            for (const plugin in byPlugin)
                return byPlugin[plugin]
        }
        return ""
    }

    function _readWallpaperText(content) {
        const nextUrl = _pickWallpaperUrl(_parseWallpaperConfig(content),
            preferredScreen)

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

    // Re-arm the decimation countdown after a reload produced new bytes: the
    // change just consumed is the reason to keep polling slowly, and a config
    // that now resolves to no wallpaper goes back to every-tick polling until
    // one is found.
    function _contentChanged() {
        _pollPhase = configuredWallpaperUrl ? _pollSkip : 0
    }

    function refresh() {
        // The tick itself stays short because a resolved wallpaper must never
        // wait for it; the file reloads are what get decimated. See
        // _pollPhase/_contentChanged.
        if (_pollPhase > 0) {
            _pollPhase--
            return
        }
        _pollPhase = configuredWallpaperUrl ? _pollSkip : 0
        // plasmashellrc decides which applets config is live, so it is re-read on
        // the same tick: Plasma picks the shell package up at startup, and the
        // wallpaper file moves with it.
        _shellConfigFile.reload()
        _configFile.reload()
    }

    // `plasmashellrc` names the shell package, and Plasma derives its applets
    // config filename from it. Only the `[Shell]` group counts — the same key
    // elsewhere in the file is not the one Plasma reads.
    function _parseShellPackage(content) {
        let inShell = false
        const lines = content.split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim()
            if (line.startsWith("[")) {
                inShell = line === "[Shell]"
                continue
            }
            if (inShell && line.startsWith("ShellPackage="))
                return line.slice("ShellPackage=".length).trim()
        }
        return ""
    }

    // Adopt the candidate list for `name`. An empty name — no plasmashellrc, or a
    // session that never picked a package — leaves the KDE file in charge.
    function _applyShellPackage(name) {
        const candidates = []
        if (name)
            candidates.push(svc.configDirectory + "/plasma-" + name + "-appletsrc")
        candidates.push(svc.defaultConfigPath)
        if (candidates.join("\n") === svc.configCandidates.join("\n"))
            return
        svc.configCandidates = candidates
        svc.configCandidateIndex = 0
        svc.configPath = candidates[0]
    }

    // The named candidate can be missing: a session Plasma has not written yet,
    // or a package that is installed but not in use. Walk forward rather than
    // giving up on the wallpaper entirely.
    function _fallBackToNextConfig(error) {
        if (svc.configCandidateIndex + 1 < svc.configCandidates.length) {
            svc.configCandidateIndex++
            svc.configPath = svc.configCandidates[svc.configCandidateIndex]
            return
        }
        console.warn("[WallpaperColorSource] config read failed error=" + error)
    }

    property FileView _shellConfigFile: FileView {
        path: svc.shellConfigPath
        preload: true
        // Same reasoning as the applets config below: the periodic reload is what
        // keeps this honest, because the installed shell runs with
        // QS_DISABLE_FILE_WATCHER=1 and no watch would ever fire.
        watchChanges: false
        onLoaded: {
            // The timer reloads on a fixed cadence whether or not the file
            // moved, so the parse only runs when the bytes actually differ.
            const content = text()
            if (content === svc._lastShellConfigText)
                return
            svc._lastShellConfigText = content
            svc._contentChanged()
            svc._applyShellPackage(svc._parseShellPackage(content))
        }
        // A session without a plasmashellrc is normal; the KDE candidate stands.
        onLoadFailed: function() {}
    }

    property FileView _configFile: FileView {
        path: svc.configPath
        preload: true
        // Keep the existing periodic reload: atomic replacement must not
        // depend on a watch of the old inode. Failed reads retain the palette.
        watchChanges: false
        onLoaded: {
            // Same early-out as _shellConfigFile: unchanged bytes mean the
            // whole _parseWallpaperConfig pass would produce the same URL.
            const content = text()
            if (content === svc._lastConfigText)
                return
            svc._lastConfigText = content
            svc._contentChanged()
            svc._readWallpaperText(content)
        }
        onLoadFailed: error => svc._fallBackToNextConfig(error)
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
