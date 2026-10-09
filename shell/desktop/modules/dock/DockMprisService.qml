pragma Singleton
import QtQuick
import qs.desktop.modules.deskcenter
import "TimedLyrics.mjs" as TimedLyrics
import Quickshell.Services.Mpris

// ────────────────────────────────────────────────────────────────
// DockMprisService — Wraps MPRIS2 players.
//
// Uses a hidden Repeater to capture MprisPlayer references since
// Quickshell's UntypedObjectModel doesn't support .get(index).
// The Repeater delegate stores each player in a JS array.
// ────────────────────────────────────────────────────────────────

QtObject {
    id: svc

    // ── Active player ──
    property MprisPlayer activePlayer: null
    property bool hasPlayer: activePlayer !== null
    // Playing controls player priority; visibility uses hasPlayer so paused
    // and buffering sessions remain available for resume.
    property bool hasPlayingPlayer: false
    property bool _rebuildingPlayers: false
    property int _startupRefreshCount: 0
    // Some MPRIS implementations mutate metadata on the same player object
    // without emitting a trackArtUrl notify signal. Consumers bind this
    // revision to refresh cover art and palettes after a track change.
    property int metadataRevision: 0
    readonly property string playbackStatus: {
        const revision = metadataRevision
        return metadataString("kos:playbackStatus")
    }
    readonly property bool loading: {
        const revision = metadataRevision
        return metadataString("kos:playbackState") === "Loading"
    }
    property string _metadataSignature: ""
    readonly property string _lyricText: {
        const revision = metadataRevision
        return metadataString("xesam:asText")
    }
    // Presence matters: an empty KOS line intentionally clears an interlude.
    readonly property bool _hasLiveLyrics: {
        const revision = metadataRevision
        return activePlayer?.metadata?.["kos:currentLyric"] !== undefined
            && activePlayer?.metadata?.["kos:currentLyric"] !== null
    }
    readonly property var _lyricLines: TimedLyrics.parse(_lyricText)
    readonly property int _lyricIndex: TimedLyrics.indexAt(_lyricLines, activePlayer?.position ?? 0)
    // Any lyric source counts: KOS live lines, LRC-timed or untimed plain
    // text. Only a track with none of these hides the widget lyrics switch.
    readonly property bool lyricsAvailable: _hasLiveLyrics || _lyricText.length > 0
    readonly property bool desktopLyricsAllowed: {
        const revision = metadataRevision
        return metadataString("kos:desktopLyricsEnabled") !== "false"
    }
    readonly property string currentLyric: {
        const revision = metadataRevision
        if (_hasLiveLyrics) return metadataString("kos:currentLyric")
        if (_lyricLines.length) return _lyricIndex < 0 ? "" : _lyricLines[_lyricIndex].text
        return _lyricText
    }
    readonly property string nextLyric: {
        const revision = metadataRevision
        if (_hasLiveLyrics) return metadataString("kos:nextLyric")
        return _lyricLines[_lyricIndex + 1]?.text ?? ""
    }
    // MPRIS position is lazy (DockMusicPopup pokes it on the same terms):
    // poll the player only while timed lyrics are enabled on the desktop,
    // at line-switch granularity, never while the shell is idle.
    property Timer lyricPositionTimer: Timer {
        interval: 500
        repeat: true
        running: DeskCenterConfigService.desktopLyricsActive && svc.desktopLyricsAllowed
            && svc.activePlayer !== null && svc.activePlayer.isPlaying
            && svc.activePlayer.positionSupported
            && !svc._hasLiveLyrics && svc._lyricLines.length > 0
        onTriggered: svc.activePlayer.positionChanged()
    }

    function metadataString(key) {
        const metadata = activePlayer?.metadata
        let value = metadata ? metadata[key] : null
        for (let depth = 0; depth < 4 && value !== null
                && typeof value === "object" && value.value !== undefined; depth++)
            value = value.value
        return value === null || value === undefined ? "" : String(value)
    }

    // ── Player tracking via Repeater ──
    property var _playerRefs: []

    // Hidden Repeater — one delegate per MPRIS player, captures the
    // actual MprisPlayer QObject via modelData into _playerRefs.
    property Repeater _playerRepeater: Repeater {
        // Rebuilding is used after a QML reload: MPRIS can be ready before
        // its model emits another change, leaving a fresh shell with no
        // delegates unless we explicitly recapture its current contents.
        model: svc._rebuildingPlayers ? [] : Mpris.players
        delegate: Item {
            id: delegate
            readonly property MprisPlayer player: modelData
            Component.onCompleted: {
                const refs = svc._playerRefs
                refs.push(player)
                svc._playerRefs = refs  // trigger change notification
                svc._updateActivePlayer()
            }
            Component.onDestruction: {
                const refs = svc._playerRefs.filter(p => p !== player)
                svc._playerRefs = refs
                svc._updateActivePlayer()
            }
            // Playback can begin in a player that is not currently selected
            // as active. Listen to every MPRIS player so the Dock information
            // slot immediately enters or leaves its carousel in that case.
            Connections {
                target: delegate.player
                ignoreUnknownSignals: true
                function onPlaybackStateChanged() { svc._updateActivePlayer() }
                function onMetadataChanged() {
                    svc._updateActivePlayer()
                    svc.refreshMetadata()
                }
            }
        }
    }

    function refreshPlayers() {
        _playerRefs = []
        activePlayer = null
        hasPlayingPlayer = false
        _rebuildingPlayers = true
        playerRebuildTimer.restart()
    }

    function refreshMetadata() {
        const player = activePlayer
        const signature = [player?.trackArtUrl ?? "", player?.trackTitle ?? "",
            player?.trackArtist ?? "", metadataString("kos:currentLyric"),
            metadataString("kos:nextLyric"), metadataString("xesam:asText"),
            metadataString("kos:playbackStatus"),
            metadataString("kos:playbackState"), metadataString("kos:desktopLyricsEnabled"), player?.isPlaying ?? false].join("\u001f")
        if (signature !== _metadataSignature) {
            _metadataSignature = signature
            metadataRevision++
        }
    }

    property Timer playerRebuildTimer: Timer {
        interval: 120
        repeat: false
        onTriggered: svc._rebuildingPlayers = false
    }
    property Timer startupRefreshTimer: Timer {
        interval: 600
        repeat: true
        running: svc._startupRefreshCount < 4
        onTriggered: {
            svc._startupRefreshCount++
            if (!svc.activePlayer)
                svc.refreshPlayers()
        }
    }
    property Timer metadataRefreshTimer: Timer {
        interval: 500
        repeat: true
        running: svc.activePlayer !== null
        onTriggered: svc.refreshMetadata()
    }
    Component.onCompleted: startupRefreshTimer.start()

    // ── Select the best active player ──
    // Priority: playing > paused > any > none
    function _updateActivePlayer() {
        // Stable service-name ordering gives the lock screen the same tie-break.
        const refs = svc._playerRefs.slice().sort((a, b) =>
            String(a?.dbusName ?? "").localeCompare(String(b?.dbusName ?? "")))
        if (!refs || refs.length === 0) {
            activePlayer = null
            hasPlayingPlayer = false
            return
        }

        // 1. Prefer a playing player
        for (let i = 0; i < refs.length; i++) {
            const p = refs[i]
            if (p && p.isPlaying) {
                activePlayer = p
                hasPlayingPlayer = true
                refreshMetadata()
                return
            }
        }

        hasPlayingPlayer = false

        // 2. Fall back to a paused player
        for (let i = 0; i < refs.length; i++) {
            const p = refs[i]
            if (p && p.playbackState === MprisPlaybackState.Paused) {
                activePlayer = p
                refreshMetadata()
                return
            }
        }

        // 3. Any player
        activePlayer = refs[0] || null
        refreshMetadata()
    }

    // ── Playback helpers ──
    function togglePlayPause() {
        if (!activePlayer) return
        if (activePlayer.isPlaying || loading) {
            activePlayer.pause()
        } else {
            activePlayer.play()
        }
    }

    function next() {
        activePlayer?.next()
    }

    function previous() {
        activePlayer?.previous()
    }

}
