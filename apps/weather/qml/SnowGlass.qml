import QtQuick
import Kos.Ui

Item {
    id: snow
    required property var skySource
    required property var maskSource
    property real wind: 0
    property real density: 0.8
    property bool motionEnabled: true
    readonly property bool running: visible && motionEnabled && !AppTheme.reduceMotion
    readonly property bool supported: GraphicsInfo.api !== GraphicsInfo.Software
    property real clock: 0
    property double lastTick: 0
    onRunningChanged: lastTick = 0
    Accessible.ignored: true

    // A single clock drives the optical pass; no per-flake QML objects or paints.
    Timer {
        interval: 33
        repeat: true
        running: snow.running && snow.supported
        onTriggered: {
            const now = Date.now()
            if (snow.lastTick > 0) snow.clock += Math.min(0.1, (now - snow.lastTick) / 1000)
            snow.lastTick = now
        }
    }
    Loader {
        anchors.fill: parent
        active: snow.visible && snow.supported
        sourceComponent: ShaderEffect {
            vertexShader: Qt.resolvedUrl("shaders/snow_glass.vert.qsb")
            fragmentShader: Qt.resolvedUrl("shaders/snow_glass.frag.qsb")
            property var source: snow.skySource
            property var maskSource: snow.maskSource
            property vector2d surfaceSize: Qt.vector2d(Math.max(1, width), Math.max(1, height))
            property real clock: snow.clock
            property real wind: snow.wind
            property real density: snow.density
        }
    }
}
