pragma Singleton

import QtQuick
import QtCore
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.platform
import "../../../Kos/Ui"
import "../../../Kos/Ui/foundation/WallpaperCatalog.js" as Catalog

// The original image and presentation preferences belong to Quickshell. The
// Plasma wallpaper is read only for first-run migration and fallback.
QtObject {
    id: service

    property Settings config: Settings {
        location: "file://" + Quickshell.stateDir + "/wallpaper.ini"
        category: "Wallpaper"
        property string image: ""
        property string mode: "image"
        property string themeId: "starfield"
        property bool themeEconomical: false
        property bool themeAnimated: false
        property real themeSpeed: 0.5
        property int themeParticleCount: 80
        property string fitMode: "crop"
        property string transition: "fade"
        property string transitionOptionsJson: '{"angle":45,"waveWidth":0.22,"waveHeight":0.08,"positionX":0.5,"positionY":0.5}'
        // macOS 式单一图集:引用条目 {type:"image"|"folder", path},不复制文件。
        property string libraryJson: "[]"
        property bool libraryMigrated: false
        property string customJson: "[]"
        property string recentJson: "[]"
        property bool takeoverEnabled: false
        property bool slideshowEnabled: false
        property int slideshowIntervalMinutes: 15
        property string slideshowFolder: ""
        // 轮播的运行时播放列表缓存,由设置程序按图集里的文件夹展开后推送;
        // 运行中文件失效由 reportImageFailed 剪除。
        property string slideshowJson: "[]"
    }

    readonly property string mode: config.mode === "theme" ? "theme" : "image"
    // Pack themes (marketplace) are valid ids too; the catalog only knows the
    // built-ins.
    readonly property string themeId: (Catalog.theme(config.themeId) || ThemePackService.has(config.themeId)) ? config.themeId : "starfield"
    readonly property bool themeEconomical: config.themeEconomical
    readonly property bool themeAnimated: config.themeAnimated
    readonly property real themeSpeed: Math.max(0.1, Math.min(1.5, config.themeSpeed))
    readonly property int themeParticleCount: Math.max(24, Math.min(160, config.themeParticleCount))
    readonly property url wallpaperUrl: config.image || WallpaperColorSource.wallpaperUrl
    readonly property bool takeoverEnabled: config.takeoverEnabled
    readonly property bool takeoverAvailable:
        PlatformClient.supports("wallpaper.plasma.proxy")
        && PlatformClient.supports("wallpaper.plasma.restore")
    readonly property string fitMode: config.fitMode
    readonly property string transition: config.transition
    readonly property var transitionOptions: {
        try {
            const value = JSON.parse(config.transitionOptionsJson)
            return value && typeof value === "object" ? value : ({})
        } catch (_) { return ({}) }
    }
    property real transitionSeed: Math.random()
    readonly property string slideshowFolder: config.slideshowFolder
    readonly property bool slideshowEnabled: config.slideshowEnabled
    readonly property int slideshowIntervalMinutes: config.slideshowIntervalMinutes
    readonly property var slideshowImages: {
        try {
            const images = JSON.parse(config.slideshowJson)
            return Array.isArray(images) ? images : []
        } catch (_) {
            return []
        }
    }
    property var readyOutputNames: []
    // Outputs whose transition for the current wallpaper has finished. The
    // proxy restyle rewrites the Plasma wallpaper for every screen (subprocess
    // plus file IO), so it must not run while the reveal animation still owns
    // the screen — see reportTransitionSettled().
    property var settledOutputNames: []
    property bool proxyPending: false
    property bool takeoverPending: false
    property bool restoreRequested: false
    property string appliedProxyKey: ""
    property string errorMessage: ""
    property int proxyRetryCount: 0
    // 旧版 recent/custom 列表的只读视图,仅供一次性迁移读取。
    function _parseJsonList(raw) {
        try {
            const value = JSON.parse(String(raw === undefined ? "[]" : raw))
            return Array.isArray(value) ? value : []
        } catch (_) {
            return []
        }
    }
    readonly property var library: {
        try {
            const entries = JSON.parse(config.libraryJson)
            return Array.isArray(entries) ? entries : []
        } catch (_) {
            return []
        }
    }

    function isLocalImage(value) {
        const path = String(value || "").trim()
        return path.startsWith("/") || path.startsWith("file://")
    }

    function localPath(value) {
        const path = String(value || "").trim()
        if (path.startsWith("/"))
            return path
        if (!path.startsWith("file://"))
            return ""
        try {
            const decoded = decodeURIComponent(path.slice(7))
            return decoded.startsWith("/") ? decoded : ""
        } catch (_) {
            return ""
        }
    }

    function chooseImage(value, userSelected) {
        const path = localPath(value)
        if (!path || takeoverPending)
            return false
        transitionSeed = Math.random()
        readyOutputNames = []
        settledOutputNames = []
        config.mode = "image"
        config.image = path
        if (userSelected)
            config.takeoverEnabled = true
        if (userSelected)
            config.slideshowEnabled = false
        config.sync()
        WallpaperColorSource.preferredWallpaperUrl = path
        return true
    }

    function chooseTheme(id) {
        if ((!Catalog.theme(id) && !ThemePackService.has(id)) || takeoverPending) return false
        SpatialWallpaperService.cancelPreparation()
        AppearanceConfigService.updateSpatialWallpaperEnabled(false)
        if (mode !== "theme" || themeId !== id) {
            readyOutputNames = []
            settledOutputNames = []
            appliedProxyKey = ""
        }
        if (!config.image) config.image = localPath(WallpaperColorSource.wallpaperUrl)
        config.themeId = id
        config.mode = "theme"
        config.slideshowEnabled = false
        config.takeoverEnabled = true
        config.sync()
        return true
    }
    function setThemeEconomical(value) {
        config.themeEconomical = !!value
        config.sync()
    }
    function setThemeMotion(animated, speed, count) {
        if (!Number.isFinite(speed) || !Number.isFinite(count)) return
        config.themeAnimated = !!animated
        config.themeSpeed = Math.max(0.1, Math.min(1.5, speed))
        config.themeParticleCount = Math.round(Math.max(24, Math.min(160, count)))
        config.sync()
    }
    function reportThemeReady(outputName, id) {
        if (mode !== "theme" || id !== themeId || !outputName) return
        if (readyOutputNames.indexOf(outputName) < 0) readyOutputNames = readyOutputNames.concat([outputName])
        if (settledOutputNames.indexOf(outputName) < 0) settledOutputNames = settledOutputNames.concat([outputName])
        applyPlasmaBackdropIfReady()
    }

    // 图集增删已迁移到 settings 端托管目录(~/.local/share/kos/gallery,
    // GNOME 模式);libraryJson 只作为旧数据残留,供一次性迁移读取,不再有
    // 写入方。

    function setTakeoverEnabled(enabled) {
        if (takeoverPending)
            return false
        if (!takeoverAvailable) {
            errorMessage = PlatformClient.capabilityProbeComplete
                ? "当前平台服务版本不支持壁纸接管"
                : "平台服务尚未准备好"
            return false
        }
        if (enabled) {
            config.takeoverEnabled = true
            config.sync()
            applyPlasmaBackdropIfReady()
            return true
        }
        const imagePath = localPath(config.image)
        if (!imagePath)
            return false
        takeoverPending = true
        restoreRequested = true
        if (!proxyPending)
            restorePlasmaImage()
        return true
    }

    function restorePlasmaImage() {
        if (!restoreRequested || proxyPending || !takeoverAvailable)
            return
        restoreRequested = false
        const imagePath = localPath(config.image)
        PlatformClient.request("wallpaper.plasma.restore", {
            imagePath: imagePath,
            screenCount: Math.max(1, ScreenLifecycle.usableScreens.length)
        }, function(response) {
            service.takeoverPending = false
            if (response?.ok) {
                config.takeoverEnabled = false
                config.sync()
                service.appliedProxyKey = ""
                service.errorMessage = ""
            } else {
                service.errorMessage = response?.error?.message
                    || "Plasma 壁纸恢复失败"
            }
        })
    }

    function reportImageReady(outputName, imageUrl) {
        if (mode === "theme" || String(imageUrl) !== wallpaperUrl.toString() || !outputName)
            return
        if (readyOutputNames.indexOf(outputName) < 0)
            readyOutputNames = readyOutputNames.concat([outputName])
        applyPlasmaBackdropIfReady()
    }

    function allOutputsReady() {
        const screens = ScreenLifecycle.usableScreens
        return screens.length > 0 && screens.every(screen =>
            screen && readyOutputNames.indexOf(screen.name) >= 0)
    }

    function allOutputsSettled() {
        const screens = ScreenLifecycle.usableScreens
        return screens.length > 0 && screens.every(screen =>
            screen && settledOutputNames.indexOf(screen.name) >= 0)
    }

    // Called by each wallpaper layer once its transition has finished, or
    // right away when the requested image was already on screen.
    function reportTransitionSettled(outputName, imageUrl) {
        if (mode === "theme" || String(imageUrl) !== wallpaperUrl.toString() || !outputName)
            return
        if (settledOutputNames.indexOf(outputName) < 0)
            settledOutputNames = settledOutputNames.concat([outputName])
        applyPlasmaBackdropIfReady()
    }

    function applyPlasmaBackdropIfReady() {
        // The restyle lands a variable time after a switch (palette polling
        // plus IPC), so without the settle gate it collides with the reveal
        // animation and drops a frame there. Fade/simple survive it; reveal
        // does not, which is what made the stutter look transition-specific.
        if (!takeoverEnabled || takeoverPending || !allOutputsReady()
                || !allOutputsSettled()
                || (mode !== "theme" && !WallpaperColorSource.ready) || proxyPending
                || !takeoverAvailable)
            return
        const color = mode === "theme" ? (Catalog.theme(themeId)?.accent || ThemePackService.accent(themeId))
            : WallpaperColorSource.primary.toString()
        const accent = color.length === 9 && color.startsWith("#")
            ? "#" + color.slice(3) : color
        const dark = mode === "theme" || WallpaperColorSource.darkMode
        const screens = ScreenLifecycle.usableScreens.length
        const key = (mode === "theme" ? "theme:" + themeId : wallpaperUrl.toString()) + ":" + accent + ":" + dark
            + ":" + screens
        if (key === appliedProxyKey)
            return
        proxyPending = true
        PlatformClient.request("wallpaper.plasma.proxy", {
            accent: accent,
            dark: dark,
            screenCount: screens
        }, function(response) {
            service.proxyPending = false
            if (response?.ok) {
                service.appliedProxyKey = key
                service.proxyRetryCount = 0
                service.errorMessage = ""
            } else {
                service.errorMessage = response?.error?.message
                    || "Plasma 纯色占位图设置失败"
                if (service.proxyRetryCount++ < 3)
                    retryProxy.restart()
            }
            if (service.restoreRequested)
                service.restorePlasmaImage()
            else if (response?.ok && service.takeoverEnabled)
                service.applyPlasmaBackdropIfReady()
        })
    }

    property Timer retryProxy: Timer {
        interval: 5000
        repeat: false
        onTriggered: service.applyPlasmaBackdropIfReady()
    }

    function setFitMode(value) {
        const mode = String(value)
        if (["crop", "fit", "stretch", "center"].indexOf(mode) < 0)
            return false
        config.fitMode = mode
        config.sync()
        return true
    }

    function setTransition(value) {
        const style = String(value)
        if (["none", "simple", "fade", "left", "right", "top", "bottom", "wipe", "wave", "grow", "center", "outer", "any", "random", "cinematic"].indexOf(style) < 0)
            return false
        config.transition = style
        config.sync()
        return true
    }

    function setTransitionOptions(raw) {
        let value
        try {
            value = JSON.parse(raw)
            if (typeof value === "string") value = JSON.parse(value)
        } catch (_) { return false }
        if (!value || typeof value !== "object" || Array.isArray(value)) return false
        const limits = { angle: [0, 360], waveWidth: [0.02, 1],
            waveHeight: [0, 0.4], positionX: [0, 1], positionY: [0, 1] }
        const next = Object.assign({}, transitionOptions)
        for (const key of Object.keys(limits)) {
            if (value[key] === undefined) continue
            const number = Number(value[key])
            if (!isFinite(number)) return false
            next[key] = Math.max(limits[key][0], Math.min(limits[key][1], number))
        }
        config.transitionOptionsJson = JSON.stringify(next)
        config.sync()
        return true
    }

    function setSlideshow(enabled, minutes, rawImages, folder) {
        const allowed = [1, 5, 15, 30, 60, 1440]
        const cadence = Number(minutes)
        if (allowed.indexOf(cadence) < 0)
            return false
        let images
        try {
            images = JSON.parse(String(rawImages))
            if (typeof images === "string") images = JSON.parse(images)
        } catch (_) {
            return false
        }
        if (!Array.isArray(images))
            return false
        const playlist = images.map(localPath).filter(path => path)
            .filter((path, index, items) => items.indexOf(path) === index)
            .slice(0, 2000)
        if (typeof folder === "string" && localPath(folder))
            config.slideshowFolder = localPath(folder)
        if (!enabled) {
            config.slideshowJson = JSON.stringify(playlist)
            config.slideshowIntervalMinutes = cadence
            config.slideshowEnabled = false
            config.sync()
            return true
        }
        if (playlist.length < 2)
            return false
        config.slideshowJson = JSON.stringify(playlist)
        config.slideshowIntervalMinutes = cadence
        readyOutputNames = []
        settledOutputNames = []
        config.mode = "image"
        config.slideshowEnabled = true
        config.takeoverEnabled = true
        config.sync()
        if (playlist.indexOf(localPath(wallpaperUrl)) < 0)
            chooseImage(playlist[0], false)
        return true
    }

    function advanceSlideshow() {
        const images = slideshowImages
        if (images.length < 2 || takeoverPending)
            return
        const current = localPath(wallpaperUrl)
        let index = images.indexOf(current)
        index = (index + 1) % images.length
        chooseImage(images[index], false)
    }

    // A requested wallpaper file failed to decode (deleted or unmounted since
    // it was chosen). Prune it everywhere it is remembered, then move on:
    // advance the slideshow to the next survivor, or fall back to the Plasma
    // wallpaper when nothing usable is left.
    function reportImageFailed(value) {
        const path = localPath(value)
        if (!path || path !== localPath(wallpaperUrl))
            return
        // 图集里的单图条目失效即剔除;文件夹条目保留(文件可能回来,
        // 展示侧有"图片不存在"占位),只影响轮播缓存。
        if (library.some(entry =>
                entry.type === "image" && localPath(entry.path) === path))
            config.libraryJson = JSON.stringify(library.filter(entry =>
                !(entry.type === "image" && localPath(entry.path) === path)))
        const playlist = slideshowImages.filter(item => item !== path)
        if (playlist.length !== slideshowImages.length) {
            if (playlist.length > 1 && slideshowEnabled) {
                config.slideshowJson = JSON.stringify(playlist)
            } else {
                config.slideshowEnabled = false
                config.slideshowJson = playlist.length > 1
                    ? JSON.stringify(playlist) : "[]"
            }
        }
        if (slideshowEnabled && slideshowImages.length > 1) {
            advanceSlideshow()
            return
        }
        if (config.image === path) {
            config.image = ""
            WallpaperColorSource.preferredWallpaperUrl = ""
        }
        config.sync()
    }

    property Timer slideshowTimer: Timer {
        interval: Math.max(1, service.slideshowIntervalMinutes) * 60000
        repeat: true
        running: service.slideshowEnabled && service.takeoverEnabled
            && !WallpaperPreviewService.active
            && service.slideshowImages.length > 1
        onTriggered: service.advanceSlideshow()
    }

    function migratePlasmaWallpaper() {
        if (mode === "theme" || config.image || !isLocalImage(WallpaperColorSource.wallpaperUrl))
            return
        chooseImage(WallpaperColorSource.wallpaperUrl)
    }

    property Connections plasmaMigration: Connections {
        target: WallpaperColorSource
        function onWallpaperUrlChanged() { service.migratePlasmaWallpaper() }
        function onPaletteChanged() { service.applyPlasmaBackdropIfReady() }
        function onDarkModeChanged() { service.applyPlasmaBackdropIfReady() }
    }

    property Connections screenChanges: Connections {
        target: ScreenLifecycle
        function onUsableScreensChanged() { service.applyPlasmaBackdropIfReady() }
    }

    property Connections platformCapabilities: Connections {
        target: PlatformClient
        function onCapabilitiesChanged() {
            if (service.takeoverAvailable)
                service.applyPlasmaBackdropIfReady()
        }
    }

    onWallpaperUrlChanged: {
        readyOutputNames = []
        settledOutputNames = []
        appliedProxyKey = ""
    }

    Component.onCompleted: {
        if (!config.libraryMigrated) {
            const merged = _parseJsonList(config.libraryJson).filter(entry =>
                entry && (entry.type === "image" || entry.type === "folder") && localPath(entry.path))
            for (const raw of _parseJsonList(config.customJson)
                    .concat(_parseJsonList(config.recentJson))) {
                const path = localPath(raw)
                if (path && merged.findIndex(entry =>
                        entry.type === "image" && entry.path === path) < 0
                        && merged.length < 200)
                    merged.push({ type: "image", path: path })
            }
            config.libraryJson = JSON.stringify(merged)
            config.libraryMigrated = true
        }
        if (config.image)
            WallpaperColorSource.preferredWallpaperUrl = config.image
        else
            migratePlasmaWallpaper()
    }
}
