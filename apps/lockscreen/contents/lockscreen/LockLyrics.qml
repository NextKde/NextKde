// SPDX-FileCopyrightText: 2026 KOS
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.plasma.workspace.dbus as DBus

// MPRIS only: no network lyric/artwork scraping and no Quickshell imports.
// The Loader in LockScreen keeps failure of this optional module away from PAM.
Item {
    id: root
    objectName: "lockLyrics"
    property real unit: 1
    property string fontFamily: "Inter"
    property Item glassTexture: null
    property Item glassFrame: null
    function unwrap(value) {
        let result = value
        for (let depth = 0; depth < 5 && result !== null && typeof result === "object"; depth++) {
            if (result.value !== undefined) result = result.value
            else if (Number(result.length) === 1 && result[0] !== undefined) result = result[0]
            else break
        }
        return result
    }
    property var serviceNames: []
    property var playerSources: []
    property int playerRevision: 0
    property bool discoveryPending: false
    function discoverPlayers() {
        if (discoveryPending) return
        discoveryPending = true
        DBus.SessionBus.asyncCall({service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "ListNames", arguments: []}, function(reply) {
                const names = Array.from(reply.value || [])
                    .filter(name => String(name).indexOf("org.mpris.MediaPlayer2.") === 0).sort()
                if (names.join("\n") !== root.serviceNames.join("\n")) root.serviceNames = names
                root.discoveryPending = false
            }, function() { root.discoveryPending = false })
    }
    Component.onCompleted: discoverPlayers()
    Timer {
        interval: 2000; repeat: true
        running: root.Window.window ? root.Window.window.visible : false
        onTriggered: root.discoverPlayers()
    }
    readonly property var activeSource: {
        const revision = playerRevision
        const sources = playerSources.filter(source => source && source.available)
            .sort((a, b) => {
                const controllability = (a.canControl !== false ? 0 : 1) - (b.canControl !== false ? 0 : 1)
                return controllability || a.serviceName.localeCompare(b.serviceName)
            })
        return sources.find(source => source.playbackStatus === "Playing")
            || sources.find(source => source.playbackStatus === "Paused") || sources[0] || null
    }
    function metadataText(key) { return activeSource ? activeSource.metadataText(key) : "" }
    readonly property bool lyricsAllowed: metadataText("kos:lockscreenLyricsEnabled") !== "false"
    readonly property string currentLine: lyricsAllowed ? metadataText("kos:currentLyric") || metadataText("xesam:asText") : ""
    readonly property string nextLine: lyricsAllowed ? metadataText("kos:nextLyric") : ""
    readonly property string trackTitle: metadataText("xesam:title")
    readonly property string trackArtist: metadataText("xesam:artist")
    readonly property bool playing: !!activeSource && activeSource.playing
    function canInvoke(method) {
        if (!activeSource || !activeSource.available || activeSource.canControl === false) return false
        if (method === "Previous") return activeSource.canPrevious !== false
        if (method === "Next") return activeSource.canNext !== false
        if (method === "PlayPause") return playing ? activeSource.canPause !== false : activeSource.canPlay !== false
        return false
    }
    function control(method) {
        if (!canInvoke(method)) return
        DBus.SessionBus.asyncCall({ service: activeSource.serviceName, path: "/org/mpris/MediaPlayer2",
            iface: "org.mpris.MediaPlayer2.Player", member: method, arguments: [] }, function() {}, function() {})
    }
    implicitWidth: 372 * unit
    implicitHeight: visible ? mediaCard.implicitHeight : 0
    visible: !!activeSource && activeSource.available && trackTitle.length > 0
    component LyricSource: Item {
        id: source
        required property string serviceName
        property int revision: 0
        readonly property bool available: watcher.registered
        function propertyValue(name) {
            const current = revision
            return available && properties.properties ? root.unwrap(properties.properties[name]) : null
        }
        readonly property string playbackStatus: String(propertyValue("PlaybackStatus") || "")
        readonly property bool playing: playbackStatus === "Playing"
        readonly property bool canControl: propertyValue("CanControl") !== false
        readonly property bool canPlay: propertyValue("CanPlay") === true
        readonly property bool canPause: propertyValue("CanPause") === true
        readonly property bool canPrevious: propertyValue("CanGoPrevious") === true
        readonly property bool canNext: propertyValue("CanGoNext") === true
        readonly property real positionSeconds: Math.max(0, Number(propertyValue("Position")) || 0) / 1000000
        onRevisionChanged: root.playerRevision++
        Component.onCompleted: root.playerSources = root.playerSources.concat([source])
        Component.onDestruction: root.playerSources = root.playerSources.filter(item => item !== source)
        function metadataText(key) {
            const current = revision
            if (!available || !properties.properties) return ""
            const metadata = root.unwrap(properties.properties["Metadata"])
            const value = metadata ? root.unwrap(metadata[key]) : null
            return value === null || value === undefined ? "" : String(value)
        }
        DBus.DBusServiceWatcher {
            id: watcher
            busType: DBus.BusType.Session
            watchedService: source.serviceName
            onRegisteredChanged: source.revision++
        }
        DBus.Properties {
            id: properties
            busType: DBus.BusType.Session
            service: watcher.registered ? watcher.watchedService : ""
            path: "/org/mpris/MediaPlayer2"
            iface: "org.mpris.MediaPlayer2.Player"
            onPropertiesChanged: function(interfaceName, changedProperties, invalidatedProperties) {
                for (const key of ["Metadata", "PlaybackStatus", "CanControl", "CanPlay", "CanPause", "CanGoPrevious", "CanGoNext", "Position"])
                    if ((changedProperties && changedProperties[key] !== undefined)
                        || (invalidatedProperties && invalidatedProperties.indexOf(key) >= 0)) update(key)
                refreshTimer.restart()
            }
            onRefreshed: source.revision++
        }
        Timer { id: refreshTimer; interval: 80; onTriggered: source.revision++ }
        Timer {
            interval: 1000; repeat: true
            running: root.visible && source.available && root.activeSource === source
                && (root.Window.window ? root.Window.window.visible : false)
            onTriggered: properties.update("Position")
        }
    }
    Repeater {
        model: root.serviceNames
        delegate: LyricSource { required property string modelData; serviceName: modelData }
    }
    LockMediaCard {
        id: mediaCard
        anchors.fill: parent
        unit: root.unit
        fontFamily: root.fontFamily
        glassTexture: root.glassTexture; glassFrame: root.glassFrame
        title: root.trackTitle; artist: root.trackArtist
        // Greeter disallows network requests. Keep artwork local/data only,
        // rather than showing endless failed remote downloads on the lock.
        artwork: {
            const url = root.metadataText("mpris:artUrl")
            return /^(file:|data:image\/)/.test(url) ? url : ""
        }
        playing: root.playing
        canPrevious: root.canInvoke("Previous")
        canPlayPause: root.canInvoke("PlayPause")
        canNext: root.canInvoke("Next")
        position: root.activeSource ? Number(root.activeSource.positionSeconds) || 0 : 0
        duration: Math.max(0, Number(root.metadataText("mpris:length")) || 0) / 1000000
        currentLine: root.currentLine; nextLine: root.nextLine
        onControlRequested: method => root.control(method)
    }
}
