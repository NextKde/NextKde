import QtQuick
import QtMultimedia

Item {
    required property var host

    id: motion
    property alias output: video
    property alias firstFrame: firstFrameSample
    property bool frameCaptured: false
    property var nativeMovie: typeof backendArtworkVideoFactory !== "undefined" && backendArtworkVideoFactory
        ? backendArtworkVideoFactory.create(motion) : null
    property bool ready: nativeMovie ? nativeMovie.ready : previewMovie.item
        && previewMovie.item.hasVideo && video.videoSink.videoSize.width > 0
        && previewMovie.item.mediaStatus !== MediaPlayer.InvalidMedia
    Binding { target: motion.nativeMovie; property: "videoSink"; value: video.videoSink; when: !!motion.nativeMovie }
    Binding { target: motion.nativeMovie; property: "playing"; value: host.motionPlaying; when: !!motion.nativeMovie }
    Binding { target: motion.nativeMovie; property: "source"; value: host.motionSource; when: !!motion.nativeMovie }
    Loader {
        id: previewMovie
        active: !motion.nativeMovie
        sourceComponent: MediaPlayer {
            objectName: "dynamicArtworkMediaPlayer"
            source: host.motionSource
            autoPlay: host.motionPlaying
            loops: MediaPlayer.Infinite
            videoOutput: video
        }
    }
    Connections {
        target: host
        function onMotionSourceChanged() { motion.frameCaptured = false }
        function onMotionPlayingChanged() {
            if (previewMovie.item) {
                if (host.motionPlaying) previewMovie.item.play(); else previewMovie.item.pause()
            }
        }
    }
    VideoOutput { id: video; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop; visible: false }
    // Capture once per media source, independently of background mode or
    // window size. Cover playback and loop boundaries never refresh it.
    ShaderEffectSource {
        id: firstFrameSample
        objectName: "dynamicArtworkFirstFrame"
        // Keep a tiny covered item in the scene so capture also happens
        // while Solid/Flow is selected and no background consumes it.
        width: 1; height: 1
        textureSize: Qt.size(512, 512)
        sourceItem: video
        live: false
    }
    Connections {
        target: video.videoSink
        function onVideoFrameChanged() {
            if (!motion.frameCaptured && video.videoSink.videoSize.width > 0) {
                firstFrameSample.scheduleUpdate()
                motion.frameCaptured = true
            }
        }
    }

}
