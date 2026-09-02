pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Quickshell resolves themed icons when the shell loads. KDE stores the
// selected theme in kdeglobals, so a theme change needs one soft shell reload
// to make iconPath() resolve against the new theme. This service watches only
// that one setting; it never reloads for unrelated kdeglobals edits.
QtObject {
    id: service

    readonly property string configPath: Quickshell.env("HOME")
        + "/.config/kdeglobals"
    property string activeTheme: ""
    property bool initialized: false
    // Changes whenever KDE applies a different icon theme. Consumers use this
    // to discard resolved icon paths without restarting all shell windows.
    property int revision: 0

    function themeFromConfig(text) {
        const lines = String(text || "").split("\n")
        let inIconsGroup = false
        for (let index = 0; index < lines.length; ++index) {
            const line = lines[index].trim()
            if (line.startsWith("[") && line.endsWith("]")) {
                inIconsGroup = line === "[Icons]"
                continue
            }
            if (inIconsGroup && line.startsWith("Theme="))
                return line.slice("Theme=".length).trim()
        }
        return ""
    }

    function applyConfig(text) {
        const nextTheme = themeFromConfig(text)
        // KConfig may notify while replacing kdeglobals. Do not treat a
        // short-lived incomplete read as a request to resolve an empty theme.
        if (!nextTheme)
            return
        if (!initialized) {
            activeTheme = nextTheme
            initialized = true
            return
        }
        if (nextTheme === activeTheme)
            return
        activeTheme = nextTheme
        refreshDelay.restart()
    }

    // Accessing the singleton from shell.qml instantiates the FileView. Keep
    // this function explicit so the startup dependency is obvious there.
    function initialize() {}

    property FileView _kdeGlobals: FileView {
        id: kdeGlobals
        path: service.configPath
        watchChanges: true
        preload: true
        // Delay the read until KConfig's atomic write has settled.
        onFileChanged: configSettleDelay.restart()
        onLoaded: service.applyConfig(text())
    }

    property Timer _configSettleDelay: Timer {
        id: configSettleDelay
        interval: 350
        repeat: false
        onTriggered: kdeGlobals.reload()
    }

    property Timer _refreshDelay: Timer {
        id: refreshDelay
        // Let KDE finish applying the theme before consumers re-resolve every
        // icon. A targeted revision avoids a shell-wide soft reload, which
        // can retain stale Dock delegates while their windows are remapped.
        interval: 650
        repeat: false
        onTriggered: {
            console.log("[IconTheme] changed to " + service.activeTheme
                + "; refreshing icon sources")
            service.revision++
        }
    }
}
