import QtQuick
import QtMultimedia
import Quickshell.Io

// One bundled tone, with no external paths, network requests or silent pre-roll.
// QtMultimedia is the normal path; `pw-play` keeps the sound alive when the
// multimedia backend is missing or fails to decode (it used to go silent).
QtObject {
    id: root
    property bool busy: false
    readonly property string soundPath:
        String(Qt.resolvedUrl("sounds/notification.wav")).replace("file://", "")

    property MediaPlayer player: MediaPlayer {
        source: Qt.resolvedUrl("sounds/notification.wav")
        audioOutput: AudioOutput { volume: 0.5 }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia)
                root.cancel()
        }
        onErrorOccurred: (error, errorString) => {
            console.warn("[NotificationSoundService] QtMultimedia unavailable, falling back to pw-play: " + errorString)
            root.playFallback()
        }
    }
    property Process fallback: Process {
        command: ["pw-play", root.soundPath]
        onExited: root.cancel()
    }
    property Timer deadline: Timer {
        interval: 3000
        onTriggered: root.cancel()
    }
    function play() {
        if (busy) return false
        busy = true
        deadline.restart()
        player.position = 0
        player.play()
        return true
    }
    function playFallback() {
        if (!busy) return
        player.stop()
        if (!fallback.running)
            fallback.running = true
    }
    function cancel() {
        if (!busy)
            return
        busy = false
        deadline.stop()
        player.stop()
        if (fallback.running)
            fallback.running = false
    }
}
