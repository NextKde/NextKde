import QtQuick

// Detailed scenery is baked once; only the small light buffer changes per tick.
// Coordinates in the plate, mask and shader share the same 16:9 artboard.
Item {
    id: root
    property var host: null
    property url plate
    property url motionMask
    property int scene: 0
    signal frameReady()

    Loader {
        anchors.fill: parent
        active: !root.host || !root.host.foreground
        sourceComponent: Item {
            Image {
                id: background
                anchors.fill: parent
                source: root.plate
                sourceSize: Qt.size(2560, 1440)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                onStatusChanged: if (status === Image.Ready) Qt.callLater(root.frameReady)
            }
            Image {
                id: maskImage
                source: root.motionMask
                sourceSize: Qt.size(1280, 720)
                visible: false
                smooth: true
            }
            ShaderEffect {
                anchors.fill: parent
                visible: background.status === Image.Ready && maskImage.status === Image.Ready
                property var motionMask: maskImage
                property vector2d viewport: Qt.vector2d(width, height)
                property real time: root.host ? root.host.phase : 0
                property real scene: root.scene
                fragmentShader: "shaders/stilllight.frag.qsb"
                blending: true
                layer.enabled: true
                layer.smooth: true
                layer.textureSize: {
                    const edge = root.host && root.host.economical ? 640 : 960
                    const scale = Math.min(1, edge / Math.max(1, width, height))
                    return Qt.size(Math.max(1, Math.ceil(width * scale)),
                        Math.max(1, Math.ceil(height * scale)))
                }
            }
        }
    }
}
