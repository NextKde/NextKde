import QtQuick
// 显式导入自身目录:文档位于被 import 的模块目录树内时,同目录隐式类型
// 解析会被模块机制短路,限定导入绕开该行为。
import "." as Theme

// 事件视界:cinematic 参考图材质优先,图片加载失败回退物理画布。
// 粒子由 cinematic 材质内部处理,没有共享粒子流。
Item {
    id: root
    // ---- pack contract ----
    property var host: null
    signal frameReady()
    property string themeId: host ? host.themeId : "blackhole"
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
    // ---- scene ----
    property bool cinematicBlackHole: true
    readonly property bool cinematicActive: cinematicBlackHole && !(cinematic.item?.failed ?? false)
    readonly property vector4d blackHoleFrame: {
        if (!cinematicActive) return Qt.vector4d(0.85,0.46,0.951,-0.309)
        const aspect=width/Math.max(1,height)
        const cropX=aspect>1.5 ? 1 : aspect/1.5
        const cropY=aspect>1.5 ? 1.5/aspect : 1
        return Qt.vector4d(0.5+0.35/cropX,0.5-0.14/cropY,0.961,-0.276)
    }
    Loader {
        id: cinematic
        anchors.fill: parent
        active: !root.foreground && root.cinematicBlackHole
        sourceComponent: Theme.CinematicBlackHole {
            phase: root.phase
            pointer: root.pointer
            clickPulse: root.clickPulse
            onFrameReady: root.frameReady()
        }
    }
    Loader {
        anchors.fill: parent
        active: !root.foreground && !root.cinematicActive
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
        blackHoleFrame: root.blackHoleFrame
        widgetRects: root.widgetRects
        clickPulse: root.clickPulse
        windStrength: root.windStrength
        windDirection: root.windDirection
        pointer: root.pointer
    }
}
