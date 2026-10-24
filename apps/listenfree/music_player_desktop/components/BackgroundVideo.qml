import QtQuick
import QtMultimedia

Item {
    required property var host

    id: videoBackgroundItem
    property var movie: typeof backendArtworkVideoFactory !== "undefined"
        ? backendArtworkVideoFactory.create(videoBackgroundItem) : null
    Binding { target: videoBackgroundItem.movie; property: "videoSink"; value: backgroundVideo.videoSink; when: !!videoBackgroundItem.movie }
    Binding { target: videoBackgroundItem.movie; property: "playing"; value: host.exposed; when: !!videoBackgroundItem.movie }
    Binding { target: videoBackgroundItem.movie; property: "source"; value: host.resolvedMedia.source || ""; when: !!videoBackgroundItem.movie }
    VideoOutput {
        id: backgroundVideo
        objectName: "backgroundVideoOutput"
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: host.blurRadius <= 0
    }
    ArtworkBackground {
        anchors.fill: parent
        visible: host.blurRadius > 0
        mode: "BlurredArtwork"
        neutralImage: true
        blurRadius: host.blurRadius
        motionTexture: videoBackgroundItem.movie && videoBackgroundItem.movie.ready ? backgroundVideo : null
    }
    Connections {
        target: videoBackgroundItem.movie
        function onReadyChanged() { if (videoBackgroundItem.movie.ready) host.sampleContrastSoon() }
    }

}
