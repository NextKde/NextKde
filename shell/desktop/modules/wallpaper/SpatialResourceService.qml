pragma Singleton
import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.platform

QtObject {
    id: root
    readonly property bool available: PlatformClient.supports("spatial.resources")
    readonly property bool enabled: AppearanceConfigService.spatialServiceEnabled
    property bool modelsReady: false
    property bool busy: false
    property bool checking: false
    property string stage: ""
    property string errorMessage: ""
    property real received: -1
    property real total: -1
    property real modelBytes: 0
    property real generatedBytes: 0
    property int epoch: 0
    property bool pollPending: false
    readonly property real progress: total > 0 ? Math.min(1, received / total) : -1
    signal initialized()

    function inspect() {
        if (!available || busy || checking) return
        checking = true
        const task = epoch
        PlatformClient.request("spatial.inspect", {}, response => {
            if (task !== epoch) return
            checking = false
            if (!response?.ok) { errorMessage = response?.error?.message || "资源检查失败"; return }
            errorMessage = ""
            modelsReady = !!response.result.modelsReady
            modelBytes = Number(response.result.modelBytes || 0)
            generatedBytes = Number(response.result.generatedBytes || 0)
            if (!modelsReady) AppearanceConfigService.updateSpatialServiceEnabled(false)
        })
    }
    function initialize() {
        if (!available) { errorMessage = "请更新平台服务以启用空间壁纸组件"; return false }
        if (busy || checking) return false
        busy = true
        errorMessage = ""
        stage = "正在检查初始化资源…"
        received = -1
        total = -1
        const task = ++epoch
        PlatformClient.request("spatial.initialize", {}, response => {
            if (task !== epoch) return
            busy = false
            if (!response?.ok) { errorMessage = response?.error?.message || "初始化失败"; return }
            stage = ""
            modelsReady = true
            modelBytes = Number(response.result.modelBytes || 0)
            generatedBytes = Number(response.result.generatedBytes || 0)
            AppearanceConfigService.updateSpatialServiceEnabled(true)
            initialized()
        })
        return true
    }
    function cancel() {
        ++epoch
        busy = false
        checking = false
        received = -1
        total = -1
        stage = ""
        PlatformClient.request("spatial.cancel", {}, () => {})
    }
    function disable() {
        SpatialWallpaperService.cancelPreparation()
        cancel()
        AppearanceConfigService.updateSpatialWallpaperEnabled(false)
        AppearanceConfigService.updateSpatialServiceEnabled(false)
    }
    function clear(kind) {
        if (["generated", "models", "all"].indexOf(kind) < 0 || !available) return
        SpatialWallpaperService.cancelPreparation()
        cancel()
        AppearanceConfigService.updateSpatialWallpaperEnabled(false)
        if (kind !== "generated") {
            AppearanceConfigService.updateSpatialServiceEnabled(false)
            modelsReady = false
        }
        busy = true
        errorMessage = ""
        stage = "正在清理资源…"
        const task = ++epoch
        PlatformClient.request("spatial.clear", {kind: kind}, response => {
            if (task !== epoch) return
            busy = false
            if (!response?.ok) errorMessage = response?.error?.message || "清理失败"
            inspect()
        })
    }
    function poll() {
        if (!available || pollPending) return
        pollPending = true
        const task = epoch
        PlatformClient.request("spatial.status", {}, response => {
            pollPending = false
            if (task !== epoch || !response?.ok || !response.result.busy
                    || !(root.busy || SpatialWallpaperService.preparationRequested || SpatialWallpaperService.requestInFlight)) return
            stage = String(response.result.stage || "正在准备…")
            received = Number(response.result.received ?? -1)
            total = Number(response.result.total ?? -1)
        })
    }
    property Timer polling: Timer {
        interval: 400
        repeat: true
        running: root.busy || SpatialWallpaperService.preparationRequested || SpatialWallpaperService.requestInFlight
        onTriggered: root.poll()
    }
    onAvailableChanged: if (available) inspect()
    Component.onCompleted: inspect()
}
