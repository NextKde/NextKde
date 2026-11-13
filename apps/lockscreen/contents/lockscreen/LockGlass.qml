// SPDX-FileCopyrightText: 2026 Rickky
// SPDX-FileCopyrightText: 2026 KOS
// SPDX-License-Identifier: MIT
// Adapted from MacShell/MacLock/Glass.qml; see LICENSE.MacShell.
import QtQuick

Item {
    id: glass
    property Item texture: null
    property Item frame: null
    property real radius: 24
    property real tint: 0.25
    property real thickness: 24
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property bool accelerated: !softwareRendering && texture !== null && frame !== null
    // Read each ancestor coordinate so bindings follow layout changes.
    readonly property point positionInFrame: {
        let x = 0, y = 0, item = glass
        while (item && item !== frame) { x += item.x; y += item.y; item = item.parent }
        return Qt.point(x, y)
    }
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        visible: !glass.accelerated || shader.status === ShaderEffect.Error
        gradient: Gradient {
            GradientStop { position: 0; color: "#66393f47" }
            GradientStop { position: 1; color: "#8830353a" }
        }
        border.width: 1
        border.color: "#45ffffff"
    }
    ShaderEffect {
        id: shader
        visible: glass.accelerated && status !== ShaderEffect.Error
        x: -10; y: -10
        width: glass.width + 20; height: glass.height + 20
        fragmentShader: Qt.resolvedUrl("liquidglass.frag.qsb")
        property variant src: glass.texture
        property vector2d itemSize: Qt.vector2d(width, height)
        property vector2d glassSize: Qt.vector2d(glass.width, glass.height)
        property vector2d srcSize: Qt.vector2d(glass.frame ? glass.frame.width : 1, glass.frame ? glass.frame.height : 1)
        property vector2d srcOffset: Qt.vector2d(glass.positionInFrame.x - 10, glass.positionInFrame.y - 10)
        property real pad: 10
        property real radius: glass.radius
        property real bezel: Math.min(glass.height * 0.36, 26)
        property real thickness: glass.thickness
        property real dispersion: 0.045
        property real magnify: 0.035
        property real rim: 0.42
        property real grain: 0.004
        property real blurPx: 1.5
        property real tintMix: glass.tint
        property real saturation: 1.12
        property real dark: 1
        property real debug: 0
        property real shadowAmt: 0.4
    }
}
