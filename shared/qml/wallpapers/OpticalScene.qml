import QtQuick

// Every scene owns its optics; the host owns playback and visibility policy.
Item {
    id: root
    property var host: null
    property url shader
    property real variant: 0
    property int resolutionLimit: 1280
    signal frameReady()

    Loader {
        anchors.fill: parent
        active: !root.host || !root.host.foreground
        sourceComponent: ShaderEffect {
            property vector2d viewport: Qt.vector2d(width, height)
            property real time: root.host ? root.host.phase : 0
            property real variant: root.variant
            property vector4d pointer: root.host ? root.host.pointer : Qt.vector4d(0.5, 0.5, 0, 0)
            fragmentShader: root.shader
            blending: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: {
                const edge = root.host && root.host.economical ? 800 : root.resolutionLimit
                const scale = Math.min(1, edge / Math.max(1, width, height))
                return Qt.size(Math.max(1, Math.ceil(width * scale)),
                    Math.max(1, Math.ceil(height * scale)))
            }
            Component.onCompleted: Qt.callLater(root.frameReady)
        }
    }
}
