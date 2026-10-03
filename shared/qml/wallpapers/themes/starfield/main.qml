import QtQuick
// 显式导入自身目录:文档位于被 import 的模块目录树内时,同目录隐式类型
// 解析会被模块机制短路,限定导入绕开该行为。
import "." as Theme

// 星尘引力:物理场景画布(本主题文件夹自有副本)+ 共享粒子流 + 前景效果。
Item {
    id: root
    // ---- pack contract ----
    property var host: null
    signal frameReady()
    property string themeId: host ? host.themeId : "starfield"
    property real phase: host ? host.phase : 0
    property bool foreground: host ? host.foreground : false
    property bool economical: host ? host.economical : false
    property int particleCount: host ? host.particleCount : 80
    property var widgetRects: host ? host.widgetRects : []
    property vector4d pointer: host ? host.pointer : Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: host ? host.clickPulse : Qt.vector4d(-10,-10,-100,0)
    property int weatherCode: host ? host.weatherCode : 0
    property real windStrength: host ? host.windStrength : 0.15
    property real windDirection: host ? host.windDirection : 0
    property bool isDay: host ? host.isDay : true
    property bool weatherAvailable: host ? host.weatherAvailable : false
    property string temperature: host ? host.temperature : "--°"
    property string city: host ? host.city : "大气光场"
    readonly property bool rainy: (weatherCode >= 51 && weatherCode <= 67)
        || (weatherCode >= 80 && weatherCode <= 82) || weatherCode >= 95
    readonly property bool snowy: (weatherCode >= 71 && weatherCode <= 77)
        || weatherCode === 85 || weatherCode === 86
    function obstacle(index) {
        const r=widgetRects[index]
        return r ? Qt.vector4d(r.x/Math.max(1,width),r.y/Math.max(1,height),
            r.width/Math.max(1,width),r.height/Math.max(1,height)) : Qt.vector4d(-10,-10,0,0)
    }
    // ---- scene ----
    Loader {
        anchors.fill: parent
        active: !root.foreground
        source: Qt.resolvedUrl("PhysicalSceneBackdrop.qml")
        onLoaded: item.host = root
    }
    Theme.ForegroundEffects {
        anchors.fill: parent
        themeId: root.themeId
        phase: root.phase
        foreground: root.foreground
        economical: root.economical
        rainy: root.rainy
        snowy: root.snowy
        thunderstorm: root.weatherCode >= 95
        blackHoleFrame: Qt.vector4d(0.85,0.46,0.951,-0.309)
        widgetRects: root.widgetRects
        clickPulse: root.clickPulse
        windStrength: root.windStrength
        windDirection: root.windDirection
        pointer: root.pointer
    }
    Loader {
        anchors.fill: parent
        sourceComponent: Theme.FlowParticleField {
            themeId: root.themeId
            phase: root.phase
            foreground: root.foreground
            economical: root.economical
            particleCount: root.particleCount
            pointer: root.pointer
            clickPulse: root.clickPulse
            obstacles: [root.obstacle(0),root.obstacle(1),root.obstacle(2),root.obstacle(3),
                root.obstacle(4),root.obstacle(5),root.obstacle(6),root.obstacle(7)]
        }
    }
}
