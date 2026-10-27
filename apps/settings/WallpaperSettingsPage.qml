import "../../shared/qml/i18n"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as Platform
import "../../shared/qml/controls" as LiquidControls
import "../../shared/qml/foundation/WallpaperCatalog.js" as WallpaperCatalog
import "../../shared/qml/wallpapers" as ThemeVisuals

ColumnLayout {
    id: page
    spacing: 16

    property var bridge: null
    property var colors: null
    property string image: ""
    property string wallpaperMode: "image"
    property string previewMode: "image"
    property string themeId: "starfield"
    readonly property bool currentIsTheme: previewActive ? previewMode === "theme" : wallpaperMode === "theme"
    readonly property string displayedThemeId: currentIsTheme && previewActive ? previewImage.slice(6) : themeId
    // 当前主题若是主题包,取包内 preview.png 作为当前卡片缩略图。
    readonly property string displayedPackPreviewPath: currentIsTheme ? page.packPreviewPath(displayedThemeId) : ""
    readonly property bool themeBridgeCompatible: bridgeCompatible && typeof bridge.chooseWallpaperTheme === "function"

    property string fitMode: "crop"
    property string transition: "fade"
    property var selectedSlideshowImages: []
    property bool categoryInitialized: false
    property string previewImage: ""
    property var customColors: []
    property color selectedBaseColor: "#70A0F5"
    property real colorDepth: 0.5
    property var catalogImages: []
    // 托管图集(GNOME 模式):导入=复制进 ~/.local/share/kos/gallery,图集=
    // 枚举该目录,移除=文件进回收站。数据完全在 settings 本地,不经 shell。
    property var galleryImages: []
    property string slideshowFolder: ""
    property bool slideshowEnabled: false
    property int slideshowIntervalMinutes: 15
    property bool takeoverEnabled: false
    property bool takeoverAvailable: false
    property bool takeoverPending: false
    property string takeoverError: ""
    property bool spatialEnabled: false
    property bool spatialPrepared: false
    property bool spatialBusy: false
    property bool spatialPreparing: false
    property string spatialError: ""
    property bool modelsChecking: true
    property bool depthModelReady: false
    property bool foregroundModelReady: false
    property bool enableAfterPreparation: false
    property string errorText: ""
    // The category also determines whether gallery clicks apply or multi-select.
    property string galleryCategory: "images"
    // 画廊不内滚:默认平铺前 10 行,"展开全部"后才显示其余(高度自然生长,
    // 滚动交给外层页面)——双层滚动条交互差,这是根本解法。
    property var scrollViewport: null
    // The grid follows the outer page's scroll. Keep lightweight delegate
    // positions, but construct images only near that viewport.
    readonly property int firstVisibleGalleryIndex: {
        if (!scrollViewport) return 0
        const offset = scrollViewport.contentY
        const top = gallery.mapToItem(scrollViewport, 0, 0).y + offset * 0
        return Math.max(0, Math.floor(-top / gallery.cellHeight) - 1) * gridColumns
    }
    readonly property int visibleGalleryCount: scrollViewport
        ? (Math.ceil(scrollViewport.height / gallery.cellHeight) + 3) * gridColumns : galleryPreviewCount
    property bool galleryExpanded: false
    readonly property int galleryPreviewCount: galleryExpanded
        ? galleryItems.length : Math.min(galleryItems.length, 10 * gridColumns)
    readonly property bool galleryHasMore: galleryItems.length > 10 * gridColumns
    property bool previewActive: false
    property bool previewPending: false
    property bool previewAvailable: false
    property bool previewWasActive: false
    signal desktopPreviewFinished()

    readonly property bool bridgeCompatible: !!bridge
        && typeof bridge.wallpaperCatalog === "function"
        && typeof bridge.wallpaperSnapshot === "function"
        && typeof bridge.inspectWallpaperModels === "function"
        && typeof bridge.previewWallpaperImage === "function"
        && typeof bridge.chooseWallpaperImage === "function"
        && typeof bridge.wallpaperColorImage === "function"
        && typeof bridge.chooseWallpaperGradient === "function"
        && typeof bridge.previewWallpaperSession === "function"
        && typeof bridge.updateWallpaperSlideshow === "function"
        && typeof bridge.updateWallpaperSpatialEnabled === "function"
        && typeof bridge.prepareWallpaperSpatial === "function"
        && typeof bridge.galleryImages === "function"
        && typeof bridge.importGalleryImage === "function"
        && typeof bridge.importGalleryFolder === "function"
        && typeof bridge.deleteGalleryImage === "function"
        && typeof bridge.revealWallpaperImage === "function"
        && typeof bridge.chooseWallpaperColor === "function"
        && typeof bridge.updateWallpaperFitMode === "function"
        && typeof bridge.updateWallpaperTransition === "function"
        && typeof bridge.updateWallpaperTakeoverEnabled === "function"
    readonly property int gridColumns: width >= 580 ? 3 : 2
    readonly property bool colorWallpaper: image.indexOf("/wallpaper-colors/") >= 0
    readonly property var intervals: WallpaperCatalog.intervals.map(item =>
        Object.assign({}, item, { label: I18n.tr(item.label) }))
    readonly property var colorItems: {
        const items = WallpaperCatalog.colorSwatches.map(swatch => {
            const item = WallpaperCatalog.colorGradient(swatch.color, colorDepth)
            item.title = I18n.tr(swatch.title)
            return item
        }).concat(customColors).map(item => ({
            title: item.title, color: "", palette: item,
            path: bridgeCompatible ? bridge.wallpaperColorImage(item.start, item.end, item.angle) : "",
            managed: item.custom === true
        }))
        return items
    }
    readonly property var imageItems: buildImageItems()
    // 图像 = 我的图片(托管目录,mtime 降序=新导入置顶)在前、系统壁纸垫底;
    // 按路径去重,同路径算托管条目(可移除进回收站)。
    readonly property var galleryItems: galleryCategory === "themes" ? WallpaperCatalog.themes.map(item =>
        Object.assign({}, item, { label: I18n.tr(item.label), detail: I18n.tr(item.detail) })).concat(packItems)
        : galleryCategory === "colors" ? colorItems : imageItems
    // 已安装主题包(marketplace):bridge 本地扫描,内置在前、包在后;
    // 与内置同 id 的包不展示(内置优先)。
    readonly property var packItems: {
        if (!bridgeCompatible) return []
        const raw = typeof bridge.themePackCatalog === "function" ? bridge.themePackCatalog() : []
        // 过桥的列表可能不是真 JS 数组(历史坑),先 slice。
        const packs = Array.prototype.slice.call(raw)
        const builtin = {}
        for (const theme of WallpaperCatalog.themes)
            builtin[theme.id] = true
        return packs.filter(pack => pack && pack.id && !builtin[pack.id])
            .map(pack => ({
                id: pack.id, label: pack.name || pack.id,
                detail: pack.detail || "", previewPath: pack.previewPath || ""
            }))
    }
    function packPreviewPath(id) {
        const hit = packItems.find(item => item.id === id)
        return hit ? hit.previewPath : ""
    }
    function buildImageItems() {
        // 过桥的 QStringList（catalogImages/galleryImages）不是真 JS 数组（历史
        // 坑：嵌套列表过界后 Array.isArray 为假），不能直接 concat；先 slice。
        const system = Array.prototype.slice.call(catalogImages)
        const custom = Array.prototype.slice.call(galleryImages)
        const managed = {}
        for (const path of custom)
            managed[path] = true
        const paths = []
        for (const path of custom.concat(system))
            if (paths.indexOf(path) < 0)
                paths.push(path)
        return paths.map(path => ({
            title: displayName(path),
            subtitle: "",
            color: "", path: path,
            managed: managed[path] === true
        }))
    }
    onGalleryCategoryChanged: {
        galleryExpanded = false
        Qt.callLater(() => gallery.positionViewAtBeginning())
    }

    function beginPreview(path) {
        if (!bridgeCompatible || previewPending) return
        if (galleryCategory === "themes" || String(path).startsWith("theme:")) {
            if (!themeBridgeCompatible) { errorText = I18n.tr("Update the settings app to use theme wallpapers"); return }
            const id = String(path).startsWith("theme:") ? String(path).slice(6) : themeId
            if (!WallpaperCatalog.theme(id) && packItems.every(item => item.id !== id)) return
            bridge.previewWallpaperSession("theme:" + id, {
                images: imageItems.map(item => item.path), colors: colorItems.map(item => item.path),
                mode: "theme", selectedImages: selectedSlideshowImages, intervalMinutes: slideshowIntervalMinutes
            })
            return
        }
        if (!previewAvailable) {
            errorText = I18n.tr("No available displays; wallpaper preview cannot start.")
            return
        }
        const candidates = galleryCategory === "colors" ? colorItems : imageItems
        let initial = path
        if (galleryCategory === "slideshow" && selectedSlideshowImages.length)
            initial = selectedSlideshowImages[0]
        else if (!candidates.some(item => item.path === initial) && candidates.length)
            initial = candidates[0].path
        if (!initial) { errorText = I18n.tr("Add a wallpaper first"); return }
        errorText = ""
        bridge.previewWallpaperSession(initial, {
            thumbnails: previewThumbnails(),
            images: imageItems.map(item => item.path), colors: colorItems.map(item => item.path),
            mode: galleryCategory === "colors" ? "color" : galleryCategory === "slideshow" ? "slideshow" : "image",
            selectedImages: selectedSlideshowImages, intervalMinutes: slideshowIntervalMinutes
        })
    }

    function chooseCategory(index) {
        galleryCategory = ["images", "colors", "slideshow", "themes"][index]
        categoryInitialized = true
        if (galleryCategory === "slideshow")
            setSlideshow(selectedSlideshowImages.length >= 2, slideshowIntervalMinutes)
        else if (slideshowEnabled)
            setSlideshow(false, slideshowIntervalMinutes)
    }
    function toggleSlideshowImage(path) {
        selectedSlideshowImages = selectedSlideshowImages.indexOf(path) >= 0
            ? selectedSlideshowImages.filter(value => value !== path)
            : selectedSlideshowImages.concat([path])
        setSlideshow(selectedSlideshowImages.length >= 2, slideshowIntervalMinutes)
    }
    function selectAllImages() {
        selectedSlideshowImages = imageItems.map(item => item.path)
        setSlideshow(selectedSlideshowImages.length >= 2, slideshowIntervalMinutes)
    }
    function applyBaseColor(value, custom) {
        if (!bridgeCompatible) return
        customDialog.errorMessage = ""
        const hex = value.toString().toUpperCase()
        const item = WallpaperCatalog.colorGradient(hex, colorDepth)
        item.title = custom ? I18n.tr("Custom") : I18n.tr("Current color")
        const path = bridge.wallpaperColorImage(item.start, item.end, item.angle)
        if (!path) { customDialog.errorMessage = bridge.lastError || I18n.tr("Could not generate a color"); return }
        selectedBaseColor = value
        if (custom) {
            item.custom = true
            if (!customColors.some(value => value.start === item.start && value.end === item.end && value.angle === item.angle))
                customColors = customColors.concat([item])
            saveCustomColors()
        }
        galleryCategory = "colors"
        if (previewActive) beginPreview(path)
        else bridge.chooseWallpaperGradient(item.start, item.end, item.angle)
    }
    function saveCustomColors() {
        if (bridge && typeof bridge.saveWallpaperCustomColors === "function")
            bridge.saveWallpaperCustomColors(JSON.stringify(customColors))
    }
    function removeCustomColor(path) {
        customColors = customColors.filter(item =>
            bridge.wallpaperColorImage(item.start, item.end, item.angle) !== path)
        saveCustomColors()
    }
    function applyColorItem(item) {
        selectedBaseColor = item.base || item.start
        if (previewActive) beginPreview(bridge.wallpaperColorImage(item.start, item.end, item.angle))
        else bridge.chooseWallpaperGradient(item.start, item.end, item.angle)
    }
    function choosePresetColor(index) {
        applyBaseColor(WallpaperCatalog.colorSwatches[index].color, false)
    }
    function applyCustomColor() {
        applyBaseColor(customDialog.selectedColor, true)
        customDialog.close()
    }

    function displayName(path) {
        const value = String(path || "")
        const packageMarker = "/contents/images/"
        const packageIndex = value.indexOf(packageMarker)
        if (packageIndex > 0)
            return value.slice(0, packageIndex).split("/").pop()
        const name = value.split("/").pop().replace(/\.[^.]+$/, "")
        return name || I18n.tr("No wallpaper selected")
    }

    function isSwatchSelected(hex) {
        return colorWallpaper && image.toLowerCase().endsWith(
            "/" + hex.slice(1).toLowerCase() + ".png")
    }

    function parseImages(raw) {
        try {
            const parsed = JSON.parse(String(raw || "[]"))
            return Array.isArray(parsed) ? parsed : []
        } catch (_) {
            return []
        }
    }

    // 快照/推送路径可能已失效(文件被删、挂载点卸载),一律先过存在性过滤。
    function filterExisting(paths) {
        // 托管图集路径天然存在;保留占位渲染兜底,这里不再做存在性过滤。
        return paths
    }

    // 磁盘缩略图缓存(方案 B):命中返回缓存文件 URL(零解码),未命中返回
    // 空、瓦片退回原图,同时 C++ 在线程池后台生成,完成发
    // wallpaperThumbnailChanged → thumbRevision++ → 绑定重求值后命中。
    // void thumbRevision 是制造依赖,让后台完成能刷新本绑定。
    property int thumbRevision: 0
    function thumbnailFor(path, width, height, radius) {
        void thumbRevision
        radius = radius || 0
        if (!bridgeCompatible || typeof bridge.wallpaperThumbnail !== "function")
            return ""
        if (!path || !path.startsWith("/"))
            return ""
        return bridge.wallpaperThumbnail(path, width, height, radius)
    }
    function previewThumbnails() {
        const result = {}
        // 与画廊瓦片同尺寸、同圆角,预览列表直出即圆角且四角位置正确。
        const width = Math.ceil(Math.max(1, gallery.cellWidth - 12) * Screen.devicePixelRatio)
        const height = Math.ceil(116 * Screen.devicePixelRatio)
        const radius = Math.ceil(14 * Screen.devicePixelRatio)
        for (const item of imageItems.slice(0, 2000)) {
            const cached = bridgeCompatible && typeof bridge.wallpaperThumbnail === "function"
                ? bridge.wallpaperThumbnail(item.path, width, height, radius, false) : ""
            if (cached) result[item.path] = cached
        }
        return result
    }

    Connections {
        target: bridge
        ignoreUnknownSignals: true
        // 生成是逐张完成的,首开会连发几十次;直接递增 revision 会让全部
        // 可见瓦片跟着逐张重求值+切图,和滚动抢主线程。合并成 300ms 一拍。
        function onWallpaperThumbnailChanged() { thumbCatchup.restart() }
    }
    Timer {
        id: thumbCatchup
        interval: 300
        onTriggered: {
            page.thumbRevision++
            if ((page.previewActive || page.previewPending)
                    && typeof page.bridge.updateWallpaperPreviewThumbnails === "function")
                page.bridge.updateWallpaperPreviewThumbnails(page.previewThumbnails())
        }
    }

    // 托管图集枚举:只在目录内容变化时重新赋值(列表没变就保持原数组身份),
    // 模型不重置 → 瓦片不重建——快照周期刷新不再引发画廊 churn。
    function refreshGallery() {
        const list = bridgeCompatible ? bridge.galleryImages() : []
        if (list.join("\n") === galleryImages.join("\n"))
            return
        galleryImages = list
    }
    onVisibleChanged: if (visible) refreshGallery()

    // 导入/移除都是同步本地操作,完成后手动刷新一次枚举。
    function importGallery(paths) {
        if (!bridgeCompatible || !paths || !paths.length)
            return
        let imported = 0
        for (const urlOrPath of paths) {
            if (String(bridge.importGalleryImage(urlOrPath)) !== "")
                ++imported
        }
        if (imported > 0)
            refreshGallery()
    }
    function importGalleryFromFolder(folder) {
        if (!bridgeCompatible)
            return
        // -2 = an import is already running (its completion refreshes too);
        // -1 = the folder does not exist (errorOccurred already reported).
        const started = bridge.importGalleryFolder(folder)
        if (started === 0 || started === -2) {
            importingFolder = true
            errorText = ""
        } else {
            refreshGallery()
        }
    }

    // Folder copies hash, decode and write off the GUI thread; refresh on
    // completion instead of right after the call.
    property bool importingFolder: false
    Connections {
        target: page.bridge && page.bridge.galleryImportFinished !== undefined ? page.bridge : null
        function onGalleryImportFinished(imported) {
            page.importingFolder = false
            if (imported === 0)
                page.errorText = I18n.tr("No supported images in that folder.")
            page.refreshGallery()
        }
        function onGalleryImportProgress(imported) {
            if (imported % 10 === 0)
                page.refreshGallery()
        }
    }
    function removeGalleryImage(path) {
        if (!bridgeCompatible)
            return
        if (bridge.deleteGalleryImage(path))
            errorText = ""
        refreshGallery()
    }

    function applyState(state) {
        if (!state || state.fitMode === undefined)
            return
        previewActive = !!state.previewActive
        previewPending = !!state.previewPending
        previewAvailable = !!state.previewAvailable
        if (previewWasActive && !previewActive && !previewPending)
            desktopPreviewFinished()
        previewWasActive = previewActive || previewPending
        if (state.previewError)
            errorText = state.previewError
        wallpaperMode = String(state.wallpaperMode || "image")
        previewMode = String(state.previewMode || "image")
        themeId = String(state.themeId || "starfield")
        image = String(state.image || "")
        fitMode = String(state.fitMode || "crop")
        transition = String(state.transition || "fade")
        previewImage = String(state.previewImage || "")
        selectedSlideshowImages = parseImages(state.slideshowImages)
        if (!categoryInitialized) {
            galleryCategory = wallpaperMode === "theme" ? "themes" : state.slideshowEnabled ? "slideshow"
                : colorWallpaper ? "colors" : "images"
            categoryInitialized = true
        }
        if (previewActive) {
            galleryCategory = state.previewMode === "theme" ? "themes" : state.previewMode === "color" ? "colors"
                : state.previewMode === "slideshow" ? "slideshow" : "images"
            selectedSlideshowImages = parseImages(state.previewSelection)
        }
        slideshowEnabled = !!state.slideshowEnabled
        slideshowIntervalMinutes = Number(previewActive ? state.previewInterval || 15 : state.slideshowIntervalMinutes || 15)
        slideshowFolder = String(state.slideshowFolder || "")
        takeoverEnabled = !!state.takeoverEnabled
        takeoverAvailable = !!state.takeoverAvailable
        takeoverPending = !!state.takeoverPending
        takeoverError = String(state.takeoverError || "")
        spatialEnabled = !!state.spatialEnabled
        spatialPrepared = !!state.spatialPrepared
        spatialBusy = !!state.spatialBusy
        spatialPreparing = !!state.spatialPreparing
        spatialError = String(state.spatialError || "")
        if (enableAfterPreparation && spatialError) {
            enableAfterPreparation = false
            errorText = spatialError
        } else if (enableAfterPreparation && spatialPrepared && !modelsChecking) {
            bridge.inspectWallpaperModels()
            modelsChecking = true
        }
    }

    function beginSpatialPreparation() {
        if (!bridgeCompatible || spatialPreparing || spatialBusy)
            return
        enableAfterPreparation = false
        errorText = ""
        bridge.prepareWallpaperSpatial()
    }

    function requestSpatialEnable() {
        if (!bridgeCompatible || colorWallpaper || spatialPreparing || spatialBusy) return
        errorText = ""
        bridge.prepareWallpaperSpatial()
    }

    function setSlideshow(enabled, interval) {
        if (!bridgeCompatible) {
            errorText = I18n.tr("The settings app is too old; please update before using wallpaper features.")
            return
        }
        const playlist = slideshowPlaylist()
        if (enabled && playlist.length < 2) {
            errorText = I18n.tr("Select at least two images to start a slideshow.")
            return
        }
        errorText = ""
        bridge.updateWallpaperSlideshow(enabled, interval, playlist,
            "")
    }

    function slideshowPlaylist() {
        return filterExisting(selectedSlideshowImages)
    }

    Component.onCompleted: {
        if (bridge && typeof bridge.wallpaperCustomColors === "function")
            customColors = parseImages(bridge.wallpaperCustomColors())
        refreshGallery()
        if (bridgeCompatible) {
            catalogImages = bridge.wallpaperCatalog()
            bridge.wallpaperSnapshot()
            bridge.inspectWallpaperModels()
        } else if (bridge) {
            modelsChecking = false
            errorText = I18n.tr("The settings app and wallpaper interface versions do not match; please update the settings app.")
        }
    }

    Connections {
        target: page.bridge
        enabled: page.bridgeCompatible
        ignoreUnknownSignals: true
        function onWallpaperSnapshotChanged(state) {
            page.applyState(state)
            if (page.bridge.lastError)
                page.errorText = page.bridge.lastError
        }
        function onWallpaperModelsChecked(depthReady, foregroundReady) {
            page.modelsChecking = false
            page.depthModelReady = depthReady
            page.foregroundModelReady = foregroundReady
            if (page.enableAfterPreparation && page.spatialPrepared && depthReady) {
                page.enableAfterPreparation = false
                page.bridge.updateWallpaperSpatialEnabled(true)
            } else if (page.enableAfterPreparation && page.spatialPrepared
                    && !depthReady) {
                page.enableAfterPreparation = false
                page.errorText = I18n.tr("Depth model verification failed; spatial wallpaper is off.")
            }
        }
    }

    Timer {
        interval: page.previewActive || page.previewPending ? 700 : 1800
        repeat: true
        running: page.slideshowEnabled || page.previewActive || page.previewPending || page.enableAfterPreparation || page.spatialBusy
            || page.spatialPreparing || page.takeoverPending
        onTriggered: if (page.bridgeCompatible) page.bridge.wallpaperSnapshot()
    }

    Platform.FileDialog {
        id: fileDialog
        title: I18n.tr("Choose wallpaper")
        fileMode: Platform.FileDialog.OpenFiles
        nameFilters: [I18n.tr("Images (*.jpg *.jpeg *.png *.webp *.bmp *.avif)")]
        // 导入=复制进托管图集;点瓦片才是应用。完成后本地刷新枚举。
        onAccepted: if (page.bridgeCompatible) {
            page.galleryCategory = "images"
            page.importGallery(selectedFiles)
        }
    }

    Platform.FolderDialog {
        id: folderDialog
        title: I18n.tr("Choose wallpaper folder")
        // 导入文件夹 = 把其中图片复制进托管图集(一次性快照,之后文件夹新增
        // 不会自动出现,需要重新导入)。
        onAccepted: {
            if (!page.bridgeCompatible)
                return
            page.galleryCategory = "images"
            page.importGalleryFromFolder(selectedFolder.toString())
        }
    }

    WallpaperColorPicker {
        id: customDialog
        colors: page.colors
        eyedropperAvailable: !!page.bridge && typeof page.bridge.pickWallpaperColor === "function"
        onColorApplied: function(value) {
            page.applyBaseColor(value, true)
            if (!customDialog.errorMessage) customDialog.close()
        }
        onEyedropperRequested: {
            if (page.bridge && typeof page.bridge.pickWallpaperColor === "function")
                { close(); page.bridge.pickWallpaperColor() }
        }
    }
    Connections {
        target: page.bridge
        ignoreUnknownSignals: true
        function onWallpaperColorPicked(value) { customDialog.selectedColor = value; customDialog.open() }
        function onWallpaperColorPickFailed(message) { customDialog.errorMessage = message; customDialog.open() }
    }

    Dialog {
        id: modelDialog
        modal: true
        width: 380
        title: I18n.tr("Prepare spatial wallpaper model")
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: page.beginSpatialPreparation()
        contentItem: Item {
            implicitWidth: 330
            implicitHeight: 70
            Text {
                anchors.fill: parent
                wrapMode: Text.Wrap
                color: page.colors.primaryText
                text: I18n.tr("Downloads and verifies the local depth model first, then generates assets for the current wallpaper. Spatial wallpaper turns on automatically afterwards.")
            }
        }
    }

    Rectangle {
        id: currentWallpaperCard
        objectName: "currentWallpaperPreviewCard"
        Layout.fillWidth: true
        implicitHeight: 88
        radius: 18
        color: page.colors.card
        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14
            Item {
                Layout.preferredWidth: 88
                Layout.preferredHeight: 56
                WallpaperThumbnail {
                    anchors.fill: parent
                    visible: !page.currentIsTheme
                    imagePath: page.currentIsTheme ? "" : page.previewActive ? page.previewImage : page.image
                    surroundingColor: page.colors.card
                }
                Loader {
                    anchors.fill: parent
                    active: page.currentIsTheme
                    // 包主题用包内 preview.png;内置主题用共享静态图。
                    sourceComponent: page.displayedPackPreviewPath ? packThumb : builtinThumb
                }
                Component {
                    id: packThumb
                    Image {
                        source: page.displayedPackPreviewPath
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                    }
                }
                Component {
                    id: builtinThumb
                    ThemeVisuals.ThemeWallpaperThumbnail { themeId: page.displayedThemeId }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Text {
                    Layout.fillWidth: true
                    text: page.currentIsTheme
                        ? ((WallpaperCatalog.theme(page.displayedThemeId)
                            ? I18n.tr(WallpaperCatalog.theme(page.displayedThemeId).label) : "")
                            || page.packItems.find(item => item.id === page.displayedThemeId)?.label
                            || I18n.tr("Theme wallpaper"))
                        : page.displayName(page.image)
                    color: page.colors.primaryText
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
                Text {
                    text: !page.bridgeCompatible
                        ? I18n.tr("Settings app version mismatch")
                        : !page.previewAvailable
                            ? I18n.tr("Desktop preview is not supported in this environment yet")
                            : I18n.tr("Enters a fullscreen simulated desktop; the wallpaper changes only after Apply")
                    color: page.colors.secondaryText
                    font.pixelSize: 12
                }
            }
            Text {
                objectName: "currentWallpaperPreviewLabel"
                text: page.previewPending ? I18n.tr("Loading…")
                    : page.previewAvailable && page.bridgeCompatible ? I18n.tr("Desktop preview  ›") : I18n.tr("Unavailable")
                color: page.previewAvailable && page.bridgeCompatible
                    ? page.colors.accent : page.colors.secondaryText
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
        MouseArea {
            id: currentWallpaperMouse
            objectName: "currentWallpaperPreviewAction"
            anchors.fill: parent
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: (!!page.image || page.currentIsTheme) && page.bridgeCompatible
                && page.previewAvailable && !page.previewPending
            onClicked: page.beginPreview(page.currentIsTheme ? "theme:" + page.displayedThemeId : page.image)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: page.galleryCategory !== "themes"
        implicitHeight: visible ? optionsColumn.implicitHeight : 0
        radius: 18
        color: page.colors.card
        Column {
            id: optionsColumn
            width: parent.width
            WallpaperSettingsRow {
                width: parent.width
                colors: page.colors
                label: I18n.tr("Fill mode")
                separator: true
                LiquidControls.LiquidSelect {
                    objectName: "wallpaperFitMenu"
                    accentColor: page.colors.accent
                    model: [I18n.tr("Fill the screen"), I18n.tr("Show in full"), I18n.tr("Stretch"), I18n.tr("Centered")]
                    currentIndex: Math.max(0, ["crop", "fit", "stretch", "center"].indexOf(page.fitMode))
                    onActivated: function(index) {
                        if (page.bridgeCompatible)
                            page.bridge.updateWallpaperFitMode(
                                ["crop", "fit", "stretch", "center"][index])
                    }
                }
            }
            WallpaperSettingsRow {
                width: parent.width
                colors: page.colors
                label: I18n.tr("Switch effect")
                separator: true
                LiquidControls.LiquidSelect {
                    objectName: "wallpaperTransitionMenu"
                    accentColor: page.colors.accent
                    model: WallpaperCatalog.transitions.map(item =>
                        Object.assign({}, item, { label: I18n.tr(item.label) }))
                    textRole: "label"
                    currentIndex: Math.max(0, WallpaperCatalog.transitions.map(item => item.id).indexOf(page.transition))
                    onActivated: function(index) {
                        if (page.bridgeCompatible)
                            page.bridge.updateWallpaperTransition(
                                WallpaperCatalog.transitions[index].id)
                    }
                }
            }
            WallpaperSettingsRow {
                width: parent.width
                colors: page.colors
                label: I18n.tr("KOS draws the wallpaper")
                // 底下还有一行小字注释，这行收矮一点，注释就不显得悬空。
                height: 46
                LiquidControls.LiquidGlassSwitch {
                    id: takeoverToggle
                    enabled: page.takeoverAvailable && !page.takeoverPending
                    checked: page.takeoverEnabled
                    accentColor: page.colors.accent
                    trackColor: page.colors.divider
                    onToggled: function(checked) {
                        if (page.bridgeCompatible)
                            page.bridge.updateWallpaperTakeoverEnabled(checked)
                        takeoverToggle.checked = Qt.binding(() => page.takeoverEnabled)
                    }
                }
            }
            // 接管说明收进卡片内，贴在该开关行的下面作小字注释。
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 16
                text: page.takeoverAvailable
                    ? I18n.tr("Restores the Plasma wallpaper when KOS wallpaper is turned off. Enabling spatial wallpaper pauses auto-switching.")
                    : I18n.tr("The current platform service version does not support wallpaper takeover; please update first.")
                color: page.colors.tertiaryText
                font.pixelSize: 10
                wrapMode: Text.Wrap
                bottomPadding: 10
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        visible: page.spatialBusy || page.spatialPreparing || page.modelsChecking
        text: page.modelsChecking ? I18n.tr("Checking the spatial wallpaper model…") : I18n.tr("Preparing spatial wallpaper; cancel from the preview or Extensions and services…")
        color: page.colors.secondaryText
        font.pixelSize: 12
    }

    // 原「图片库 / N 张 / 分类菜单 / 添加…」标题行已删；分类改由下面图集卡片
    // 内的「壁纸类型」行承担（下拉：图像 / 纯色），「添加…」入口一并移除。

    Rectangle {
        id: galleryCard
        Layout.fillWidth: true
        // 高度随内容生长(不再固定高度内滚):前 10 行 + 展开按钮,展开后
        // 全量行数;滚动由外层 pageScroll 承担,交互上只有一层滚动。
        Layout.preferredHeight: typeRow.height + importRow.height + slideshowRow.height + themeOptions.height + 12
            + Math.ceil(page.galleryPreviewCount / page.gridColumns) * (page.galleryCategory === "themes" ? 184 : 128)
            + (page.galleryHasMore ? expandRow.height + 10 : 0)
        visible: true
        radius: 18
        color: page.colors.card

        Column {
            anchors.fill: parent

            WallpaperSettingsRow {
                id: typeRow
                width: parent.width
                colors: page.colors
                label: I18n.tr("Wallpaper type")
                separator: true
                LiquidControls.LiquidSelect {
                    objectName: "wallpaperTypeMenu"
                    accentColor: page.colors.accent
                    model: [I18n.tr("Image"), I18n.tr("Colors"), I18n.tr("Slideshow"), I18n.tr("Theme wallpaper")]
                    currentIndex: ["images", "colors", "slideshow", "themes"].indexOf(page.galleryCategory)
                    onActivated: function(index) {
                        page.chooseCategory(index)
                    }
                }
            }

            WallpaperSettingsRow {
                id: slideshowRow
                objectName: "slideshowOptions"
                visible: page.galleryCategory === "slideshow"
                height: visible ? implicitHeight : 0
                width: parent.width
                colors: page.colors
                label: I18n.tr("Switch interval")
                separator: true
                LiquidControls.LiquidSelect {
                    objectName: "frequencyMenu"
                    accentColor: page.colors.accent
                    model: page.intervals
                    textRole: "label"
                    currentIndex: Math.max(0, page.intervals.map(item => item.minutes).indexOf(page.slideshowIntervalMinutes))
                    onActivated: function(index) {
                        page.slideshowIntervalMinutes = page.intervals[index].minutes
                        page.setSlideshow(page.selectedSlideshowImages.length >= 2, page.slideshowIntervalMinutes)
                    }
                }
                WallpaperTextButton {
                    objectName: "slideshowSelectAll"
                    label: I18n.tr("Select all")
                    colors: page.colors
                    onClicked: page.selectAllImages()
                }
            }

            Text {
                id: themeOptions
                width: parent.width - 32
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.galleryCategory === "themes"
                height: visible ? contentHeight + 16 : 0
                text: I18n.tr("Plays automatically after 10 seconds without windows on the desktop and pauses when windows appear. The preview always plays.")
                color: page.colors.secondaryText
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // 导入入口独占一行：壁纸类型行之下、图像网格之上，右对齐。
            // 链接式文字（accent 色）而非按钮，表示可点击。
            Row {
                id: importRow
                visible: page.galleryCategory !== "themes"
                anchors.right: parent.right
                anchors.rightMargin: 12
                height: 42
                spacing: 14
                Text {
                    objectName: "addCustomColorButton"
                    visible: page.galleryCategory === "colors"
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Custom colors")
                    color: page.bridgeCompatible ? page.colors.accent : page.colors.tertiaryText
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    opacity: page.bridgeCompatible ? 1 : 0.6
                    MouseArea {
                        anchors.fill: parent
                        enabled: page.bridgeCompatible
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            customDialog.errorMessage = ""
                            customDialog.selectedColor = page.selectedBaseColor
                            customDialog.open()
                        }
                    }
                }
                Text {
                    objectName: "importImagesButton"
                    visible: page.galleryCategory !== "colors" && page.galleryCategory !== "themes"
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Import images")
                    color: page.bridgeCompatible
                        ? page.colors.accent : page.colors.tertiaryText
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    opacity: page.bridgeCompatible ? 1 : 0.6
                    MouseArea {
                        anchors.fill: parent
                        enabled: page.bridgeCompatible
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fileDialog.open()
                    }
                }
                Text {
                    objectName: "importFolderButton"
                    visible: page.galleryCategory !== "colors" && page.galleryCategory !== "themes"
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Import folder")
                    color: page.bridgeCompatible
                        ? page.colors.accent : page.colors.tertiaryText
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    opacity: page.bridgeCompatible ? 1 : 0.6
                    MouseArea {
                        anchors.fill: parent
                        enabled: page.bridgeCompatible
                        cursorShape: Qt.PointingHandCursor
                        onClicked: folderDialog.open()
                    }
                }
            }

            // 网格与上面内容之间的呼吸空间。
            Item { width: parent.width; height: 12 }

            GridView {
                id: gallery
                objectName: "wallpaperGallery"
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 8
                // 高度=全部内容,不做内部滚动;折叠时模型只给前 10 行。
                height: visible ? contentHeight : 0
                interactive: false
                cellWidth: Math.max(1, width / page.gridColumns)
                cellHeight: page.galleryCategory === "themes" ? 184 : 128
                model: page.galleryItems.slice(0, page.galleryPreviewCount)
                delegate: Loader {
                    required property int index
                    required property var modelData
                    active: index >= page.firstVisibleGalleryIndex
                        && index < page.firstVisibleGalleryIndex + page.visibleGalleryCount
                    width: gallery.cellWidth - 12
                    height: page.galleryCategory === "themes" ? 172 : 116
                    sourceComponent: page.galleryCategory === "themes" ? themeDelegate : imageDelegate
                    Component {
                        id: themeDelegate
                        ThemeWallpaperTile {
                            themeId: modelData.id
                            previewPath: modelData.previewPath || ""
                            title: modelData.label
                            detail: modelData.detail
                            accent: page.colors.accent
                            textColor: page.colors.primaryText
                            secondaryColor: page.colors.secondaryText
                            surroundingColor: page.colors.card
                            selected: page.currentIsTheme && page.displayedThemeId === modelData.id
                            onActivated: if (page.themeBridgeCompatible) page.bridge.chooseWallpaperTheme(modelData.id)
                            onPreviewRequested: page.beginPreview("theme:" + modelData.id)
                        }
                    }
                    Component {
                        id: imageDelegate
                        WallpaperGalleryTile {
                        id: galleryTile
                        imagePath: modelData.path
                        swatchColor: modelData.color
                        accent: page.colors.accent
                        surroundingColor: page.colors.card
                        // 托管图集条目都可移除(进回收站);系统壁纸/纯色/渐变没有。
                        removable: page.bridgeCompatible && modelData.managed === true
                        revealable: page.bridgeCompatible && !modelData.palette && !modelData.color
                            && modelData.path.length > 0
                        // 精确按显示尺寸生成(dpr 烘进缓存图):内容列已锁死
                        // 700px,瓦片尺寸恒定,不存在重排换键的问题;量化反而会
                        // 让 PreserveAspectCrop 裁掉/错位烘焙的圆角。
                        readonly property size thumbPx: Qt.size(
                            Math.ceil(galleryTile.width * Screen.devicePixelRatio),
                            Math.ceil(galleryTile.height * Screen.devicePixelRatio))
                        thumbSource: page.thumbnailFor(modelData.path,
                            thumbPx.width, thumbPx.height,
                            Math.ceil(14 * Screen.devicePixelRatio))
                        selected: page.galleryCategory === "slideshow"
                            ? page.selectedSlideshowImages.indexOf(modelData.path) >= 0
                            : (page.previewActive ? page.previewImage : page.image) === modelData.path
                        selectionMode: page.galleryCategory === "slideshow"
                        onActivated: {
                            if (!page.bridgeCompatible) return
                            if (page.galleryCategory === "slideshow") page.toggleSlideshowImage(modelData.path)
                            else if (modelData.palette) page.applyColorItem(modelData.palette)
                            else page.bridge.chooseWallpaperImage(modelData.path)
                        }
                        onRevealRequested: if (page.bridgeCompatible)
                            page.bridge.revealWallpaperImage(modelData.path)
                        onRemoveRequested: if (page.bridgeCompatible)
                            if (modelData.palette) page.removeCustomColor(modelData.path)
                            else page.removeGalleryImage(modelData.path)
                    }
                    }
                }
            }

            // 展开全部/收起:仅在条目数超过 10 行时出现;链接式文字,与导入
            // 入口同一风格。展开后卡片自然变高,滚动交给外层页面。
            Text {
                id: expandRow
                width: parent.width
                visible: page.galleryHasMore
                horizontalAlignment: Text.AlignHCenter
                text: page.galleryExpanded
                    ? I18n.tr("Hide") : I18n.tr("Expand all (") + page.galleryItems.length + I18n.tr(" images)")
                color: page.colors.accent
                font.pixelSize: 12
                font.weight: Font.Medium
                topPadding: 10
                bottomPadding: 12
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.galleryExpanded = !page.galleryExpanded
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        text: page.galleryCategory === "themes" ? I18n.tr("Tap an app, then use the arrow in the bottom-right for the animated desktop preview. It plays automatically after 10 seconds without desktop windows and lowers its cost on battery.")
            : page.galleryCategory === "slideshow"
            ? I18n.tr("Selected ") + page.selectedSlideshowImages.length + I18n.tr(" images · slideshow starts with at least two, preview on the desktop.")
            : page.galleryCategory === "colors" ? I18n.tr("Tap a color to apply a gradient wallpaper; custom colors stay in the list and can be removed on hover.")
            : page.galleryItems.length ? I18n.tr("Pick an image to apply it as the desktop wallpaper directly.")
            : I18n.tr("No images yet; add images or a folder.")
        color: page.colors.secondaryText
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }

    // WallpaperOptionsDialog 已随「更多选项」入口一起移除；三行设置平铺在
    // 上面的选项卡片里。要恢复二级弹窗，从 git 历史找回本文件与实例化块。

    Rectangle {
        visible: !!(page.errorText || page.spatialError || page.takeoverError)
        Layout.fillWidth: true
        implicitHeight: errorMessage.implicitHeight + 22
        radius: 12
        color: Qt.rgba(1, 0.28, 0.24, 0.10)
        RowLayout {
            id: errorMessage
            anchors.fill: parent
            anchors.margins: 11
            spacing: 9
            Text {
                text: "!"
                color: "#d93025"
                font.pixelSize: 14
                font.weight: Font.Bold
            }
            Text {
                Layout.fillWidth: true
                text: page.errorText || page.spatialError || page.takeoverError
                color: "#b42318"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }
    }
}
