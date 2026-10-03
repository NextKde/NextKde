import QtQuick

ShaderEffect {
    id: root
    property string themeId: "starfield"
    property real phase: 0
    property bool foreground: false
    property bool economical: false
    property bool rainy: false
    property bool snowy: false
    property bool thunderstorm: false
    property real windStrength: 0.15
    property real windDirection: 0
    property vector4d blackHoleFrame: Qt.vector4d(0.85,0.46,0.951,-0.309)
    property var widgetRects: []
    function target(index) {
        const r=widgetRects[index]
        return r ? Qt.vector4d(r.x/Math.max(1,width),r.y/Math.max(1,height),
            r.width/Math.max(1,width),r.height/Math.max(1,height)) : Qt.vector4d(-10,-10,0,0)
    }
    property real targetCount: Math.min(8,widgetRects.length)
    property vector4d target0: target(0)
    property vector4d target1: target(1)
    property vector4d target2: target(2)
    property vector4d target3: target(3)
    property vector4d target4: target(4)
    property vector4d target5: target(5)
    property vector4d target6: target(6)
    property vector4d target7: target(7)
    property vector4d clickPulse: Qt.vector4d(-10,-10,-100,0)
    property vector4d pointer: Qt.vector4d(-10,-10,0,0)
    property vector2d viewport: Qt.vector2d(width,height)
    property real time: phase
    property real front: foreground ? 1 : 0
    property real theme: themeId === "blackhole" ? 2 : themeId === "weather" ? 1 : 0
    property real quality: economical ? 0 : 1
    property real rain: rainy ? 1 : 0
    property real snow: snowy ? 1 : 0
    property real thunder: thunderstorm ? 1 : 0
    property vector2d wind: Qt.vector2d(Math.sin(windDirection*Math.PI/180)*windStrength,windStrength)
    visible: themeId === "starfield" || themeId === "weather" || themeId === "blackhole"
    fragmentShader: "shaders/foreground_effects.frag.qsb"
}
