pragma Singleton
import QtQuick
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
    // A paused player remains controllable through MPRIS, but it should not
    // occupy the Dock's live information slot or take part in its carousel.
    property bool hasPlayingPlayer: false
    property bool _rebuildingPlayers: false
    property int _startupRefreshCount: 0
    // Some MPRIS implementations mutate metadata on the same player object
    // without emitting a trackArtUrl notify signal. Consumers bind this
    // revision to refresh cover art and palettes after a track change.
    property int metadataRevision: 0
    property string _metadataSignature: ""

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
                function onPlaybackStateChanged() { svc._updateActivePlayer() }
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
            player?.trackArtist ?? "", player?.isPlaying ?? false].join("\u001f")
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
        const refs = svc._playerRefs
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
        if (activePlayer.isPlaying) {
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
