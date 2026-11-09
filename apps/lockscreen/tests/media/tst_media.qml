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
        property bool canControl: true
        property string playbackStatus: "Paused"
        readonly property bool playing: playbackStatus === "Playing"
        function metadataText(key) { return key === "xesam:title" ? "first" : "" }
    }
    QtObject {
        id: second
        property string serviceName: "org.mpris.MediaPlayer2.z.instance2"
        property bool available: true
        property bool canControl: true
        property string playbackStatus: "Playing"
        readonly property bool playing: playbackStatus === "Playing"
        function metadataText(key) { return key === "xesam:title" ? "second" : "" }
    }
    function init() {
        tryCompare(lyrics, "discoveryPending", false)
        first.available = true
        second.available = true
        first.canControl = true
        second.canControl = true
        first.playbackStatus = "Paused"
        second.playbackStatus = "Playing"
        lyrics.playerSources = []
    }
    function test_controllability_data() {
        return [
            { tag: "playing-controllable", a: "Playing", b: "Playing", ca: false, cb: true, expected: 1 },
            { tag: "paused-controllable", a: "Paused", b: "Paused", ca: false, cb: true, expected: 1 },
            { tag: "stopped-controllable", a: "Stopped", b: "Stopped", ca: false, cb: true, expected: 1 },
            { tag: "playing-before-controllable-paused", a: "Playing", b: "Paused", ca: false, cb: true, expected: 0 },
            { tag: "paused-before-controllable-stopped", a: "Paused", b: "Stopped", ca: false, cb: true, expected: 0 },
            { tag: "both-controllable-stable-name", a: "Playing", b: "Playing", ca: true, cb: true, expected: 0 },
            { tag: "both-readonly-stable-name", a: "Playing", b: "Playing", ca: false, cb: false, expected: 0 },
            { tag: "controllable-name-first", a: "Playing", b: "Playing", ca: true, cb: false, expected: 0 }
        ]
    }
    function test_controllability(data) {
        first.playbackStatus = data.a
        second.playbackStatus = data.b
        first.canControl = data.ca
        second.canControl = data.cb
        for (const sources of [[second, first], [first, second]]) {
            lyrics.playerSources = sources
            compare(lyrics.activeSource, data.expected === 0 ? first : second)
        }
        lyrics.playerSources = [first]
        compare(lyrics.activeSource, first)
    }
    function test_controllabilityChanges() {
        first.playbackStatus = "Playing"
        lyrics.playerSources = [second, first]
        compare(lyrics.activeSource, first)
        first.canControl = false
        compare(lyrics.activeSource, second)
        second.canControl = false
        compare(lyrics.activeSource, first)
    }
    function test_playerSelection() {
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
