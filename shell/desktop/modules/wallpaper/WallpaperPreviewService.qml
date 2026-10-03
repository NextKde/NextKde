pragma Singleton
import QtQuick
import qs.desktop.modules.common
import "../../../Kos/Ui"
import "../../../Kos/Ui/foundation/WallpaperCatalog.js" as Catalog

// Preview owns a draft. Only Apply commits it to WallpaperService.
QtObject {
    id: service
    property bool active: false
    property bool pending: false
    property bool presented: false
    property string image: ""
    property string mode: "image"
    property var thumbnailCatalog: ({})
    property var imageCatalog: []
    property var colorCatalog: []
    property var selectedImages: []
    readonly property var images: mode === "theme" ? Catalog.themes
        .map(item => "theme:" + item.id)
        .concat(ThemePackService.packs
            .map(item => "theme:" + item.id)
            .filter(id => !Catalog.theme(id.slice(6))))
        : mode === "color" ? colorCatalog : imageCatalog
    property int intervalMinutes: 15
    property string errorMessage: ""
    property int direction: 1
    property real transitionSeed: Math.random()
    property bool slideshowPlaying: false
    property var readyOutputs: []
    readonly property bool available: ScreenLifecycle.usableScreens.length > 0

    function parse(raw) {
        try {
            let value = JSON.parse(raw)
            if (typeof value === "string") value = JSON.parse(value)
            return value
        } catch (_) { return null }
    }
    function paths(values) {
        if (!Array.isArray(values)) return []
        return values.map(value => WallpaperService.localPath(value))
            .filter((value, index, all) => value && all.indexOf(value) === index).slice(0, 2000)
    }
    function setThumbnails(raw) {
        const values = typeof raw === "string" ? parse(raw) : raw
        const next = {}
        if (values && typeof values === "object" && !Array.isArray(values)) {
            for (const path of imageCatalog) {
                const cached = WallpaperService.localPath(values[path])
                if (cached) next[path] = cached
            }
        }
        thumbnailCatalog = next
    }
    function thumbnailFor(path) {
        return thumbnailCatalog[path] || ""
    }
    function begin(path, rawImages) {
        return beginSession(path, JSON.stringify({ images: parse(rawImages), colors: [],
            mode: path.indexOf("/wallpaper-colors/") >= 0 ? "color" : "image",
            selectedImages: WallpaperService.slideshowImages,
            intervalMinutes: WallpaperService.slideshowIntervalMinutes }))
    }
    function beginSession(path, rawSession) {
        if (!available) {
            errorMessage = "当前没有可用的显示器"
            return false
        }
        if (pending || WallpaperService.takeoverPending) return false
        const session = parse(rawSession)
        const isTheme = session && session.mode === "theme"
        const local = isTheme && String(path).startsWith("theme:")
            && (Catalog.theme(String(path).slice(6)) || ThemePackService.has(String(path).slice(6)))
            ? String(path) : isTheme ? "" : WallpaperService.localPath(path)
        if (!session || !local) return false
        imageCatalog = paths(session.images)
        colorCatalog = paths(session.colors)
        setThumbnails(session.thumbnails)
        selectedImages = paths(session.selectedImages)
        mode = ["image", "color", "slideshow", "theme"].indexOf(session.mode) >= 0 ? session.mode : "image"
        if (mode === "color" && colorCatalog.indexOf(local) < 0)
            colorCatalog = [local].concat(colorCatalog)
        else if (mode !== "color" && mode !== "theme" && imageCatalog.indexOf(local) < 0)
            imageCatalog = [local].concat(imageCatalog)
        selectedImages = selectedImages.filter(path => imageCatalog.indexOf(path) >= 0)
        intervalMinutes = [1, 5, 15, 30, 60, 1440].indexOf(Number(session.intervalMinutes)) >= 0
            ? Number(session.intervalMinutes) : 15
        errorMessage = ""
        presented = false
        active = true
        showImage(mode === "slideshow" && selectedImages.length ? selectedImages[0] : local)
        slideshowPlaying = mode === "slideshow" && selectedImages.length >= 2
        return true
    }
    function chooseColor(path) {
        const local = WallpaperService.localPath(path)
        if (!active || !local) return false
        if (colorCatalog.indexOf(local) < 0) colorCatalog = [local].concat(colorCatalog)
        mode = "color"
        slideshowPlaying = false
        errorMessage = ""
        showImage(local)
        return true
    }
    function showImage(path) {
        if (!path || (path === image && presented && !pending)) return
        SpatialWallpaperService.cancelPreparation()
        pending = true
        transitionSeed = Math.random()
        readyOutputs = []
        image = path
        loadingWatchdog.restart()
    }
    function imageReady(path, outputName) {
        if (!active || (mode === "theme" ? String(path) : WallpaperService.localPath(path)) !== image) return
        if (outputName && readyOutputs.indexOf(outputName) < 0)
            readyOutputs = readyOutputs.concat([outputName])
        const screens = ScreenLifecycle.usableScreens
        if (!screens.length || !screens.every(screen => readyOutputs.indexOf(screen.name) >= 0)) return
        loadingWatchdog.stop()
        pending = false
        presented = true
    }
    function select(index) {
        if (!active || !images.length) return
        const target = (index + images.length) % images.length
        if (mode === "slideshow") {
            toggleSelected(images[target])
            return
        }
        if (images[target] === image) return
        direction = target < images.indexOf(image) ? -1 : 1
        showImage(images[target])
    }
    function toggleSelected(path) {
        if (mode !== "slideshow") return
        selectedImages = selectedImages.indexOf(path) >= 0
            ? selectedImages.filter(value => value !== path) : selectedImages.concat([path])
        if (selectedImages.length && selectedImages.indexOf(image) < 0) showImage(selectedImages[0])
        if (selectedImages.length < 2) slideshowPlaying = false
    }
    function selectAll() {
        if (mode !== "slideshow") return
        selectedImages = imageCatalog.slice()
        if (selectedImages.length && selectedImages.indexOf(image) < 0) showImage(selectedImages[0])
    }
    function toggleSlideshow() {
        if (mode !== "slideshow" || selectedImages.length < 2 || pending) return
        slideshowPlaying = !slideshowPlaying
        if (slideshowPlaying) move(1)
    }
    function setMode(value) {
        if (["image", "color", "slideshow", "theme"].indexOf(value) < 0) return
        SpatialWallpaperService.cancelPreparation()
        mode = value
        errorMessage = ""
        slideshowPlaying = value === "slideshow" && selectedImages.length >= 2
        const candidates = value === "slideshow" && selectedImages.length ? selectedImages : images
        if (candidates.length && candidates.indexOf(image) < 0) showImage(candidates[0])
    }
    function move(delta) {
        const playlist = mode === "slideshow" ? selectedImages : images
        if (!playlist.length) return
        direction = delta < 0 ? -1 : 1
        showImage(playlist[(playlist.indexOf(image) + delta + playlist.length) % playlist.length])
    }
    function finish(keep) {
        if (!active || (keep && pending)) return
        const keepSpatial = keep && mode === "image" && SpatialWallpaperService.previewEnabled
        if (keep) {
            if (mode === "theme") {
                if (!WallpaperService.chooseTheme(image.slice(6))) return
            } else if (mode === "slideshow") {
                if (selectedImages.length < 2) {
                    errorMessage = "请选择至少两张图片"
                    return
                }
                if (!WallpaperService.setSlideshow(true, intervalMinutes, JSON.stringify(selectedImages), "")) return
                AppearanceConfigService.updateSpatialWallpaperEnabled(false)
            } else {
                if (!WallpaperService.chooseImage(image, true)) return
                if (image.indexOf("/wallpaper-colors/") >= 0)
                    AppearanceConfigService.updateSpatialWallpaperEnabled(false)
            }
        }
        if (keepSpatial) {
            // Commit the setting before leaving the draft; keep resident assets.
            AppearanceConfigService.updateSpatialWallpaperEnabled(true)
            active = false
            SpatialWallpaperService.previewEnabled = false
        } else {
            SpatialWallpaperService.cancelPreparation()
            if (keep) AppearanceConfigService.updateSpatialWallpaperEnabled(false)
            active = false
        }
        pending = false
        slideshowPlaying = false
        loadingWatchdog.stop()
        presented = false
    }
    function imageFailed(path) {
        if (!active || (mode === "theme" ? String(path) : WallpaperService.localPath(path)) !== image) return
        errorMessage = "这张图片无法显示，已恢复原壁纸。"
        finish(false)
    }
    property Timer loadingWatchdog: Timer {
        interval: 12000
        onTriggered: service.imageFailed(service.image)
    }
    property Timer slideshow: Timer {
        interval: 5000
        repeat: true
        running: service.active && service.presented && service.slideshowPlaying
            && service.selectedImages.length > 1 && !service.loadingWatchdog.running
        onTriggered: service.move(1)
    }
}
