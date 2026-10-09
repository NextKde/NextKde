pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property url artwork: ""
    property url fallbackArtwork: ""
    property string artistKey: ""
    property real sidebarWidth: 233
    property real heroHeight: height * .76
    property real scrollOffset: 0
    property real collapse: 0
    readonly property url displayedArtwork: frontIsA ? layerA.artwork : layerB.artwork
    readonly property bool imageReady: frontIsA ? layerA.ready : layerB.ready
    readonly property bool heroReady: imageReady && String(artwork).length > 0 && String(displayedArtwork) === String(artwork)
    readonly property real displayedAspect: imageReady ? (frontIsA ? layerA.sourceAspect : layerB.sourceAspect) : 1.6
    property bool frontIsA: true
    property real frontOpacity: 1
    readonly property url desiredArtwork: String(artwork).length ? artwork : fallbackArtwork
    function sampleContrastSoon() {
        contrastTimer.remaining = 5
        contrastTimer.restart()
    }

    onArtistKeyChanged: {
        if (crossfade.running) crossfade.complete()
        layerA.artwork = ""; layerB.artwork = ""
        prepare()
    }

    function prepare() {
        sampleContrastSoon()
        if (crossfade.running) crossfade.complete()
        if (!String(desiredArtwork).length) { layerA.artwork=""; layerB.artwork=""; return }
        const front = frontIsA ? layerA : layerB
        const next = frontIsA ? layerB : layerA
        if (String(front.artwork) === String(desiredArtwork) && front.ready) return
        // Show a local cover while a remote hero is pending, when available.
        if (!front.ready && !String(front.artwork).length && String(fallbackArtwork).length
                && String(fallbackArtwork) !== String(desiredArtwork)) front.artwork = fallbackArtwork
        next.artwork = desiredArtwork
        if (next.ready) promote(next, !frontIsA)
    }
    function promote(layer, isA) {
        if (!layer.ready || (String(layer.artwork) !== String(desiredArtwork)
                            && String(layer.artwork) !== String(fallbackArtwork))) return
        if (imageReady && String(displayedArtwork) === String(desiredArtwork)
                && String(layer.artwork) !== String(desiredArtwork)) return
        if (frontIsA !== isA) {
            frontIsA = isA
            crossfade.restart()
        }
        sampleContrastSoon()
    }
    onDesiredArtworkChanged: prepare()
    onFallbackArtworkChanged: prepare()
    Component.onCompleted: prepare()
    NumberAnimation {
        id: crossfade; target: root; property: "frontOpacity"
        from: 0; to: 1; duration: AppTheme.duration(440)
        easing.type: Easing.InOutCubic
        onFinished: root.sampleContrastSoon()
    }
    Timer {
        id: contrastTimer; interval: 120; repeat: true
        property int remaining: 0
        onTriggered: {
            if (root.visible && typeof backendBackgroundContrast !== "undefined") backendBackgroundContrast.sample(root)
            if (--remaining <= 0) stop()
        }
    }
    Rectangle { anchors.fill: parent; color: "#253a35" }
    Loader {
        anchors.fill: parent
        active: !root.heroReady || root.frontOpacity < 1
        sourceComponent: ArtworkBackground {
            objectName: "artistSongCoverBackground"
            artwork: root.fallbackArtwork
            sylvakruAuto: true; neutralImage: true
            blurRadius: width * .085
            onVisualReadyChanged: if (visualReady) root.sampleContrastSoon()
            Rectangle { anchors.fill: parent; color: "#60000000" }
        }
    }

    // Reuse the automatic-cover background's separable Gaussian. Blur the
    // source before extending it, so edge silhouettes cannot become long limbs.
    component GaussianPass: ShaderEffectSource {
        id: pass
        required property var inputTexture
        required property vector2d axis
        property real sigma: .075
        textureSize: Qt.size(width,height)
        hideSource: true; visible: false; smooth: true
        sourceItem: ShaderEffect {
            width: pass.width; height: pass.height
            property var source: pass.inputTexture
            property vector2d axis: pass.axis
            property real sigma: pass.sigma
            fragmentShader: "qrc:/shaders/artwork-gaussian.frag.qsb"
        }
    }

    component PortraitLayer: Item {
        id: portrait
        property url artwork: ""
        // The existing cover provider returns transparent 1x1 for missing art.
        readonly property bool ready: photo.status === Image.Ready && (photo.implicitWidth > 1 || photo.implicitHeight > 1)
        readonly property real sidebarFraction: root.sidebarWidth / Math.max(1,root.width)
        readonly property real heroFraction: root.heroHeight / Math.max(1,root.height)
        readonly property real viewAspect: root.width / Math.max(1,root.height)
        readonly property real sourceAspect: photo.implicitWidth / Math.max(1,photo.implicitHeight)
        Image {
            id: photo
            objectName: "artistPhotoLoader"
            source: AppTheme.textureUrl(portrait.artwork)
            sourceSize.width: 2048
            asynchronous: true; visible: false; mipmap: true
            function tryFallback() {
                if ((status === Image.Error || (status === Image.Ready && implicitWidth <= 1 && implicitHeight <= 1))
                        && String(portrait.artwork) === String(root.desiredArtwork)
                        && String(root.fallbackArtwork).length && String(portrait.artwork) !== String(root.fallbackArtwork))
                    portrait.artwork = root.fallbackArtwork
            }
            onStatusChanged: tryFallback()
            onImplicitWidthChanged: tryFallback()
        }
        ShaderEffectSource {
            id: contentBounds
            width: 1; height: 1; textureSize: Qt.size(1,1)
            format: ShaderEffectSource.RGBA16F
            visible: false; hideSource: true; smooth: false
            sourceItem: ShaderEffect {
                width: 1; height: 1
                property var source: photo
                property var blurredSource: photo
                property var boundsSource: photo
                property real sidebarFraction: 0
                property real heroFraction: 1
                property real scrollFraction: 0
                property real collapse: 0
                property real fieldOnly: 2
                fragmentShader: "qrc:/shaders/artist-backdrop.frag.qsb"
            }
        }
        ShaderEffectSource {
            id: backgroundPhoto
            width: softPhotoX.width; height: softPhotoX.height
            textureSize: Qt.size(width,height)
            visible: false; hideSource: true
            sourceItem: ShaderEffect {
                width: backgroundPhoto.width; height: backgroundPhoto.height
                property var source: photo
                property var blurredSource: photo
                property var boundsSource: contentBounds
                property real sidebarFraction: 0
                property real heroFraction: 1
                property real scrollFraction: 0
                property real collapse: 0
                property real fieldOnly: 3
                fragmentShader: "qrc:/shaders/artist-backdrop.frag.qsb"
            }
        }
        GaussianPass {
            id: softPhotoX
            width: 256; height: Math.min(512,Math.max(1,Math.round(256 / Math.max(.1,portrait.sourceAspect))))
            inputTexture: backgroundPhoto; axis: Qt.vector2d(1,0)
        }
        GaussianPass {
            id: softPhoto
            width: softPhotoX.width; height: softPhotoX.height
            inputTexture: softPhotoX; axis: Qt.vector2d(0,1)
        }
        // Only the background field uses the softened photo. The hero below
        // still samples the original image at its complete, original aspect.
        ShaderEffect {
            id: field
            width: 512; height: Math.max(1, Math.round(512 / portrait.viewAspect))
            visible: false
            property var source: softPhoto
            property var blurredSource: softPhoto
            property var boundsSource: contentBounds
            property real sidebarFraction: portrait.sidebarFraction
            property real heroFraction: portrait.heroFraction
            property real scrollFraction: root.scrollOffset / Math.max(1,root.height)
            property real collapse: root.collapse
            property real fieldOnly: 1
            fragmentShader: "qrc:/shaders/artist-backdrop.frag.qsb"
        }
        ShaderEffectSource {
            id: fieldTexture
            width: field.width; height: field.height
            sourceItem: field; hideSource: true; visible: false
            textureSize: Qt.size(width,height)
        }
        GaussianPass {
            id: blurX
            width: field.width; height: field.height
            inputTexture: fieldTexture; axis: Qt.vector2d(1,0); sigma: .055
        }
        GaussianPass {
            id: blurTexture
            width: field.width; height: field.height
            inputTexture: blurX; axis: Qt.vector2d(0,1); sigma: .055
        }
        ShaderEffect {
            objectName: "artistHeroArtwork"
            anchors.fill: parent
            visible: portrait.ready
            property var source: photo
            property var blurredSource: blurTexture
            property var boundsSource: contentBounds
            property real sidebarFraction: portrait.sidebarFraction
            property real heroFraction: portrait.heroFraction
            property real scrollFraction: root.scrollOffset / Math.max(1,root.height)
            property real collapse: root.collapse
            property real fieldOnly: 0
            fragmentShader: "qrc:/shaders/artist-backdrop.frag.qsb"
        }
    }
    PortraitLayer {
        id: layerA; anchors.fill: parent
        visible: root.heroReady
        z: root.frontIsA ? 1 : 0
        opacity: root.frontIsA ? root.frontOpacity : 1
        onReadyChanged: if (ready) root.promote(layerA,true)
    }
    PortraitLayer {
        id: layerB; anchors.fill: parent
        visible: root.heroReady
        z: root.frontIsA ? 0 : 1
        opacity: root.frontIsA ? 1 : root.frontOpacity
        onReadyChanged: if (ready) root.promote(layerB,false)
    }
}
