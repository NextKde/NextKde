pragma Singleton
import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.platform
import "../../../Kos/Ui"

// Opt-in orchestration for the desktop wallpaper pipeline. The generator and
// model live in the platform's child process; this service only tracks which
// wallpaper is current and publishes cached paths to the renderer.
QtObject {
    id: root

    property string imagePath: ""
    property string depthPath: ""
    property string backgroundPath: ""
    property string mattePath: ""
    property string influencePath: ""
    property string requestedPath: ""
    property bool requestInFlight: false
    property bool preparationRequested: false
    property int retryCount: 0
    property string errorMessage: ""
    property bool previewEnabled: false
    property bool activationPending: false
    property bool waitingForResources: false
    readonly property bool enabled: AppearanceConfigService.spatialWallpaperEnabled
    readonly property url wallpaperUrl: WallpaperPreviewService.active
        ? WallpaperPreviewService.image : WallpaperService.wallpaperUrl
    // The preview draft may be an image while the committed desktop is a theme.
    readonly property bool imageMode: WallpaperPreviewService.active
        ? WallpaperPreviewService.mode === "image" : WallpaperService.mode !== "theme"
    readonly property bool ready: imageMode && !ThemeWallpaperService.active
        && SpatialResourceService.enabled
        && (WallpaperPreviewService.active ? (previewEnabled || activationPending)
            : (enabled || activationPending)) && depthPath.length > 0
        && imagePath === currentImagePath()
    readonly property bool prepared: depthPath.length > 0
        && imagePath === currentImagePath()
    readonly property bool layeredReady: ready && backgroundPath.length > 0
        && mattePath.length > 0 && influencePath.length > 0

    function currentImagePath() {
        const value = wallpaperUrl.toString()
        if (value.startsWith("/"))
            return value
        if (!value.startsWith("file://"))
            return ""
        try {
            return decodeURIComponent(value.replace(/^file:\/\//, ""))
        } catch (error) {
            console.warn("[SpatialWallpaper] invalid wallpaper URL: " + error)
            return ""
        }
    }

    function refreshWallpaper() {
        const nextPath = currentImagePath()
        if (nextPath !== imagePath) {
            cancelPreparation()
            imagePath = nextPath
            depthPath = ""
            backgroundPath = ""
            mattePath = ""
            influencePath = ""
            errorMessage = ""
            retryCount = 0
            retryTimer.stop()
        }
        if (enabled && WallpaperService.mode !== "theme" && !WallpaperPreviewService.active && SpatialResourceService.enabled && nextPath)
            requestDelay.restart()
    }

    function requestDepthIfNeeded() {
        if ((!enabled && !preparationRequested) || !SpatialResourceService.enabled || !imagePath
                || requestInFlight || depthPath)
            return
        requestedPath = imagePath
        requestInFlight = true
        console.log("[SpatialWallpaper] requesting depth for " + requestedPath)
        DepthManager.generate(requestedPath)
    }

    function cancelActivation() {
        if (!WallpaperPreviewService.active) AppearanceConfigService.updateSpatialWallpaperEnabled(false)
        cancelPreparation()
    }
    function cancelPreparation() {
        const hadTask = requestInFlight || preparationRequested || waitingForResources
        requestDelay.stop()
        retryTimer.stop()
        presentationWatchdog.stop()
        DepthManager.invalidate()
        requestedPath = ""
        requestInFlight = false
        preparationRequested = false
        waitingForResources = false
        activationPending = false
        previewEnabled = false
        depthPath = ""
        backgroundPath = ""
        mattePath = ""
        influencePath = ""
        errorMessage = ""
        if (hadTask) SpatialResourceService.cancel()
    }
    function prepareForEnable() {
        if (preparationRequested || requestInFlight) return false
        refreshWallpaper()
        if (!imageMode || !imagePath) {
            errorMessage = "请先选择图片壁纸"
            return false
        }
        errorMessage = ""
        retryCount = 0
        preparationRequested = true
        activationPending = true
        if (!SpatialResourceService.enabled) {
            waitingForResources = true
            if (!SpatialResourceService.initialize()) {
                waitingForResources = false
                preparationRequested = false
                activationPending = false
                errorMessage = SpatialResourceService.errorMessage || "资源正在检查，请稍后重试"
                return false
            }
        } else requestDepthIfNeeded()
        return true
    }
    // Called only after the textures/renderer have loaded, before the visual fade-in.
    function presentationReady() {
        if (!activationPending || !prepared) return
        presentationWatchdog.stop()
        if (WallpaperPreviewService.active) previewEnabled = true
        else {
            WallpaperService.setSlideshow(false, WallpaperService.slideshowIntervalMinutes, JSON.stringify(WallpaperService.slideshowImages))
            WallpaperService.setTakeoverEnabled(true)
            AppearanceConfigService.updateSpatialWallpaperEnabled(true)
        }
        activationPending = false
        preparationRequested = false
    }
    property Connections resources: Connections {
        target: SpatialResourceService
        function onEnabledChanged() {
            if (SpatialResourceService.enabled && root.enabled && !WallpaperPreviewService.active)
                root.refreshWallpaper()
        }
        function onInitialized() {
            if (!root.waitingForResources) return
            root.waitingForResources = false
            root.requestDepthIfNeeded()
        }
        function onErrorMessageChanged() {
            if (root.waitingForResources && SpatialResourceService.errorMessage) {
                root.errorMessage = SpatialResourceService.errorMessage
                root.preparationRequested = false
                root.activationPending = false
                root.waitingForResources = false
            }
        }
    }

    property Timer presentationWatchdog: Timer {
        interval: 20000
        onTriggered: {
            console.warn("[SpatialWallpaper] presentation timed out: " + JSON.stringify({
                wallpaperMode: WallpaperService.mode,
                previewActive: WallpaperPreviewService.active,
                previewMode: WallpaperPreviewService.mode,
                imageMode: root.imageMode,
                ready: root.ready,
                prepared: root.prepared,
                image: root.imagePath,
                depth: root.depthPath,
                background: root.backgroundPath,
                matte: root.mattePath,
                influence: root.influencePath
            }))
            root.cancelPreparation()
            root.errorMessage = "空间素材加载失败，请重试"
        }
    }

    // Wallpaper services can publish several URLs during startup. Let the
    // final URL settle before occupying the worker's bounded request queue.
    property Timer requestDelay: Timer {
        interval: 350
        repeat: false
        onTriggered: root.requestDepthIfNeeded()
    }

    property Timer retryTimer: Timer {
        repeat: false
        onTriggered: root.requestDepthIfNeeded()
    }

    property Connections wallpaperChanges: Connections {
        target: root
        function onWallpaperUrlChanged() { root.refreshWallpaper() }
    }

    property Connections settingChanges: Connections {
        target: AppearanceConfigService
        function onSpatialWallpaperEnabledChanged() {
            if (root.enabled)
                root.refreshWallpaper()
            else {
                root.requestDelay.stop()
                root.retryTimer.stop()
                root.depthPath = ""
                root.backgroundPath = ""
                root.mattePath = ""
                root.influencePath = ""
                root.errorMessage = ""
            }
        }
    }

    property Connections generationReplies: Connections {
        target: DepthManager
        function onFinished(sourcePath, resultPath, width, height, cached,
                            model, contract, backgroundPath, mattePath,
                            influencePath) {
            if (!root.requestInFlight || sourcePath !== root.requestedPath)
                return
            root.requestInFlight = false
            if ((root.enabled || root.preparationRequested)
                    && sourcePath === root.imagePath && resultPath) {
                root.retryCount = 0
                root.errorMessage = ""
                root.backgroundPath = backgroundPath
                root.mattePath = mattePath
                root.influencePath = influencePath
                SpatialResourceService.stage = "正在加载空间素材…"
                SpatialResourceService.received = -1
                SpatialResourceService.total = -1
                root.depthPath = resultPath
                if (root.activationPending) root.presentationWatchdog.restart()
                SpatialResourceService.inspect()
                console.log("[SpatialWallpaper] depth ready for " + sourcePath)
            } else if (root.enabled || root.preparationRequested)
                root.requestDelay.restart()
        }
        function onFailed(sourcePath, code, message, retryable) {
            if (!root.requestInFlight || sourcePath !== root.requestedPath)
                return
            root.requestInFlight = false
            console.warn("[SpatialWallpaper] " + code + ": " + message
                + " retryable=" + retryable)
            if ((root.enabled || root.preparationRequested)
                    && sourcePath === root.imagePath) {
                root.errorMessage = message
                root.preparationRequested = false
                root.activationPending = false
                if (root.enabled && retryable
                        && code !== "depth-generation-failed") {
                    root.retryCount++
                    root.retryTimer.interval = Math.min(30000,
                        2000 * Math.pow(2, Math.min(root.retryCount - 1, 4)))
                    root.retryTimer.restart()
                }
            } else if (root.enabled || root.preparationRequested)
                root.requestDelay.restart()
        }
    }

    Component.onCompleted: refreshWallpaper()
}
