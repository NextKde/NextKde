import QtQuick

// The user-provided reference supplies the cinematic material. Animation is
// the previous orbital lighting law advects grain over this fixed material.
Item {
    id: root
    property real phase: 0
    property vector4d pointer: Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: Qt.vector4d(-10,-10,-100,0)
    readonly property bool failed: plate.status === Image.Error
    signal frameReady()
    Image {
        id: plate
        source: "assets/blackhole-cinematic-reference.png"
        sourceSize: Qt.size(Math.max(1, Math.min(2048, Math.ceil(root.width))),
            Math.max(1, Math.min(2048, Math.ceil(root.height))))
        visible: false
        smooth: true
        onStatusChanged: if (status === Image.Ready) Qt.callLater(root.frameReady)
    }
    Image {
        id: flowNoiseImage
        source: "vendor/black-hole/noise_texture.png"
        visible: false
        smooth: true
    }
    ShaderEffect {
        anchors.fill: parent
        property var source: plate
        property var flowNoise: flowNoiseImage
        property vector2d viewport: Qt.vector2d(width,height)
        property real time: root.phase
        property vector4d pointer: root.pointer
        property vector4d clickPulse: root.clickPulse
        fragmentShader: "shaders/cinematic_blackhole.frag.qsb"
    }
}
