import QtQuick
// 显式限定自身目录类型:模块目录树内隐式解析会被短路(见 main.qml 注释)。
import "." as Theme

// The cached physical background canvas. Each theme folder (starfield,
// weather, blackhole fallback) owns its own verbatim copy per the
// one-folder-per-theme rule; the preamble below is the pack contract inlined.
Item {
    id: root
    // ---- contract (host injected by the theme's main.qml) ----
    property var host: null
    property string themeId: host ? host.themeId : "starfield"
    property real phase: host ? host.phase : 0
    property bool foreground: host ? host.foreground : false
    property bool economical: host ? host.economical : false
    property var widgetRects: host ? host.widgetRects : []
    property vector4d pointer: host ? host.pointer : Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: host ? host.clickPulse : Qt.vector4d(-10,-10,-100,0)
    property int weatherCode: host ? host.weatherCode : 0
    property bool isDay: host ? host.isDay : true
    readonly property bool rainy: (weatherCode >= 51 && weatherCode <= 67)
        || (weatherCode >= 80 && weatherCode <= 82) || weatherCode >= 95
    readonly property bool snowy: (weatherCode >= 71 && weatherCode <= 77)
        || weatherCode === 85 || weatherCode === 86
    signal frameReady()
    function obstacle(index) {
        const r=widgetRects[index]
        return r ? Qt.vector4d(r.x/Math.max(1,width),r.y/Math.max(1,height),
            r.width/Math.max(1,width),r.height/Math.max(1,height)) : Qt.vector4d(-10,-10,0,0)
    }
    // ---- canvas ----
    readonly property int backgroundLimit: themeId === "weather" ? (economical ? 480 : 640)
        : themeId === "starfield" ? (economical ? 640 : 960) : (economical ? 960 : 1600)
    readonly property int renderWidth: Math.max(1, Math.min(width, backgroundLimit * Math.min(1, width / Math.max(1, height))))
    readonly property int renderHeight: Math.max(1, renderWidth * height / Math.max(1, width))
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(root.renderWidth, root.renderHeight)
    function requestFrame() { Qt.callLater(function() { sceneTexture.scheduleUpdate() }) }
    Component.onCompleted: requestFrame()
    Connections {
        target: root
        function onThemeIdChanged() { root.requestFrame() }
        function onWeatherCodeChanged() { root.requestFrame() }
        function onIsDayChanged() { root.requestFrame() }
    }
    Loader {
        id: tables
        active: root.themeId === "blackhole"
        sourceComponent: Item {
            property alias deflection: deflectionImage.texture
            property alias inverseRadius: inverseRadiusImage.texture
            property alias blackBody: blackBodyImage.texture
            property alias doppler: dopplerImage.texture
            Theme.FloatingPointTable { id: deflectionImage; source: "vendor/black-hole/deflection-float.png"; visible: false }
            Theme.FloatingPointTable { id: inverseRadiusImage; source: "vendor/black-hole/inverse_radius-float.png"; tableWidth: 64; tableHeight: 32; visible: false }
            Theme.FloatingPointTable { id: blackBodyImage; source: "vendor/black-hole/black_body-float.png"; tableWidth: 128; tableHeight: 1; channels: 3; visible: false }
            Theme.FloatingPointTable { id: dopplerImage; source: "vendor/black-hole/doppler-float.png"; tableWidth: 512; tableHeight: 256; channels: 3; visible: false }}
    }
    Image { id: noiseImage; source: "vendor/black-hole/noise_texture.png"; smooth: true; visible: false }
    ShaderEffectSource {
        id: noiseRepeat
        sourceItem: noiseImage
        textureSize: Qt.size(noiseImage.implicitWidth,noiseImage.implicitHeight)
        wrapMode: ShaderEffectSource.Repeat
        smooth: true
        mipmap: true
        live: false
        visible: false
    }
    Item {
        id: sceneBuffer
        width: root.renderWidth
        height: root.renderHeight
        ShaderEffect {
            anchors.fill: parent
            property vector2d viewport: Qt.vector2d(width, height)
            // Cinematic image material or physical fallback; infall shares the same phase.
            property real time: 3.8 + (root.themeId === "blackhole" ? root.phase : Math.floor(root.phase * 4) / 4)
            onTimeChanged: root.requestFrame()
            property real scene: root.themeId === "blackhole" ? 1 : root.themeId === "weather" ? 2 : 0
            property real quality: root.economical ? 0 : 1
            property vector4d pointer: root.pointer
            property vector4d clickPulse: root.clickPulse
            property vector4d obstacle0: root.obstacle(0)
            property vector4d obstacle1: root.obstacle(1)
            property vector4d obstacle2: root.obstacle(2)
            property vector4d obstacle3: root.obstacle(3)
            property vector4d obstacle4: root.obstacle(4)
            property vector4d obstacle5: root.obstacle(5)
            property vector4d obstacle6: root.obstacle(6)
            property vector4d obstacle7: root.obstacle(7)
            property real storm: root.rainy || root.snowy ? 1 : root.weatherCode > 0 ? 0.5 : 0.15
            property real daylight: root.isDay ? 1 : 0
            property var deflectionTable: (tables.item?.deflection ?? noiseRepeat)
            property var inverseRadiusTable: (tables.item?.inverseRadius ?? noiseRepeat)
            property var blackBodyTable: (tables.item?.blackBody ?? noiseRepeat)
            property var noiseTexture: noiseRepeat
            property var dopplerTable: (tables.item?.doppler ?? noiseRepeat)
            fragmentShader: "shaders/physical_scene.frag.qsb"
        }
    }
    ShaderEffectSource {
        id: sceneTexture
        sourceItem: sceneBuffer
        hideSource: true
        live: true
        smooth: true
        textureSize: Qt.size(root.renderWidth, root.renderHeight)
        visible: false
        onScheduledUpdateCompleted: root.frameReady()
    }
    ShaderEffect {
        anchors.fill: parent
        property var source: sceneTexture
        property vector2d pixel: Qt.vector2d(1 / root.renderWidth, 1 / root.renderHeight)
        property real strength: root.themeId === "blackhole" ? 0.85 : 0.32
        // Restrict lower-rim bloom to the shadow boundary of this camera.
        property vector4d horizon: {
            const radius=Math.sqrt(22*22+1.8*1.8)
            const sine=2.598076211/radius*Math.sqrt(1-1/radius)
            return Qt.vector4d(0.85,0.46,sine/Math.sqrt(1-sine*sine)/0.40,
                root.themeId === "blackhole" ? 1 : 0)
        }
        fragmentShader: "shaders/bloom.frag.qsb"
    }
}
