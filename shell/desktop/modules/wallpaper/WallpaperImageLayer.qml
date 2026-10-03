import QtQuick
import qs.desktop.modules.common
import "../../../Kos/Ui/foundation/WallpaperCatalog.js" as WallpaperCatalog

// Ordinary wallpaper for every output. Only a switch briefly keeps two
// screen-sized textures; the outgoing image is released after it finishes.
Item {
    id: root

    property url source: ""
    property var targetScreen: null
    property bool previewTarget: false
    property string fitMode: "crop"
    property string transition: "fade"
    property string activeTransition: "fade"
    property real activeSeed: 0
    readonly property var options: WallpaperCatalog.transitionPreset(activeTransition)
    readonly property bool anyPosition: transition === "any"
    readonly property real originX: activeTransition === "center" ? 0.5
        : anyPosition ? (activeSeed * 127) % 1 : Number(options.positionX ?? 0.5)
    readonly property real originY: activeTransition === "center" ? 0.5
        : anyPosition ? (activeSeed * 251) % 1 : Number(options.positionY ?? 0.5)
    readonly property int effectMode: ({left: 1, right: 2, top: 3, bottom: 4,
        wipe: 5, wave: 6, grow: 7, center: 7, outer: 8, cinematic: 9})[activeTransition] || 0
    readonly property int animationDuration: activeTransition === "simple" ? 260 : 800
    property real revealProgress: 0
    readonly property bool revealSupported: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool useReveal: effectMode > 0 && revealSupported

    function reportReady(path) {
        if (root.previewTarget) WallpaperPreviewService.imageReady(path, root.targetScreen?.name || "")
        else if (root.targetScreen) WallpaperService.reportImageReady(root.targetScreen.name, path)
    }
    // The motion owns the screen until it finishes; the service waits for this
    // before letting the Plasma restyle run.
    function reportSettled() {
        if (root.previewTarget || !root.targetScreen) return
        WallpaperService.reportTransitionSettled(root.targetScreen.name, root.source)
    }
    readonly property real pixelRatio: Math.max(1,
        Number(targetScreen?.devicePixelRatio || 1))
    readonly property size decodedSize: Qt.size(
        Math.max(1, Math.ceil(width * pixelRatio * 1.06)),
        Math.max(1, Math.ceil(height * pixelRatio * 1.06)))
    readonly property int imageFillMode: fitMode === "fit"
        ? Image.PreserveAspectFit : fitMode === "stretch"
        ? Image.Stretch : fitMode === "center"
        ? Image.Pad : Image.PreserveAspectCrop
    readonly property bool ready: currentImage.status === Image.Ready
        || nextImage.status === Image.Ready

    clip: true

    // Swap the two loaded Image objects, never their source URLs. This keeps
    // the incoming texture resident at the final animation frame.
    property var currentImage: imageA
    property var nextImage: imageB
    property var effectImage: null
    property int cleanupFrames: 0
    readonly property bool transitioning: switchAnimation.running || revealAnimation.running
    readonly property int progressEasing: root.useReveal
        ? Easing.Linear : root.activeTransition === "simple" ? Easing.Linear : Easing.InOutCubic

    function requestSource() {
        const requested = root.source.toString()
        if (!requested) {
            revealAnimation.stop()
            switchAnimation.stop()
            cleanupDelay.stop()
            cleanupFrames = 0
            effectImage = null
            currentImage.source = ""
            nextImage.source = ""
            currentImage.opacity = 1
            nextImage.opacity = 0
            return
        }
        // Finish the current motion; the newest request starts from its fully
        // displayed image. Rapid clicks cannot tear down a partially drawn frame.
        if (root.transitioning) return
        if (requested === currentImage.source.toString()) {
            nextImage.opacity = 0
            if (currentImage.status === Image.Ready) {
                reportReady(requested)
                reportSettled()
            }
            return
        }
        cleanupDelay.stop()
        cleanupFrames = 0
        effectImage = null
        nextImage.opacity = 0
        nextImage.scale = 1
        if (requested === nextImage.source.toString()) {
            if (nextImage.status === Image.Ready) startTransition()
        } else {
            nextImage.source = root.source
        }
    }

    function startTransition() {
        if (root.transitioning || nextImage.source.toString() !== root.source.toString()) return
        reportReady(nextImage.source.toString())
        activeSeed = root.previewTarget
            ? WallpaperPreviewService.transitionSeed : WallpaperService.transitionSeed
        activeTransition = WallpaperCatalog.resolvedTransition(root.transition, activeSeed)
        if (!currentImage.source.toString() || activeTransition === "none") {
            promote()
            return
        }
        revealProgress = 0
        effectImage = useReveal ? nextImage : null
        if (useReveal) {
            nextImage.opacity = 1
            revealShader.progress = 0
            revealAnimation.start()
        } else {
            switchAnimation.start()
        }
    }

    function promote() {
        revealProgress = 1
        const outgoing = currentImage
        currentImage = nextImage
        nextImage = outgoing
        currentImage.opacity = 1
        currentImage.scale = 1
        nextImage.opacity = 0
        nextImage.scale = 1
        // Teardown is deferred far past the moving frames. Freeing the
        // outgoing texture and hiding the shader right at the end of the
        // motion costs a visible hitch just as attention peaks.
        if (nextImage.source.toString() || effectImage)
            cleanupDelay.restart()
        if (currentImage.source.toString() !== root.source.toString())
            Qt.callLater(requestSource)
        reportSettled()
    }

    function bufferStatus(buffer) {
        if (buffer.source.toString() !== root.source.toString()) return
        if (buffer.status === Image.Ready) {
            if (buffer === nextImage) startTransition()
            else if (buffer === currentImage) reportReady(buffer.source.toString())
        } else if (buffer.status === Image.Error && buffer === nextImage) {
            console.warn("[WallpaperImageLayer] image failed: " + buffer.source)
            if (root.previewTarget) WallpaperPreviewService.imageFailed(buffer.source.toString())
            else WallpaperService.reportImageFailed(buffer.source.toString())
        }
    }

    onSourceChanged: Qt.callLater(requestSource)
    Component.onCompleted: requestSource()
    Connections {
        target: WallpaperPreviewService
        function onActiveChanged() { Qt.callLater(root.requestSource) }
    }

    // The countdown arms only once the motion has been over for a while, so
    // the texture free and shader teardown cannot land on the ending frames.
    Timer {
        id: cleanupDelay
        interval: 700
        onTriggered: {
            // Never run teardown while a request is loading the next image.
            if (root.transitioning || root.nextImage.source.toString() === root.source.toString()) {
                cleanupDelay.restart()
                return
            }
            root.cleanupFrames = 4
        }
    }

    FrameAnimation {
        running: root.cleanupFrames > 0
        onTriggered: {
            root.cleanupFrames--
            if (root.cleanupFrames === 2) root.nextImage.source = ""
            if (root.cleanupFrames === 0) root.effectImage = null
        }
    }

    Rectangle { anchors.fill: parent; color: "#111111"; z: -1 }

    component WallpaperBuffer: Image {
        id: buffer
        anchors.fill: parent
        z: root.nextImage === buffer ? 1 : 0
        sourceSize: root.decodedSize
        fillMode: root.imageFillMode
        autoTransform: true
        asynchronous: true
        cache: true
        smooth: true
        visible: root.effectImage !== buffer
        onStatusChanged: root.bufferStatus(buffer)
    }

    WallpaperBuffer { id: imageA }
    WallpaperBuffer { id: imageB; opacity: 0 }

    // Sample the loaded image texture directly. A layer.effect would allocate
    // and retire another full-screen render target on each output.
    ShaderEffect {
        id: revealShader
        anchors.fill: parent
        z: 2
        visible: root.effectImage !== null
        property var source: root.effectImage || root.currentImage
        property real progress: 0
        property real direction: WallpaperPreviewService.active ? WallpaperPreviewService.direction : 1
        property real effectMode: root.effectMode
        property real angle: Number(root.options.angle ?? 45) * Math.PI / 180
        property real waveWidth: Number(root.options.waveWidth ?? 0.22)
        property real waveHeight: Number(root.options.waveHeight ?? 0.08)
        property vector2d origin: Qt.vector2d(root.originX, root.originY)
        property real aspect: root.width / Math.max(1, root.height)
        property vector2d paintScale: Qt.vector2d(root.width / Math.max(1, root.effectImage?.paintedWidth || root.width),
            root.height / Math.max(1, root.effectImage?.paintedHeight || root.height))
        property real zoom: 1
        fragmentShader: Qt.resolvedUrl("../../shaders/wallpaper_reveal.frag.qsb")
    }

    // Only uniform writers here: they update values on the render thread
    // without touching scene-graph nodes. The cinematic zoom lives in the
    // shader for the same reason — ScaleAnimators restructure nodes when they
    // stop, which costs a visible hitch on the final frame of every reveal.
    ParallelAnimation {
        id: revealAnimation
        UniformAnimator {
            target: revealShader
            uniform: "progress"
            from: 0
            to: 1
            duration: root.animationDuration
            easing.type: Easing.Linear
        }
        UniformAnimator {
            target: revealShader
            uniform: "zoom"
            from: root.activeTransition === "cinematic" && root.fitMode === "crop" ? 1.03 : 1
            to: 1
            duration: root.animationDuration
            easing.type: Easing.OutCubic
        }
        onFinished: root.promote()
    }

    ParallelAnimation {
        id: switchAnimation
        NumberAnimation {
            target: root
            property: "revealProgress"
            from: 0
            to: 1
            duration: root.animationDuration
            easing.type: root.progressEasing
        }
        NumberAnimation {
            target: currentImage
            property: "scale"
            from: 1
            to: root.activeTransition === "cinematic" && root.revealSupported && root.fitMode === "crop" ? 1.018 : 1
            duration: root.animationDuration
            easing.type: root.progressEasing
        }
        NumberAnimation {
            target: nextImage
            property: "scale"
            from: root.activeTransition === "cinematic" && root.revealSupported && root.fitMode === "crop" ? 1.03 : 1
            to: 1
            duration: root.animationDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: nextImage
            property: "opacity"
            from: root.useReveal ? 1 : 0
            to: 1
            duration: root.animationDuration
            easing.type: root.progressEasing
        }
        onFinished: root.promote()
    }
}
