import QtQuick
// 显式限定自身目录类型:模块目录树内隐式解析会被短路(见 main.qml 注释)。
import "." as Theme

Item {
    id: root
    property string themeId: "forest"
    property real phase: 0
    property bool foreground: false
    property bool economical: false
    property vector4d pointer: Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: Qt.vector4d(-10,-10,-100,0)
    property var widgetRects: []
    signal frameReady()
    function target(index) {
        const r=widgetRects[index]
        return r ? Qt.vector4d(r.x/Math.max(1,width),r.y/Math.max(1,height),
            r.width/Math.max(1,width),r.height/Math.max(1,height)) : Qt.vector4d(-10,-10,0,0)
    }
    Loader {
        anchors.fill: parent
        active: root.themeId === "forest"
        sourceComponent: Theme.ForestFireflies {
            phase: root.phase
            foreground: root.foreground
            economical: root.economical
            pointer: root.pointer
            clickPulse: root.clickPulse
            widgetRects: root.widgetRects
            onFrameReady: root.frameReady()
        }
    }
    Image {
        id: sceneryImage
        source: root.themeId === "forest" ? "" : root.foreground
            ? "vendor/black-hole/noise_texture.png" : "assets/underwater-cinematic.png"
        sourceSize: Qt.size(Math.max(1, Math.min(2048, Math.ceil(root.width))),
            Math.max(1, Math.min(2048, Math.ceil(root.height))))
        visible: false
        smooth: true
        onStatusChanged: if (status === Image.Ready) Qt.callLater(root.frameReady)
    }
    ShaderEffect {
        visible: root.themeId !== "forest"
        anchors.fill: parent
        property vector2d viewport: Qt.vector2d(width,height)
        property var scenery: sceneryImage
        property real imageAspect: sceneryImage.implicitWidth / Math.max(1, sceneryImage.implicitHeight)
        property real imageReady: sceneryImage.status === Image.Ready ? 1 : 0
        property real time: root.phase
        property real scene: root.themeId === "forest" ? 1 : 0
        property real front: root.foreground ? 1 : 0
        property real quality: root.economical ? 0 : 1
        property vector4d pointer: root.pointer
        property vector4d clickPulse: root.clickPulse
        property real targetCount: Math.min(8,root.widgetRects.length)
        property vector4d target0: root.target(0)
        property vector4d target1: root.target(1)
        property vector4d target2: root.target(2)
        property vector4d target3: root.target(3)
        property vector4d target4: root.target(4)
        property vector4d target5: root.target(5)
        property vector4d target6: root.target(6)
        property vector4d target7: root.target(7)
        fragmentShader: "shaders/nature_wallpaper.frag.qsb"
    }
    Component.onCompleted: Qt.callLater(root.frameReady)
    onThemeIdChanged: Qt.callLater(root.frameReady)
}
