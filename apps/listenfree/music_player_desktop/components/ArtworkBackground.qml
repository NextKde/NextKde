pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects

Item {
    id: background
    property url artwork: ""
    property Item motionTexture: null
    property string mode: "SolidMaterial"
    property real blurAmount: 60
    // Global imagery is kept neutral; immersive artwork retains its own treatment.
    property bool neutralImage: false
    property bool sylvakruAuto: false
    property real blurRadius: 56
    property bool playing: false
    property bool reducedMotion: false
    property bool visualReady: false
    property real maskStrength: 0
    onArtworkChanged: visualReady = false
    property real flowTime: 0
    readonly property bool exposed: visible && (!Window.window || Window.window.visibility !== Window.Minimized)
    readonly property color fallbackColor: AppTheme.darkMode ? "#333333" : "#474747"
    clip: true
    // Kawarp's four-tap pass, cached by Qt until its input/offset changes.
    component FlowBlurPass: ShaderEffectSource {
        id: passTexture
        required property var inputTexture
        required property real sampleOffset
        width: 128; height: 128
        textureSize: Qt.size(128, 128)
        format: ShaderEffectSource.RGBA16F
        smooth: true
        hideSource: true
        visible: false
        sourceItem: ShaderEffect {
            width: 128; height: 128
            property var source: passTexture.inputTexture
            property real sampleOffset: passTexture.sampleOffset
            fragmentShader: "qrc:/shaders/artwork-kawase.frag.qsb"
        }
    }
    Rectangle { anchors.fill: parent; color: background.fallbackColor }
    Loader {
        anchors.fill: parent
        active: background.artwork.toString().length > 0 || !!background.motionTexture
        sourceComponent: background.sylvakruAuto ? sylvakruComponent : background.mode === "SolidMaterial" ? solidComponent : background.mode === "DynamicFlow" ? flowComponent : blurComponent
    }
    Component {
        id: sylvakruComponent
        Item {
            id: sampled
            readonly property real sigma: background.blurRadius / Math.max(1,width)
            readonly property int textureWidth: 512
            readonly property int textureHeight: Math.max(1, Math.round(512 * height / Math.max(1, width)))
            Image {
                id: original
                anchors.fill: parent
                source: AppTheme.textureUrl(background.artwork)
                sourceSize: Qt.size(1024,1024)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; visible: false
                onStatusChanged: background.visualReady = status === Image.Ready
            }
            ShaderEffectSource {
                id: cropped
                anchors.fill: parent
                sourceItem: original; hideSource: true; visible: false
                textureSize: Qt.size(sampled.textureWidth,sampled.textureHeight)
            }
            ShaderEffect {
                id: horizontal
                anchors.fill: parent; visible: false
                property var source: cropped
                property vector2d axis: Qt.vector2d(1,0)
                property real sigma: sampled.sigma
                fragmentShader: "qrc:/shaders/artwork-gaussian.frag.qsb"
            }
            ShaderEffectSource {
                id: horizontalTexture
                anchors.fill: parent; visible: false; hideSource: true
                sourceItem: horizontal
                textureSize: Qt.size(sampled.textureWidth,sampled.textureHeight)
            }
            ShaderEffect {
                id: vertical
                anchors.fill: parent; visible: false
                property var source: horizontalTexture
                property vector2d axis: Qt.vector2d(0,1)
                property real sigma: sampled.sigma
                fragmentShader: "qrc:/shaders/artwork-gaussian.frag.qsb"
            }
            // Both expensive passes stay at the same bounded resolution. The
            // final bilinear upscale never repeats 49 samples per window pixel.
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: vertical; hideSource: true; smooth: true
                textureSize: Qt.size(sampled.textureWidth,sampled.textureHeight)
            }
            Image {
                id: meanImage
                width: 20; height: 20; source: AppTheme.textureUrl(background.artwork)
                sourceSize: Qt.size(20,20); fillMode: Image.Stretch
                asynchronous: true; visible: false
            }
            ShaderEffect {
                id: meanColor
                width: 1; height: 1; visible: false
                property var source: meanImage
                property real dark: -1
                fragmentShader: "qrc:/shaders/artwork-palette.frag.qsb"
            }
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: meanColor; hideSource: true
                textureSize: Qt.size(1,1); smooth: false
                opacity: 180 / 255
            }
        }
    }
    Component {
        id: solidComponent
        Item {
            Image { id: paletteImage; width: 64; height: 64; source: AppTheme.textureUrl(background.artwork); sourceSize: Qt.size(64, 64); asynchronous: true; visible: false; onStatusChanged: background.visualReady = status === Image.Ready }
            ShaderEffectSource {
                id: paletteMotionSample
                width: 64; height: 64
                sourceItem: background.motionTexture
                textureSize: Qt.size(64, 64)
                visible: false
            }
            ShaderEffect {
                id: palette
                objectName: "artworkPaletteShader"
                width: 1; height: 1
                property var source: background.motionTexture ? paletteMotionSample : paletteImage
                property real dark: AppTheme.darkMode ? 1 : 0
                fragmentShader: "qrc:/shaders/artwork-palette.frag.qsb"
                visible: false
            }
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: palette
                sourceRect: Qt.rect(0, 0, 1, 1)
                textureSize: Qt.size(1, 1)
                hideSource: true
                smooth: false
                visible: !!background.motionTexture || paletteImage.status === Image.Ready
            }
        }
    }
    Component {
        id: blurComponent
        Item {
            Image {
                id: coverImage
                anchors.fill: parent
                source: AppTheme.textureUrl(background.artwork)
                sourceSize: Qt.size(1024, 1024)
                asynchronous: true
                onStatusChanged: background.visualReady = status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                visible: !background.motionTexture && (background.neutralImage ? background.blurRadius : background.blurAmount) <= 0
            }
            ShaderEffectSource {
                id: motionSample
                objectName: "backgroundMotionSample"
                anchors.fill: parent
                sourceItem: background.motionTexture
                textureSize: Qt.size(512, 512)
                live: true
                visible: !!background.motionTexture && (background.neutralImage ? background.blurRadius : background.blurAmount) <= 0
            }
            MultiEffect {
                objectName: "artworkBlurEffect"
                anchors.fill: parent
                source: background.motionTexture ? motionSample : coverImage
                visible: (background.neutralImage ? background.blurRadius : background.blurAmount) > 0
                blurEnabled: true
                blur: Math.max(0, Math.min(1, background.neutralImage ? background.blurRadius / 64 : background.blurAmount / 100))
                blurMax: background.neutralImage ? 64 : 128
                // MultiEffect extends its pixel radius by (1 + multiplier).
                // Keep the existing 0–64 px rendering and extend only above it.
                blurMultiplier: background.neutralImage ? Math.max(0, background.blurRadius / 64 - 1) : 0
                autoPaddingEnabled: false
                saturation: background.neutralImage ? 0 : -.25
            }
            Rectangle { anchors.fill: parent; color: "#26000000"; visible: !background.neutralImage }
        }
    }
    Component {
        id: flowComponent
        Item {
            id: flowLayer
            // Kawarp keeps the full spatial field at 128px, then applies eight
            // small blur passes. Flow never reduces the artwork to a palette.
            readonly property int sampleSize: 128
            readonly property real blurScale: .55 + .65 * Math.max(0, Math.min(1, background.blurAmount / 100))
            Image { id: texture; width: flowLayer.sampleSize; height: width; source: AppTheme.textureUrl(background.artwork); sourceSize: Qt.size(width, height); visible: false; asynchronous: true; onStatusChanged: background.visualReady = status === Image.Ready }
            ShaderEffectSource {
                id: flowMotionSample
                width: flowLayer.sampleSize; height: width
                sourceItem: background.motionTexture
                textureSize: Qt.size(width, height)
                smooth: true
                visible: false
            }
            ShaderEffect { id: toned; width: flowLayer.sampleSize; height: width; property var source: background.motionTexture ? flowMotionSample : texture; fragmentShader: "qrc:/shaders/artwork-flow-tint.frag.qsb"; visible: false }
            ShaderEffectSource { id: toneTexture; sourceItem: toned; textureSize: Qt.size(128,128); format: ShaderEffectSource.RGBA16F; hideSource: true; smooth: true; visible: false }
            FlowBlurPass { id: blur0; inputTexture: toneTexture; sampleOffset: .5 * flowLayer.blurScale }
            FlowBlurPass { id: blur1; inputTexture: blur0; sampleOffset: 1.5 * flowLayer.blurScale }
            FlowBlurPass { id: blur2; inputTexture: blur1; sampleOffset: 2.5 * flowLayer.blurScale }
            FlowBlurPass { id: blur3; inputTexture: blur2; sampleOffset: 3.5 * flowLayer.blurScale }
            FlowBlurPass { id: blur4; inputTexture: blur3; sampleOffset: 4.5 * flowLayer.blurScale }
            FlowBlurPass { id: blur5; inputTexture: blur4; sampleOffset: 5.5 * flowLayer.blurScale }
            FlowBlurPass { id: blur6; inputTexture: blur5; sampleOffset: 6.5 * flowLayer.blurScale }
            FlowBlurPass { id: blurred; inputTexture: blur6; sampleOffset: 7.5 * flowLayer.blurScale }
            ShaderEffect {
                objectName: "artworkFlowShader"
                anchors.fill: parent
                property var source: blurred
                property real flowTime: background.flowTime
                property real aspect: width / Math.max(1, height)
                property real viewWidth: width
                property real viewHeight: height
                fragmentShader: "qrc:/shaders/artwork-flow.frag.qsb"
            }

        }
    }
    NumberAnimation on flowTime {
        from: 0; to: 60000; duration: 1200000000; loops: Animation.Infinite
        running: background.mode === "DynamicFlow"
        paused: running && (!background.exposed || !background.playing || background.reducedMotion)
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0,0,0,background.maskStrength) }
}
