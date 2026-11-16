pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Optional theme extension. Artwork and application mappings belong to the
// installed icon theme; ordinary themes and user images keep their usual path.
QtObject {
    id: service

    property var icons: ({})
    property var desktopEntries: ({})
    property var colorSources: ({})
    property string themeDirectory: ""
    property int revision: 0
    property var candidates: []
    property int candidateIndex: 0
    property string indexPath: ""
    property string manifestPath: ""

    function relativePath(value) {
        return typeof value === "string" && value.length > 0
            && !value.startsWith("/") && !value.includes("\\")
            && !value.includes(":") && !value.includes("?") && !value.includes("#")
            && value.split("/").every(part => part !== ".." && part !== "." && part !== "")
    }

    function fileUrl(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/") }

    function clearArtwork() {
        icons = ({})
        desktopEntries = ({})
        colorSources = ({})
        revision++
    }

    function reload() {
        clearArtwork()
        candidates = []
        candidateIndex = 0
        themeDirectory = ""
        manifestPath = ""
        indexPath = ""
        const theme = IconThemeReloadService.activeTheme
        if (!relativePath(theme) || theme.includes("/")) return
        const home = Quickshell.env("HOME")
        const roots = [(Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/icons",
            home + "/.icons"]
        for (const directory of (Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":")) {
            if (directory.startsWith("/")) roots.push(directory.replace(/\/$/, "") + "/icons")
        }
        candidates = [...new Set(roots)].map(path => path + "/" + theme)
        candidateIndex = 0
        nextCandidate()
    }

    function nextCandidate() {
        if (candidateIndex >= candidates.length) return
        themeDirectory = candidates[candidateIndex++]
        indexPath = themeDirectory + "/index.theme"
    }

    function acceptIndex(text) {
        let inTheme = false
        const fields = ({})
        for (const raw of text.split("\n")) {
            const line = raw.trim()
            if (line.startsWith("[")) inTheme = line === "[Icon Theme]"
            else if (inTheme && !line.startsWith("#")) {
                const equals = line.indexOf("=")
                if (equals > 0) fields[line.slice(0, equals).trim()] = line.slice(equals + 1).trim()
            }
        }
        // The first installed theme wins, even when it has no extension.
        const manifest = fields["X-KOS-LayerManifest"]
        if (fields["X-KOS-LayeredIconsVersion"] !== "1" || !relativePath(manifest)) return
        manifestPath = themeDirectory + "/" + manifest
    }

    function acceptManifest(text) {
        try {
            const manifest = JSON.parse(text)
            if (!manifest || manifest.version !== 1 || !manifest.icons
                    || typeof manifest.icons !== "object" || Array.isArray(manifest.icons)) {
                clearArtwork()
                return
            }
            const accepted = ({})
            const sources = ({})
            for (const name of Object.keys(manifest.icons)) {
                const item = manifest.icons[name]
                if (!item || ![item.color, item.clear, item.base, item.foreground, item.highlights].every(relativePath)) continue
                const paths = ({})
                for (const role of ["color", "clear", "base", "foreground", "highlights"])
                    paths[role] = fileUrl(themeDirectory + "/" + item[role])
                accepted[name] = paths
                sources[paths.color] = paths
            }
            icons = accepted
            colorSources = sources
            const mappings = ({})
            for (const [desktopId, name] of Object.entries(manifest.desktopEntries || ({}))) {
                if (typeof name === "string" && Object.prototype.hasOwnProperty.call(accepted, name))
                    mappings[desktopId] = name
            }
            desktopEntries = mappings
            revision++
        } catch (error) {
            clearArtwork()
            console.warn("[LayeredIcons] invalid theme manifest: " + error)
        }
    }

    function iconRecord(name) {
        return Object.prototype.hasOwnProperty.call(icons, name) ? icons[name] : null
    }

    function artwork(source) {
        const currentRevision = revision
        let value = String(source || "")
        if (value.startsWith("image://icon/")) {
            value = value.slice("image://icon/".length)
            try { value = decodeURIComponent(value) } catch (error) { return null }
            if (!value.includes("/") && !value.includes(":")) return iconRecord(value)
        }
        if (value.startsWith("file://")) {
            try { value = decodeURIComponent(value.slice(7)) } catch (error) { return null }
        }
        if (!value.startsWith(themeDirectory + "/") || !themeDirectory) return null
        return colorSources[fileUrl(value)] || null
    }

    function defaultSource(iconName, desktopId) {
        const currentRevision = revision
        const mapped = desktopEntries[desktopId] || desktopEntries[String(desktopId).replace(/\.desktop$/i, "")]
        if (!mapped || !icons[mapped]) return ""
        // Keep color rendering on the normal provider, including inheritance
        // when an advertised standard icon is unavailable.
        return Quickshell.iconPath(mapped, true) || ""
    }

    property FileView indexFile: FileView {
        path: service.indexPath
        preload: true
        printErrors: false
        watchChanges: true
        onLoaded: service.acceptIndex(text())
        onLoadFailed: Qt.callLater(service.nextCandidate)
        onFileChanged: service.reload()
    }
    property FileView manifestFile: FileView {
        path: service.manifestPath
        preload: true
        printErrors: false
        watchChanges: true
        onLoaded: service.acceptManifest(text())
        onLoadFailed: service.clearArtwork()
        onFileChanged: service.manifestFile.reload()
    }
    property Connections themeConnection: Connections {
        target: IconThemeReloadService
        function onActiveThemeChanged() { service.reload() }
    }
    Component.onCompleted: reload()
}
