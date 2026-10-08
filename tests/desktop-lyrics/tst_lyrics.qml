import QtQuick
import QtTest
import "."
TestCase {
    name: "DesktopLyrics"
    MprisPlayer { id: player }
    SignalSpy { id: positions; target: player; signalName: "positionChanged" }
    function test_playback() {
        DockMprisService.activePlayer = player
        player.metadata = ({"xesam:asText":"[00:01]first\n[00:03]\n[00:05]last"})
        compare(DockMprisService.currentLyric, "")
        compare(DockMprisService.nextLyric, "first")
        player.position = 1.5
        compare(DockMprisService.currentLyric, "first")
        player.isPlaying = true
        positions.clear()
        tryVerify(function() { return positions.count > 0 }, 1000)
        player.isPlaying = false
        positions.clear()
        wait(250)
        compare(positions.count, 0)
        player.position = 3
        compare(DockMprisService.currentLyric, "")
        compare(DockMprisService.nextLyric, "last")
        player.position = 8
        compare(DockMprisService.currentLyric, "last")
        player.position = 2
        compare(DockMprisService.currentLyric, "first")
        player.metadata = ({"xesam:asText":"[00:00]fallback", "kos:currentLyric":"", "kos:nextLyric":"live next"})
        compare(DockMprisService.currentLyric, "")
        compare(DockMprisService.nextLyric, "live next")
        player.metadata = ({"xesam:asText":"plain lyrics"})
        compare(DockMprisService.currentLyric, "plain lyrics")
        compare(DockMprisService.nextLyric, "")
        DockMprisService.activePlayer = null
        compare(DockMprisService.currentLyric, "")
    }
}
