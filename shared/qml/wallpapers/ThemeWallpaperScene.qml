import QtQuick

Item {
    id: root
    property string themeId: "starfield"
    property bool cinematicBlackHole: true
    readonly property bool natureActive: themeId === "underwater" || themeId === "forest"
    readonly property bool cinematicActive: themeId === "blackhole" && cinematicBlackHole && !(cinematic.item?.failed ?? false)
    readonly property vector4d blackHoleFrame: {
        if (!cinematicActive) return Qt.vector4d(0.85,0.46,0.951,-0.309)
        const aspect=width/Math.max(1,height)
        const cropX=aspect>1.5 ? 1 : aspect/1.5
        const cropY=aspect>1.5 ? 1.5/aspect : 1
        return Qt.vector4d(0.5+0.35/cropX,0.5-0.14/cropY,0.961,-0.276)
    }
    property real phase: 0
    property bool foreground: false
    property bool economical: false
    property int particleCount: 80
    property var widgetRects: []
    property vector4d pointer: Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: Qt.vector4d(-10,-10,-100,0)
    function obstacle(index) {
        const r=widgetRects[index]
        return r ? Qt.vector4d(r.x/Math.max(1,width),r.y/Math.max(1,height),
            r.width/Math.max(1,width),r.height/Math.max(1,height)) : Qt.vector4d(-10,-10,0,0)
    }
    property int weatherCode: 0
    property real windStrength: 0.15
    property real windDirection: 0
    property bool isDay: true
    property string temperature: "--°"
    property string city: "大气光场"
    property bool weatherAvailable: false
    readonly property bool rainy: (weatherCode >= 51 && weatherCode <= 67)
        || (weatherCode >= 80 && weatherCode <= 82) || weatherCode >= 95
    readonly property bool snowy: (weatherCode >= 71 && weatherCode <= 77)
        || weatherCode === 85 || weatherCode === 86
    readonly property int backgroundLimit: themeId === "weather" ? (economical ? 480 : 640)
        : themeId === "starfield" ? (economical ? 640 : 960) : (economical ? 960 : 1600)
    readonly property int renderWidth: Math.max(1, Math.min(width, backgroundLimit * Math.min(1, width / Math.max(1, height))))
    readonly property int renderHeight: Math.max(1, renderWidth * height / Math.max(1, width))
    signal frameReady()
    clip: true

    Loader {
        id: cinematic
        anchors.fill: parent
        active: !root.foreground && root.themeId === "blackhole" && root.cinematicBlackHole
        sourceComponent: CinematicBlackHole {
            phase: root.phase
            pointer: root.pointer
            clickPulse: root.clickPulse
            onFrameReady: root.frameReady()
        }
    }
    // Cache the composed background between bounded clock updates.
    // Float lookup decoding is performed once, outside the animation path.
    Loader {
        id: backdrop
        anchors.fill: parent
        active: !root.foreground && !root.cinematicActive && !root.natureActive
        sourceComponent: Item {
            id: cachedBackground
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(root.renderWidth, root.renderHeight)
            function requestFrame() { Qt.callLater(function() { sceneTexture.scheduleUpdate() }) }
            Component.onCompleted: requestFrame()
            Connections {
                target: root
                function onThemeIdChanged() { cachedBackground.requestFrame() }
                function onWeatherCodeChanged() { cachedBackground.requestFrame() }
                function onIsDayChanged() { cachedBackground.requestFrame() }
            }
            Loader {
                id: tables
                active: root.themeId === "blackhole"
                sourceComponent: Item {
                    property alias deflection: deflectionImage.texture
                    property alias inverseRadius: inverseRadiusImage.texture
                    property alias blackBody: blackBodyImage.texture
                    property alias doppler: dopplerImage.texture
                    FloatingPointTable { id: deflectionImage; source: "vendor/black-hole/deflection-float.png"; visible: false }
                    FloatingPointTable { id: inverseRadiusImage; source: "vendor/black-hole/inverse_radius-float.png"; tableWidth: 64; tableHeight: 32; visible: false }
                    FloatingPointTable { id: blackBodyImage; source: "vendor/black-hole/black_body-float.png"; tableWidth: 128; tableHeight: 1; channels: 3; visible: false }
                    FloatingPointTable { id: dopplerImage; source: "vendor/black-hole/doppler-float.png"; tableWidth: 512; tableHeight: 256; channels: 3; visible: false }
                }
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
                    onTimeChanged: cachedBackground.requestFrame()
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
    }
    Loader {
        anchors.fill: parent
        active: root.natureActive
        sourceComponent: NatureWallpaper {
            themeId: root.themeId
            phase: root.phase
            foreground: root.foreground
            economical: root.economical
            pointer: root.pointer
            clickPulse: root.clickPulse
            widgetRects: root.widgetRects
            onFrameReady: root.frameReady()
        }
    }
    ForegroundEffects {
        anchors.fill: parent
        themeId: root.themeId
        phase: root.phase
        foreground: root.foreground
        economical: root.economical
        rainy: root.rainy
        snowy: root.snowy
        blackHoleFrame: root.blackHoleFrame
        widgetRects: root.widgetRects
        clickPulse: root.clickPulse
        thunderstorm: root.weatherCode >= 95
        windStrength: root.windStrength
        windDirection: root.windDirection
        pointer: root.pointer
    }
    Loader {
        active: !root.natureActive && root.themeId !== "blackhole" && !(root.foreground && root.themeId === "weather")
        anchors.fill: parent
        sourceComponent: FlowParticleField {
        anchors.fill: parent
        themeId: root.themeId
        phase: root.phase
        foreground: root.foreground
        economical: root.economical
        particleCount: root.particleCount
        pointer: root.pointer
        clickPulse: root.clickPulse
        obstacles: [root.obstacle(0),root.obstacle(1),root.obstacle(2),root.obstacle(3),root.obstacle(4),root.obstacle(5),root.obstacle(6),root.obstacle(7)]
        }
    }
}
