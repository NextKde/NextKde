pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtMultimedia

Item {
    id: root
    property var settingsStore: null
    property url artwork: ""
    property bool playing: false
    property Item motionTexture: null
    property string autoStyle: "BlurredArtwork"
    property bool immersive: false
    function setting(key, fallback) {
        if(!settingsStore)return fallback
        const revision=settingsStore.revision
        return settingsStore.value(key,fallback)
    }
    readonly property string backgroundType: immersive ? "AutoCover" : setting("background.type","AutoCover")
    readonly property bool localMedia: backgroundType === "Video" || backgroundType === "Wallpaper"
    readonly property url localMediaFile: localMedia ? setting(backgroundType === "Wallpaper" ? "background.wallpaper" : "background.video", "") : ""
    readonly property var resolvedMedia: localMedia && settingsStore
        ? settingsStore.resolveBackground(localMediaFile, backgroundType === "Wallpaper") : ({})
    readonly property bool videoBackground: localMedia && resolvedMedia.kind === "Video"
    readonly property bool exposed: visible && (!Window.window || (Window.window.visible && Window.window.visibility !== Window.Minimized))
    readonly property url defaultImage: Qt.resolvedUrl("../assets/background-pastel.svg")
    readonly property url chosenImage: setting("background.image","") || defaultImage
    readonly property url desiredSource: localMedia ? (resolvedMedia.kind === "Image" ? resolvedMedia.source : "")
        : backgroundType === "Color" ? "" : backgroundType === "Image" ? chosenImage : artwork
    readonly property string visualStyle: backgroundType === "Image" || localMedia ? "BlurredArtwork" : autoStyle
    readonly property real mask: immersive ? .24 : Math.max(0,Math.min(1,setting("background.mask",0)/100))
    readonly property real blurRadius: immersive ? 0 : Math.max(0,Math.min(192,
        backgroundType === "AutoCover" ? setting("background.autoBlurPx",width*.03) : setting("background.blur",56)))
    readonly property color chosenColor: setting("background.color","#c8bad9")
    function sampleContrastSoon() {
        sampleTimer.remaining = AppTheme.motionEnabled ? 5 : 1
        sampleTimer.restart()
    }
    onVisibleChanged: if (visible) sampleContrastSoon()
    onMaskChanged: sampleContrastSoon()
    Connections { target: AppTheme; function onDarkModeChanged() { root.sampleContrastSoon() } }
    onChosenColorChanged: sampleContrastSoon()
    onFrontIsAChanged: { crossfade.restart(); sampleContrastSoon() }
    Timer {
        id: sampleTimer; interval: AppTheme.motionEnabled ? 120 : 50; repeat: true
        property int remaining: 0
        onTriggered: {
            if(root.visible && !root.immersive && typeof backendBackgroundContrast !== "undefined")backendBackgroundContrast.sample(root)
            if (--remaining <= 0) stop()
        }
    }
    property bool frontIsA: true
    property real frontOpacity: 1
    function releaseOutgoing() {
        const front = frontIsA ? layerA : layerB
        // A rapid switch may already be loading the next image underneath.
        if (String(front.artwork) !== String(desiredSource)
                || (String(desiredSource).length && !front.visualReady)) return
        const old = frontIsA ? layerB : layerA
        old.motionTexture = null
        old.artwork = ""
    }
    NumberAnimation {
        id: crossfade; target: root; property: "frontOpacity"; from: 0; to: 1
        duration: AppTheme.duration(500)
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.645,0.045,0.355,1,1,1]
        onFinished: root.releaseOutgoing()
    }
    function promote(layer, isA) {
        if(layer.visualReady && String(layer.artwork)===String(desiredSource))frontIsA=isA
    }
    function updateTextures() {
        const texture=backgroundType === "AutoCover" ? motionTexture : null
        layerA.motionTexture=String(layerA.artwork)===String(desiredSource) ? texture : null
        layerB.motionTexture=String(layerB.artwork)===String(desiredSource) ? texture : null
    }
    onMotionTextureChanged: Qt.callLater(updateTextures)
    onBackgroundTypeChanged: { Qt.callLater(updateTextures);sampleContrastSoon() }
    function prepare() {
        Qt.callLater(updateTextures)
        const front=frontIsA?layerA:layerB
        const target=frontIsA?layerB:layerA
        if(String(front.artwork)===String(desiredSource) && (front.visualReady || !String(desiredSource).length))return
        if(!String(desiredSource).length) {
            target.artwork=""
            frontIsA=!frontIsA
            return
        }
        if(String(target.artwork)===String(desiredSource) && target.visualReady)frontIsA=!frontIsA
        else target.artwork=desiredSource
    }
    onDesiredSourceChanged: prepare()
    Component.onCompleted: { prepare();sampleContrastSoon() }
    Rectangle { anchors.fill: parent; color: AppTheme.pageBackground }
    ArtworkBackground {
        id: layerA
        visible: root.backgroundType !== "Color" && !root.localMedia || root.resolvedMedia.kind === "Image"
        anchors.fill: parent; mode: root.visualStyle
        neutralImage: !root.immersive
        sylvakruAuto: !root.immersive && root.backgroundType === "AutoCover"
        blurRadius: root.blurRadius
        blurAmount: root.setting("nowPlaying.backgroundBlur",85)
        playing: root.playing && (root.frontIsA || root.frontOpacity < 1); reducedMotion: !AppTheme.motionEnabled
        // Keep the old image opaque underneath. Fading both layers exposes the
        // base color halfway through and adds an unintended grey brightness dip.
        z: root.frontIsA ? 1 : 0
        opacity: root.frontIsA ? root.frontOpacity : 1
        onVisualReadyChanged: if(visualReady)Qt.callLater(root.promote,layerA,true)
    }
    ArtworkBackground {
        id: layerB
        visible: root.backgroundType !== "Color" && !root.localMedia || root.resolvedMedia.kind === "Image"
        anchors.fill: parent; mode: root.visualStyle
        neutralImage: !root.immersive
        sylvakruAuto: !root.immersive && root.backgroundType === "AutoCover"
        blurRadius: root.blurRadius
        blurAmount: root.setting("nowPlaying.backgroundBlur",85)
        playing: root.playing && (!root.frontIsA || root.frontOpacity < 1); reducedMotion: !AppTheme.motionEnabled
        z: root.frontIsA ? 0 : 1
        opacity: root.frontIsA ? 1 : root.frontOpacity
        onVisualReadyChanged: if(visualReady)Qt.callLater(root.promote,layerB,false)
    }
    Loader {
        id: localVideoLoader
        objectName: "backgroundVideoLoader"
        anchors.fill: parent
        active: root.videoBackground
        z: 1
        sourceComponent: Item {
            id: videoBackgroundItem
            property var movie: typeof backendArtworkVideoFactory !== "undefined"
                ? backendArtworkVideoFactory.create(videoBackgroundItem) : null
            Binding { target: videoBackgroundItem.movie; property: "videoSink"; value: backgroundVideo.videoSink; when: !!videoBackgroundItem.movie }
            Binding { target: videoBackgroundItem.movie; property: "playing"; value: root.exposed; when: !!videoBackgroundItem.movie }
            Binding { target: videoBackgroundItem.movie; property: "source"; value: root.resolvedMedia.source || ""; when: !!videoBackgroundItem.movie }
            VideoOutput {
                id: backgroundVideo
                objectName: "backgroundVideoOutput"
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                visible: root.blurRadius <= 0
            }
            ArtworkBackground {
                anchors.fill: parent
                visible: root.blurRadius > 0
                mode: "BlurredArtwork"
                neutralImage: true
                blurRadius: root.blurRadius
                motionTexture: videoBackgroundItem.movie && videoBackgroundItem.movie.ready ? backgroundVideo : null
            }
            Connections {
                target: videoBackgroundItem.movie
                function onReadyChanged() { if (videoBackgroundItem.movie.ready) root.sampleContrastSoon() }
            }
        }
    }
    Text {
        anchors.centerIn: parent
        width: Math.min(480, parent.width - 40)
        z: 3
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        color: AppTheme.textSecondary
        text: root.resolvedMedia.error || (localVideoLoader.item && localVideoLoader.item.movie
            ? localVideoLoader.item.movie.errorString : "")
        visible: root.localMedia && text.length > 0
    }
    Rectangle {
        anchors.fill: parent; visible: root.backgroundType==="Color"; z: 2
        color: root.chosenColor
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    Image {
        z: 2
        anchors.fill: parent
        visible: root.backgroundType === "Image" && String(root.chosenImage) === String(root.defaultImage)
        source: "../assets/background-grain.svg"
        fillMode: Image.Tile; opacity: .018
    }
    Rectangle {
        z: 2
        anchors.fill: parent
        color: Qt.rgba(0,0,0,root.mask)
    }
}
