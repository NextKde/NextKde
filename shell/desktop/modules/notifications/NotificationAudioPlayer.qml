import QtQuick
import QtMultimedia

// One persistent player owns the output through pre-roll and the actual sound.
// Silence wakes HDMI/DP receivers before a short notification reaches them.
QtObject {
    id: root

    property bool busy: false
    property bool warming: false
    property url pendingSource
    property var fallbackSources: []

    property MediaPlayer player: MediaPlayer {
        audioOutput: AudioOutput { volume: 1.0 }
        onMediaStatusChanged: {
            if (mediaStatus !== MediaPlayer.EndOfMedia || !root.busy) return
            if (root.warming) root.startSound()
            else {
                console.info("[NotificationSoundService] completed " + source
                    + " duration=" + duration + "ms position=" + position + "ms")
                root.cancel()
            }
        }
        onErrorOccurred: (error, errorString) => {
            if (!root.busy) return
            console.warn("[NotificationSoundService] " + source + ": " + errorString)
            // Defer changing source out of the backend's error callback.
            Qt.callLater(root.retry)
        }
    }

    property Timer deadline: Timer {
        interval: 10000
        onTriggered: {
            console.warn("[NotificationSoundService] playback timed out")
            root.cancel()
        }
    }

    function play(source, fallbacks) {
        if (busy) return false
        pendingSource = source
        fallbackSources = fallbacks.slice()
        busy = true
        warming = true
        deadline.restart()
        player.source = Qt.resolvedUrl("sounds/prewarm.wav")
        player.play()
        return true
    }

    function startSound() {
        if (!busy) return
        warming = false
        player.source = pendingSource
        player.play()
    }

    function retry() {
        if (!busy) return
        if (warming) {
            startSound()
        } else if (fallbackSources.length) {
            pendingSource = fallbackSources.shift()
            startSound()
        } else cancel()
    }

    function cancel() {
        busy = false
        warming = false
        deadline.stop()
        player.stop()
        fallbackSources = []
    }
}
