import QtQuick
import qs.desktop.modules.common
import "SpatialPointer.mjs" as SpatialPointer

// GPU-only wallpaper presentation. The worker prepares optional layered
// assets; this item falls back to the depth shader when they are unavailable.
Item {
    id: root

    // Subject-only rendering is shared with the desktop widget foreground.
    property bool foregroundOnly: false
    property bool renderingEnabled: true
    property var targetScreen: null
    readonly property bool selectedOutput: targetScreen !== null
        && targetScreen !== undefined
        && ScreenLifecycle.activeScreen !== null
        && targetScreen.name === ScreenLifecycle.activeScreen.name
    readonly property bool active: renderingEnabled && selectedOutput && SpatialWallpaperService.ready
        && (!WallpaperPreviewService.active || WallpaperPreviewService.mode === "image")
    visible: selectedOutput
    opacity: visualReady && !SpatialWallpaperService.activationPending ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
    function finishPresentation() {
        Qt.callLater(() => {
            if (!root.foregroundOnly && root.visualReady && SpatialWallpaperService.activationPending)
                SpatialWallpaperService.presentationReady()
        })
    }
    onVisualReadyChanged: if (visualReady) finishPresentation()
    property real pointerX: 0
    property real pointerY: 0
    // Sensitivity changes the input curve, not the renderer's camera limits.
    // Apply it once here so background, subject and preview stay registered.
    property real pointerSensitivity: 3
    property real renderedPointerX: SpatialPointer.responsivePointer(pointerX, pointerSensitivity)
    property real renderedPointerY: SpatialPointer.responsivePointer(pointerY, pointerSensitivity)
    Behavior on renderedPointerX { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on renderedPointerY { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    // ShaderEffect receives the raw Image texture, not Image's fillMode.
    // Recreate PreserveAspectCrop in texture coordinates for both inputs.
    readonly property real sourceAspect: sourceImage.implicitHeight > 0
        ? sourceImage.implicitWidth / sourceImage.implicitHeight : 1
    readonly property real outputAspect: height > 0 ? width / height : 1
    readonly property real outputScale: targetScreen
        ? Math.max(1, Number(targetScreen.devicePixelRatio || 1)) : 1
    readonly property size textureSize: Qt.size(
        Math.max(1, Math.round(width * outputScale)),
        Math.max(1, Math.round(height * outputScale)))
    readonly property vector2d cropScale: Qt.vector2d(
        Math.min(1, outputAspect / sourceAspect),
        Math.min(1, sourceAspect / outputAspect))
    readonly property bool layeredTexturesReady:
        SpatialWallpaperService.layeredReady
        && backgroundImage.status === Image.Ready
        && matteImage.status === Image.Ready
        && influenceImage.status === Image.Ready
    readonly property bool meshRendererAvailable: meshRenderer.item !== null
        && meshRenderer.item.ready
    readonly property bool visualReady: active && sourceImage.status === Image.Ready
        && (meshRendererAvailable || (depthImage.status === Image.Ready
            && (!SpatialWallpaperService.layeredReady || layeredTexturesReady)))

    function syncMeshRenderer() {
        if (!meshRenderer.item)
            return
        meshRenderer.item.foregroundOnly = root.foregroundOnly
        meshRenderer.item.textureSize = root.textureSize
        meshRenderer.item.wallpaperPath = SpatialWallpaperService.wallpaperUrl
        meshRenderer.item.depthPath = SpatialWallpaperService.depthPath
        meshRenderer.item.backgroundPath = SpatialWallpaperService.layeredReady
            ? SpatialWallpaperService.backgroundPath : ""
        meshRenderer.item.mattePath = SpatialWallpaperService.layeredReady
            ? SpatialWallpaperService.mattePath : ""
        meshRenderer.item.pointerX = renderedPointerX
        meshRenderer.item.pointerY = renderedPointerY
        meshRenderer.item.outputAspect = outputAspect
    }

    onActiveChanged: console.log("[DepthWallpaperLayer] active=" + active
        + " output=" + (targetScreen ? targetScreen.name : "none"))
    onMeshRendererAvailableChanged: {
        if (active)
            console.log("[DepthWallpaperLayer] renderer="
                + (meshRendererAvailable ? "3D mesh" : "shader fallback"))
    }

    Image {
        id: sourceImage
        anchors.fill: parent
        visible: false
        source: root.active ? SpatialWallpaperService.wallpaperUrl : ""
        sourceSize: root.textureSize
        fillMode: Image.PreserveAspectCrop
        autoTransform: true
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] source image failed: " + source)
        }
    }

    Image {
        id: depthImage
        anchors.fill: parent
        visible: false
        source: root.active ? SpatialWallpaperService.depthPath : ""
        sourceSize: root.textureSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] depth image failed: " + source)
        }
    }

    Image {
        id: backgroundImage
        anchors.fill: parent
        visible: false
        source: root.active && SpatialWallpaperService.layeredReady
            ? SpatialWallpaperService.backgroundPath : ""
        sourceSize: root.textureSize
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] background failed: " + source)
        }
    }

    Image {
        id: matteImage
        anchors.fill: parent
        visible: false
        source: root.active && SpatialWallpaperService.layeredReady
            ? SpatialWallpaperService.mattePath : ""
        sourceSize: root.textureSize
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] matte failed: " + source)
        }
    }

    Image {
        id: influenceImage
        anchors.fill: parent
        visible: false
        source: root.active && SpatialWallpaperService.layeredReady
            ? SpatialWallpaperService.influencePath : ""
        sourceSize: root.textureSize
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] influence failed: " + source)
        }
    }

    // Loaded only when depth assets are ready. If the optional Qt Quick 3D
    // runtime/plugin is unavailable, Loader falls back to the shader paths.
    Loader {
        id: meshRenderer
        anchors.fill: parent
        active: root.active && root.layeredTexturesReady
        source: Qt.resolvedUrl("DepthWallpaper3D.qml")
        onLoaded: root.syncMeshRenderer()
        onStatusChanged: if (status === Loader.Error)
            console.warn("[DepthWallpaperLayer] 3D renderer unavailable; using shader fallback")
    }

    ShaderEffect {
        anchors.fill: parent
        visible: !root.foregroundOnly && !root.meshRendererAvailable && root.active && sourceImage.status === Image.Ready
            && depthImage.status === Image.Ready && !root.layeredTexturesReady
        property variant source: sourceImage
        property variant depthMap: depthImage
        property vector2d pointer: Qt.vector2d(root.renderedPointerX,
            root.renderedPointerY)
        property vector2d cropScale: root.cropScale
        fragmentShader: Qt.resolvedUrl("shaders/depth_parallax.frag.qsb")
    }

    ShaderEffect {
        anchors.fill: parent
        visible: !root.meshRendererAvailable && root.active && sourceImage.status === Image.Ready
            && root.layeredTexturesReady
        property variant source: sourceImage
        property real foregroundOnly: root.foregroundOnly ? 1 : 0
        property variant background: backgroundImage
        property variant matte: matteImage
        property variant influence: influenceImage
        property variant depthMap: depthImage
        property vector2d pointer: Qt.vector2d(root.renderedPointerX,
            root.renderedPointerY)
        property vector2d cropScale: root.cropScale
        fragmentShader: Qt.resolvedUrl("shaders/layered_wallpaper.frag.qsb")
    }

    onForegroundOnlyChanged: syncMeshRenderer()
    onRenderedPointerXChanged: syncMeshRenderer()
    onRenderedPointerYChanged: syncMeshRenderer()
    onOutputAspectChanged: syncMeshRenderer()
    onTextureSizeChanged: syncMeshRenderer()
    Connections {
        target: SpatialWallpaperService
        function onActivationPendingChanged() {
            if (root.visualReady) root.finishPresentation()
        }
        function onDepthPathChanged() { root.syncMeshRenderer() }
        function onBackgroundPathChanged() { root.syncMeshRenderer() }
        function onMattePathChanged() { root.syncMeshRenderer() }
        function onWallpaperUrlChanged() { root.syncMeshRenderer() }
    }

}
