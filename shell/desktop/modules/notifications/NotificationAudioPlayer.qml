import QtQuick
import QtMultimedia

// One bundled tone, with no external paths, network requests or silent pre-roll.
QtObject {
    id: root
    property bool busy: false

    property MediaPlayer player: MediaPlayer {
        source: Qt.resolvedUrl("sounds/notification.wav")
        audioOutput: AudioOutput { volume: 0.5 }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) root.cancel()
        }
        onErrorOccurred: (error, errorString) => {
            console.warn("[NotificationSoundService] playback unavailable: " + errorString)
            Qt.callLater(root.cancel)
        }
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
    function cancel() {
        busy = false
        deadline.stop()
        player.stop()
    }
}
