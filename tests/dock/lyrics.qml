import QtQuick
import QtTest
import "."
TestCase {
    name: "DesktopLyrics"
    MprisPlayer { id: player }
    MprisPlayer { id: otherPlayer; dbusName: "org.mpris.MediaPlayer2.z" }
    function init() {
        player.canControl = true
        otherPlayer.canControl = true
    }
    function cleanup() {
        MediaService._playerRefs = []
        MediaService._updateActivePlayer()
    }
    function test_controllability_data() {
        return [
            { tag: "playing-controllable", a: 1, b: 1, ca: false, cb: true, expected: 1 },
            { tag: "paused-controllable", a: 2, b: 2, ca: false, cb: true, expected: 1 },
            { tag: "stopped-controllable", a: 0, b: 0, ca: false, cb: true, expected: 1 },
            { tag: "playing-before-controllable-paused", a: 1, b: 2, ca: false, cb: true, expected: 0 },
            { tag: "paused-before-controllable-stopped", a: 2, b: 0, ca: false, cb: true, expected: 0 },
            { tag: "both-controllable-stable-name", a: 1, b: 1, ca: true, cb: true, expected: 0 },
            { tag: "both-readonly-stable-name", a: 1, b: 1, ca: false, cb: false, expected: 0 },
            { tag: "controllable-name-first", a: 1, b: 1, ca: true, cb: false, expected: 0 }
        ]
    }
    function test_controllability(data) {
        player.dbusName = "org.mpris.MediaPlayer2.a"
        player.playbackState = data.a
        otherPlayer.playbackState = data.b
        player.isPlaying = data.a === 1
        otherPlayer.isPlaying = data.b === 1
        player.canControl = data.ca
        otherPlayer.canControl = data.cb
        for (const refs of [[otherPlayer, player], [player, otherPlayer]]) {
            MediaService._playerRefs = refs
            MediaService._updateActivePlayer()
            compare(MediaService.activePlayer, data.expected === 0 ? player : otherPlayer)
            compare(MediaService.hasPlayingPlayer, data.a === 1 || data.b === 1)
        }
        MediaService._playerRefs = [player]
        MediaService._updateActivePlayer()
        compare(MediaService.activePlayer, player)
    }
    function test_selectionOrder() {
        player.dbusName = "org.mpris.MediaPlayer2.a"
        player.isPlaying = false
        otherPlayer.isPlaying = true
        player.playbackState = 2
        otherPlayer.playbackState = 1
        MediaService._playerRefs = [otherPlayer, player]
        MediaService._updateActivePlayer()
        compare(MediaService.activePlayer, otherPlayer)
        otherPlayer.isPlaying = false
        otherPlayer.playbackState = 2
        MediaService._updateActivePlayer()
        compare(MediaService.activePlayer, player)
        player.playbackState = 0
        MediaService._updateActivePlayer()
        compare(MediaService.activePlayer, otherPlayer)
        otherPlayer.playbackState = 0
        MediaService._updateActivePlayer()
        compare(MediaService.activePlayer, player)
        MediaService._playerRefs = []
        MediaService._updateActivePlayer()
    }
    SignalSpy { id: positions; target: player; signalName: "positionChanged" }
    function test_perPlayerDesktopSwitch() {
        MediaService.activePlayer = player
        player.position = 0
        player.metadata = ({"xesam:asText":"[00:00]first", "kos:desktopLyricsEnabled":false})
        player.isPlaying = true
        compare(MediaService.desktopLyricsAllowed, false)
        compare(MediaService.currentLyric, "first")
        positions.clear()
        wait(550)
        compare(positions.count, 0)
        player.metadata = ({"xesam:asText":"[00:00]first", "kos:desktopLyricsEnabled":true})
        compare(MediaService.desktopLyricsAllowed, true)
        tryVerify(() => positions.count > 0, 1000)
        player.metadata = ({"kos:desktopLyricsEnabled": {value:false}})
        compare(MediaService.desktopLyricsAllowed, false)
        player.isPlaying = false
        player.metadata = ({})
        compare(MediaService.desktopLyricsAllowed, true)
        MediaService.activePlayer = null
    }
    function test_playback() {
        MediaService.activePlayer = player
        player.metadata = ({"xesam:asText":"[00:01]first\n[00:03]\n[00:05]last"})
        compare(MediaService.currentLyric, "")
        compare(MediaService.nextLyric, "first")
        player.position = 1.5
        compare(MediaService.currentLyric, "first")
        player.isPlaying = true
        positions.clear()
        tryVerify(function() { return positions.count > 0 }, 1000)
        player.isPlaying = false
        positions.clear()
        wait(250)
        compare(positions.count, 0)
        player.position = 3
        compare(MediaService.currentLyric, "")
        compare(MediaService.nextLyric, "last")
        player.position = 8
        compare(MediaService.currentLyric, "last")
        player.position = 2
        compare(MediaService.currentLyric, "first")
        player.metadata = ({"xesam:asText":"[00:00]fallback", "kos:currentLyric":"", "kos:nextLyric":"live next"})
        compare(MediaService.currentLyric, "")
        compare(MediaService.nextLyric, "live next")
        player.metadata = ({"xesam:asText":"plain lyrics"})
        compare(MediaService.currentLyric, "plain lyrics")
        compare(MediaService.nextLyric, "")
        MediaService.activePlayer = null
        compare(MediaService.currentLyric, "")
    }
}
