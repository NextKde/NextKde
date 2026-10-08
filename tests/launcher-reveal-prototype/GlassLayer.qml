import QtQuick

// Stage 2: a flat SDF plate, with no capture, blur, refraction or highlights.
Item {
    id: root
    property bool opened: false
    property bool animationsEnabled: true
    property real previewProgress: -1
    property bool ready: false
    readonly property alias effect: shape
    width: 1100
    height: 650

    function setReveal(progress, animate) {
        reveal.stop();
        reveal.from = shape.revealProgress;
        reveal.to = progress;
        reveal.duration = animate ? 320 : 1;
        reveal.start();
    }
    onOpenedChanged: if (ready && previewProgress < 0) setReveal(opened ? 1 : 0, animationsEnabled)
    onPreviewProgressChanged: if (ready && previewProgress >= 0) setReveal(previewProgress, false)
    Component.onCompleted: {
        ready = true;
        if (opened) setReveal(1, animationsEnabled);
    }

    ShaderEffect {
        id: shape
        anchors.fill: parent
        property vector2d panelSize: Qt.vector2d(width, height)
        property real revealProgress: 0
        property color plateColor: Qt.rgba(0.14, 0.20, 0.29, 0.97)
        fragmentShader: Qt.resolvedUrl("glass-reveal.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) console.error("SDF_SHADER_ERROR: " + log)
    }

    property UniformAnimator reveal: UniformAnimator {
        target: shape
        uniform: "revealProgress"
        easing.type: Easing.OutCubic
    }
}
