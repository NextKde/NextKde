import QtQuick
import QtTest
import "../../contents/lockscreen" as Lock

TestCase {
    name: "LockMedia"
    Lock.LockLyrics { id: lyrics }
    QtObject {
        id: first
        property string serviceName: "org.mpris.MediaPlayer2.a.instance1"
        property bool available: true
        property string playbackStatus: "Paused"
        readonly property bool playing: playbackStatus === "Playing"
        function metadataText(key) { return key === "xesam:title" ? "first" : "" }
    }
    QtObject {
        id: second
        property string serviceName: "org.mpris.MediaPlayer2.z.instance2"
        property bool available: true
        property string playbackStatus: "Playing"
        readonly property bool playing: playbackStatus === "Playing"
        function metadataText(key) { return key === "xesam:title" ? "second" : "" }
    }
    function test_playerSelection() {
        tryCompare(lyrics, "discoveryPending", false)
        lyrics.playerSources = [second, first]
        compare(lyrics.activeSource, second)
        compare(lyrics.trackTitle, "second")
        second.playbackStatus = "Paused"
        compare(lyrics.activeSource, first)
        first.playbackStatus = "Stopped"
        compare(lyrics.activeSource, second)
        second.playbackStatus = "Stopped"
        compare(lyrics.activeSource, first)
        first.available = false
        compare(lyrics.activeSource, second)
        second.available = false
        compare(lyrics.activeSource, null)
        compare(lyrics.trackTitle, "")
    }
}
