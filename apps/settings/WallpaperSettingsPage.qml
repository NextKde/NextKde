import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import "../../shared/qml/controls" as LiquidControls

ColumnLayout {
    id: page
    spacing: 16

    property var bridge: null
    property var colors: null
    property string image: ""
    property string fitMode: "crop"
    property string transition: "cinematic"
    property var recentImages: []
    property var catalogImages: []
    property var folderImages: []
    property var storedSlideshowImages: []
    property string folderName: ""
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
    property string galleryCategory: "system"
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
        && typeof bridge.updateWallpaperSlideshow === "function"
        && typeof bridge.updateWallpaperSpatialEnabled === "function"
        && typeof bridge.prepareWallpaperSpatial === "function"
        && typeof bridge.wallpaperImagesInFolder === "function"
        && typeof bridge.chooseWallpaperColor === "function"
        && typeof bridge.updateWallpaperFitMode === "function"
        && typeof bridge.updateWallpaperTransition === "function"
        && typeof bridge.updateWallpaperTakeoverEnabled === "function"
    readonly property int gridColumns: width >= 580 ? 3 : 2
    readonly property bool colorWallpaper: image.indexOf("/wallpaper-colors/") >= 0
    readonly property var intervals: [
        { minutes: 0, label: "关闭" },
        { minutes: 5, label: "每 5 分钟" },
        { minutes: 15, label: "每 15 分钟" },
        { minutes: 60, label: "每小时" },
        { minutes: 1440, label: "每天" }
    ]
    readonly property var swatches: [
        { title: "暮蓝", color: "#27384D" },
        { title: "雾白", color: "#E7E9E7" },
        { title: "石墨", color: "#292C33" },
        { title: "海松", color: "#35645B" },
        { title: "霞光", color: "#C97162" },
        { title: "浅紫", color: "#81749A" },
        { title: "沙丘", color: "#B49C7C" },
        { title: "夜空", color: "#151F3D" }
    ]
    readonly property var galleryItems: {
        if (galleryCategory === "colors")
            return swatches.map(item => ({
                title: item.title, subtitle: "纯色", color: item.color, path: ""
            }))
        const paths = galleryCategory === "recent" ? recentImages
            : galleryCategory === "folder" ? (folderImages.length ? folderImages : storedSlideshowImages) : catalogImages
        return paths.map(path => ({
            title: displayName(path),
            subtitle: galleryCategory === "system" ? "系统壁纸"
                : galleryCategory === "folder" ? "文件夹" : "最近使用",
            color: "", path: path
        }))
    }
    readonly property var slideshowPool: {
        const candidates = folderImages.length > 1 ? folderImages
            : storedSlideshowImages.length > 1 ? storedSlideshowImages
            : catalogImages.concat(recentImages)
        return candidates.filter(path => path.indexOf("/wallpaper-colors/") < 0)
            .filter((path, index, items) => items.indexOf(path) === index)
    }
    onGalleryCategoryChanged: Qt.callLater(() => gallery.positionViewAtBeginning())

    function beginPreview(path) {
        if (!bridgeCompatible || previewPending)
            return
        if (!previewAvailable) {
            errorText = "当前没有可用的显示器，无法启动壁纸预览。"
            return
        }
        errorText = ""
        const paths = galleryItems.filter(item => item.path).map(item => item.path)
        const index = paths.indexOf(path)
        if (index < 0) {
            bridge.previewWallpaperImage(path, [path])
            return
        }
        const first = Math.max(0, index - 30)
        bridge.previewWallpaperImage(path, paths.slice(first, first + 61))
    }

    function displayName(path) {
        const value = String(path || "")
        const packageMarker = "/contents/images/"
        const packageIndex = value.indexOf(packageMarker)
        if (packageIndex > 0)
            return value.slice(0, packageIndex).split("/").pop()
        const name = value.split("/").pop().replace(/\.[^.]+$/, "")
        return name || "未选择壁纸"
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
        image = String(state.image || "")
        fitMode = String(state.fitMode || "crop")
        transition = String(state.transition || "cinematic")
        recentImages = parseImages(state.recentImages)
        slideshowEnabled = !!state.slideshowEnabled
        slideshowIntervalMinutes = Number(state.slideshowIntervalMinutes || 15)
        storedSlideshowImages = parseImages(state.slideshowImages)
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
        enableAfterPreparation = true
        errorText = ""
        bridge.prepareWallpaperSpatial()
    }

    function requestSpatialEnable() {
        if (!bridgeCompatible || modelsChecking || colorWallpaper)
            return
        if (!depthModelReady) {
            modelDialog.open()
            return
        }
        if (!spatialPrepared) {
            beginSpatialPreparation()
            return
        }
        bridge.updateWallpaperSpatialEnabled(true)
    }

    function setSlideshow(enabled, interval) {
        if (!bridgeCompatible) {
            errorText = "设置程序版本过旧，请更新后再使用壁纸功能。"
            return
        }
        if (enabled && slideshowPool.length < 2) {
            errorText = "自动切换至少需要两张图片，请添加文件夹或选择系统壁纸。"
            return
        }
        errorText = ""
        bridge.updateWallpaperSlideshow(enabled, interval, slideshowPool)
    }

    Component.onCompleted: {
        if (bridgeCompatible) {
            catalogImages = bridge.wallpaperCatalog()
            bridge.wallpaperSnapshot()
            bridge.inspectWallpaperModels()
        } else if (bridge) {
            modelsChecking = false
            errorText = "设置程序与壁纸界面版本不匹配，请更新设置程序。"
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
                page.errorText = "深度模型校验未通过，空间壁纸未开启。"
            }
        }
    }

    Timer {
        interval: page.previewActive || page.previewPending ? 700 : 1800
        repeat: true
        running: page.previewActive || page.previewPending || page.enableAfterPreparation || page.spatialBusy
            || page.spatialPreparing || page.takeoverPending
        onTriggered: if (page.bridgeCompatible) page.bridge.wallpaperSnapshot()
    }

    Platform.FileDialog {
        id: fileDialog
        title: "选择壁纸"
        fileMode: Platform.FileDialog.OpenFile
        nameFilters: ["图片 (*.jpg *.jpeg *.png *.webp *.bmp *.avif)"]
        onAccepted: if (page.bridgeCompatible)
            page.beginPreview(selectedFile.toString())
    }

    Platform.FolderDialog {
        id: folderDialog
        title: "选择壁纸文件夹"
        onAccepted: {
            if (!page.bridgeCompatible)
                return
            const images = page.bridge.wallpaperImagesInFolder(folder.toString())
            if (images.length < 1) {
                page.errorText = "文件夹内没有支持的图片。"
                return
            }
            page.folderImages = images
            page.folderName = folder.toString().split("/").pop()
            page.galleryCategory = "folder"
            if (page.slideshowEnabled && images.length < 2)
                page.setSlideshow(false, page.slideshowIntervalMinutes)
            else
                page.setSlideshow(page.slideshowEnabled, page.slideshowIntervalMinutes)
        }
    }

    Dialog {
        id: modelDialog
        modal: true
        width: 380
        title: "准备空间壁纸模型"
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: page.beginSpatialPreparation()
        contentItem: Item {
            implicitWidth: 330
            implicitHeight: 70
            Text {
                anchors.fill: parent
                wrapMode: Text.Wrap
                color: page.colors.primaryText
                text: "先下载并校验本机深度模型，再生成当前壁纸的素材。完成后自动开启空间壁纸。"
            }
        }
    }

    Rectangle {
        id: currentWallpaperCard
        objectName: "currentWallpaperPreviewCard"
        Layout.fillWidth: true
        implicitHeight: 88
        radius: 18
        color: currentWallpaperMouse.containsMouse
            && currentWallpaperMouse.enabled
            ? page.colors.divider
            : page.colors.card
        Behavior on color { ColorAnimation { duration: 120 } }
        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14
            WallpaperThumbnail {
                Layout.preferredWidth: 88
                Layout.preferredHeight: 56
                imagePath: page.image
                surroundingColor: page.colors.card
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Text {
                    Layout.fillWidth: true
                    text: page.displayName(page.image)
                    color: page.colors.primaryText
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
                Text {
                    text: !page.bridgeCompatible
                        ? "设置程序版本不匹配"
                        : !page.previewAvailable
                            ? "当前环境暂不支持桌面预览"
                            : "进入全屏模拟桌面，应用后才会更换壁纸"
                    color: page.colors.secondaryText
                    font.pixelSize: 12
                }
            }
            Text {
                objectName: "currentWallpaperPreviewLabel"
                text: page.previewPending ? "正在载入…"
                    : page.previewAvailable && page.bridgeCompatible ? "桌面预览  ›" : "不可用"
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
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: !!page.image && page.bridgeCompatible
                && page.previewAvailable && !page.previewPending
            onClicked: page.beginPreview(page.image)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: optionsColumn.implicitHeight
        radius: 18
        color: page.colors.card
        Column {
            id: optionsColumn
            width: parent.width
            WallpaperSettingsRow {
                width: parent.width
                colors: page.colors
                label: "空间壁纸"
                separator: true
                LiquidControls.LiquidGlassSwitch {
                    id: spatialSwitch
                    enabled: !page.modelsChecking && !page.colorWallpaper
                        && !page.spatialBusy && !page.spatialPreparing
                    checked: page.spatialEnabled
                    accentColor: page.colors.accent
                    trackColor: page.colors.divider
                    onToggled: function(checked) {
                        if (checked) page.requestSpatialEnable()
                        else if (page.bridgeCompatible) page.bridge.updateWallpaperSpatialEnabled(false)
                        spatialSwitch.checked = Qt.binding(() => page.spatialEnabled)
                    }
                }
            }
            WallpaperSettingsRow {
                width: parent.width
                colors: page.colors
                label: "更换频率"
                separator: true
                WallpaperValueMenu {
                    objectName: "frequencyMenu"
                    width: 142
                    colors: page.colors
                    backdropSource: page
                    model: page.intervals
                    textRole: "label"
                    currentIndex: page.slideshowEnabled
                        ? Math.max(0, page.intervals.findIndex(item => item.minutes === page.slideshowIntervalMinutes)) : 0
                    onActivated: function(index) {
                        const minutes = page.intervals[index].minutes
                        page.setSlideshow(minutes > 0, minutes || page.slideshowIntervalMinutes)
                    }
                }
            }
            WallpaperSettingsRow {
                width: parent.width
                colors: page.colors
                label: "更多选项"
                actionable: true
                onActivated: optionsDialog.open()
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        visible: page.spatialBusy || page.spatialPreparing || page.modelsChecking
        text: page.modelsChecking ? "正在检查空间壁纸模型…" : "正在准备空间壁纸，完成后自动开启…"
        color: page.colors.secondaryText
        font.pixelSize: 12
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        Text {
            text: "图片库"
            color: page.colors.secondaryText
            font.pixelSize: 12
            Layout.leftMargin: 13
        }
        Text {
            text: page.galleryItems.length + " 张"
            color: page.colors.secondaryText
            font.pixelSize: 11
        }
        Item { Layout.fillWidth: true }
        WallpaperValueMenu {
            objectName: "galleryMenu"
            width: 124
            colors: page.colors
            backdropSource: page
            model: ["系统壁纸", "最近使用", "纯色", "轮播图片"]
            onActivated: function(index) {
                page.galleryCategory = ["system", "recent", "colors", "folder"][index]
            }
            currentIndex: ["system", "recent", "colors", "folder"].indexOf(page.galleryCategory)
        }
        WallpaperValueMenu {
            width: 95
            colors: page.colors
            backdropSource: page
            placeholder: "添加…"
            currentIndex: -1
            model: ["添加图片…", "添加文件夹…"]
            onActivated: index => {
                if (index === 0) fileDialog.open()
                else folderDialog.open()
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(420,
            Math.ceil(page.galleryItems.length / page.gridColumns) * 128 + 16)
        visible: page.galleryItems.length > 0
        radius: 18
        color: page.colors.card

        GridView {
            id: gallery
            objectName: "wallpaperGallery"
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            cellWidth: Math.max(1, width / page.gridColumns)
            cellHeight: 128
            boundsBehavior: Flickable.StopAtBounds
            model: page.galleryItems
            delegate: WallpaperGalleryTile {
                required property var modelData
                width: gallery.cellWidth - 12
                height: 116
                imagePath: modelData.path
                title: modelData.title
                subtitle: ""
                swatchColor: modelData.color
                accent: page.colors.accent
                surroundingColor: page.colors.card
                selected: modelData.color ? page.isSwatchSelected(modelData.color) : page.image === modelData.path
                onActivated: {
                    if (!page.bridgeCompatible) return
                    if (modelData.color) page.bridge.chooseWallpaperColor(modelData.color)
                    else page.beginPreview(modelData.path)
                }
            }
            ScrollBar.vertical: ScrollBar {
                policy: gallery.contentHeight > gallery.height
                    ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                width: 6
                contentItem: Rectangle {
                    radius: 3
                    color: page.colors.secondaryText
                    opacity: 0.7
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        text: page.galleryItems.length ? "点选图片，在桌面试用。确认后保留，取消恢复原图。"
            : "暂无图片，可添加图片或文件夹。"
        color: page.colors.secondaryText
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }

    WallpaperOptionsDialog {
        id: optionsDialog
        colors: page.colors
        fitMode: page.fitMode
        transition: page.transition
        takeoverEnabled: page.takeoverEnabled
        takeoverAvailable: page.takeoverAvailable
        takeoverPending: page.takeoverPending
        onFitChosen: mode => { if (page.bridgeCompatible) page.bridge.updateWallpaperFitMode(mode) }
        onTransitionChosen: style => { if (page.bridgeCompatible) page.bridge.updateWallpaperTransition(style) }
        onTakeoverChosen: enabled => { if (page.bridgeCompatible) page.bridge.updateWallpaperTakeoverEnabled(enabled) }
    }

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
