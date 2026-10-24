import QtQuick
import QtMultimedia
VideoOutput {
    property var host: null
    objectName: "immersiveVideo"
    fillMode: VideoOutput.PreserveAspectCrop
    visible: host && host.videoVisible
    onHostChanged: if (host && host.service) host.service.attachVideoSink(videoSink)
    Component.onDestruction: if (host && host.service) host.service.attachVideoSink(null)
}
