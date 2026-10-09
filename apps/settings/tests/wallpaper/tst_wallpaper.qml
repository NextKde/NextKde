import QtQuick
import QtTest
import "../.." as Settings

TestCase {
    name: "WallpaperSettings"
    when: windowShown

    Component {
        id: pageComponent
        Settings.WallpaperSettingsPage {
            width: 780
            height: implicitHeight
            colors: ({ card: "#202020", primaryText: "#ffffff",
                       secondaryText: "#aaaaaa", tertiaryText: "#888888", accent: "#4488ff",
                       divider: "#555555", separator: "#444444",
                       dark: true })
        }
    }

    SignalSpy { id: previewFinished; signalName: "desktopPreviewFinished" }

    QtObject {
        id: bridgeMock
        property bool slideshowRequested: false
        property int intervalRequested: -1
        property string fitRequested: ""
        property string transitionRequested: ""
        property string previewRequested: ""
        property string imageRequested: ""
        property string themeRequested: ""
        property bool themeEconomicalRequested: false
        property var sessionRequested: ({})
        property var playlistRequested: []
        property var gradientRequested: []
        property var optionsRequested: ({})
        property string lastError: ""
        signal wallpaperSnapshotChanged(var state)
        signal wallpaperModelsChecked(bool depthReady, bool foregroundReady)
        function wallpaperCatalog() { return [] }
        function chooseWallpaperTheme(id) { themeRequested = id }
        function updateWallpaperThemeEconomical(value) { themeEconomicalRequested = value }
        function galleryImages() { return [] }
        function importGalleryImage(path) {}
        function importGalleryFolder(path) {}
        function deleteGalleryImage(path) { return true }
        function wallpaperSnapshot() {}
        function inspectWallpaperModels() {}
        function previewWallpaperImage(path, images) { previewRequested = path }
        function wallpaperColorImage(start, end, angle) { return "/tmp/wallpaper-colors/" + start.slice(1) + "-" + end.slice(1) + "-" + angle + ".png" }
        function chooseWallpaperGradient(start, end, angle) { gradientRequested = [start, end, angle] }
        function wallpaperThumbnail(path, width, height) { return "/tmp/cache/" + encodeURIComponent(path) + ".webp" }
        function updateWallpaperPreviewThumbnails(thumbnails) {}
        function previewWallpaperSession(path, session) { previewRequested = path; sessionRequested = session }
        function updateWallpaperTransitionOptions(options) { optionsRequested = options }
        function chooseWallpaperImage(path) { imageRequested = path }
        function filterExistingImages(images) { return images }
        function addWallpaperImages(images) {}
        function addWallpaperFolder(path) {}
        function removeWallpaperFromLibrary(type, ref) {}
        function revealWallpaperImage(path) {}
        function updateWallpaperSlideshow(enabled, minutes, images) {
            playlistRequested = images
            slideshowRequested = enabled
            intervalRequested = minutes
        }
        function updateWallpaperSpatialEnabled(enabled) {}
        function prepareWallpaperSpatial() {}
        function wallpaperImagesInFolder(path) { return [] }
        function chooseWallpaperColor(color) {}
        function updateWallpaperFitMode(mode) { fitRequested = mode }
        function updateWallpaperTransition(style) { transitionRequested = style }
        function updateWallpaperTakeoverEnabled(enabled) {}
    }

    function test_previewActionUsesCompatibleBridge() {
        const page = createTemporaryObject(pageComponent, null)
        verify(page !== null)
        page.bridge = bridgeMock
        page.image = "/tmp/wallpaper.jpg"
        page.previewAvailable = true
        tryCompare(page, "bridgeCompatible", true)

        const action = findChild(page, "currentWallpaperPreviewAction")
        const label = findChild(page, "currentWallpaperPreviewLabel")
        verify(action !== null)
        verify(label !== null)
        compare(action.enabled, true)
        compare(label.text, "桌面预览  ›")
        action.clicked(null)
        compare(bridgeMock.previewRequested, "/tmp/wallpaper.jpg")
    }

    function test_galleryClickAppliesWithoutPreview() {
        const page = createTemporaryObject(pageComponent, null)
        page.bridge = bridgeMock
        page.catalogImages = ["/tmp/direct-wallpaper.jpg"]
        bridgeMock.previewRequested = ""
        bridgeMock.imageRequested = ""
        const gallery = findChild(page, "wallpaperGallery")
        tryVerify(() => gallery.itemAtIndex(0) !== null)
        gallery.itemAtIndex(0).item.activated()
        compare(bridgeMock.imageRequested, "/tmp/direct-wallpaper.jpg")
        compare(bridgeMock.previewRequested, "")
    }

    function test_slideshowSelectionAndPreviewShareDraft() {
        const page = createTemporaryObject(pageComponent, null)
        page.bridge = bridgeMock
        page.catalogImages = ["/tmp/a.jpg", "/tmp/b.jpg", "/tmp/c.jpg"]
        page.previewAvailable = true
        page.chooseCategory(2)
        page.toggleSlideshowImage("/tmp/a.jpg")
        compare(bridgeMock.slideshowRequested, false)
        page.toggleSlideshowImage("/tmp/c.jpg")
        compare(bridgeMock.slideshowRequested, true)
        compare(bridgeMock.playlistRequested.join(","), "/tmp/a.jpg,/tmp/c.jpg")
        page.beginPreview("/tmp/a.jpg")
        compare(bridgeMock.sessionRequested.mode, "slideshow")
        compare(bridgeMock.sessionRequested.images.length, 3)
        compare(bridgeMock.sessionRequested.thumbnails["/tmp/a.jpg"], "/tmp/cache/%2Ftmp%2Fa.jpg.webp")
        compare(bridgeMock.previewRequested, "/tmp/a.jpg")
        compare(bridgeMock.sessionRequested.colors.length, 18)
        compare(bridgeMock.sessionRequested.selectedImages.length, 2)
        page.toggleSlideshowImage("/tmp/a.jpg")
        compare(bridgeMock.slideshowRequested, false)
    }

    function test_colorCatalogAndCustomApply() {
        const page = createTemporaryObject(pageComponent, null)
        page.bridge = bridgeMock
        page.chooseCategory(1)
        compare(page.galleryItems.length, 18)
        page.choosePresetColor(7)
        compare(bridgeMock.gradientRequested.length, 3)
        verify(bridgeMock.gradientRequested[0] !== bridgeMock.gradientRequested[1])
        findChild(page, "customWallpaperColorDialog").selectedColor = "#A8C8F0"
        page.applyCustomColor()
        compare(page.customColors.length, 1)
        verify(bridgeMock.gradientRequested[0] !== bridgeMock.gradientRequested[1])
        const previous = bridgeMock.gradientRequested.join(",")
        page.colorDepth = 0.9
        page.applyBaseColor(page.selectedBaseColor, true)
        verify(bridgeMock.gradientRequested.join(",") !== previous)
    }

    function test_customColorsAccumulateAndOnlyCustomCanBeRemoved() {
        const page = createTemporaryObject(pageComponent, null)
        page.bridge = bridgeMock
        page.applyBaseColor("#123456", true)
        page.applyBaseColor("#987654", true)
        compare(page.customColors.length, 2)
        const custom = page.colorItems.filter(item => item.managed)
        compare(custom.length, 2)
        compare(page.colorItems.filter(item => !item.managed).length, 18)
        page.choosePresetColor(1)
        compare(page.customColors.length, 2)
        page.removeCustomColor(page.colorItems[0].path)
        compare(page.customColors.length, 2)
        page.removeCustomColor(custom[0].path)
        compare(page.customColors.length, 1)
    }

    function test_colorDepthAndPreviewStayInSync() {
        const page = createTemporaryObject(pageComponent, null)
        page.bridge = bridgeMock
        page.chooseCategory(1)
        const original = page.colorItems[1].path
        page.colorDepth = 0.9
        verify(page.colorItems[1].path !== original)
        page.previewAvailable = true
        page.previewActive = true
        bridgeMock.gradientRequested = []
        page.choosePresetColor(1)
        compare(bridgeMock.gradientRequested.length, 0)
        compare(bridgeMock.previewRequested, page.colorItems[1].path)
        compare(bridgeMock.sessionRequested.mode, "color")
    }

    function test_customPickerTabsAndRgb() {
        const page = createTemporaryObject(pageComponent, this)
        page.bridge = bridgeMock
        const picker = findChild(page, "customWallpaperColorDialog")
        picker.open()
        tryCompare(picker, "visible", true)
        picker.selectedTab = 1
        wait(30)
        picker.selectedTab = 2
        wait(30)
        picker.setRgb(0, 0.25)
        verify(Math.abs(picker.selectedColor.r - 0.25) < 0.01)
        picker.colorApplied(picker.selectedColor)
        tryCompare(picker, "visible", false)
        verify(bridgeMock.gradientRequested[0] !== bridgeMock.gradientRequested[1])
    }

    function test_previewSnapshotSyncsModeAndSelection() {
        const page = createTemporaryObject(pageComponent, null)
        page.bridge = bridgeMock
        page.applyState({ fitMode: "crop", image: "/tmp/a.jpg", transition: "wave",
            transitionOptions: '{"angle":90}', previewActive: true,
            previewMode: "slideshow", previewImage: "/tmp/b.jpg",
            previewInterval: 30, previewSelection: '["/tmp/a.jpg","/tmp/b.jpg"]' })
        compare(page.galleryCategory, "slideshow")
        compare(page.selectedSlideshowImages.length, 2)
        compare(page.slideshowIntervalMinutes, 30)
        compare(page.previewImage, "/tmp/b.jpg")
        const effects = findChild(page, "wallpaperTransitionMenu")
        effects.activated(8)
        compare(bridgeMock.transitionRequested, "wave")
    }

    function test_incompatibleBridgeDisablesPreview() {
        const page = createTemporaryObject(pageComponent, null)
        const oldBridge = Qt.createQmlObject("import QtQuick; QtObject {}", page)
        page.bridge = oldBridge
        page.image = "/tmp/wallpaper.jpg"
        page.previewAvailable = true

        compare(page.bridgeCompatible, false)
        const action = findChild(page, "currentWallpaperPreviewAction")
        const label = findChild(page, "currentWallpaperPreviewLabel")
        compare(action.enabled, false)
        compare(label.text, "不可用")
    }

    function test_pageLoadsAndAcceptsSnapshot() {
        const page = createTemporaryObject(pageComponent, null)
        verify(page !== null)
        page.applyState({ image: "", fitMode: "fit",
            transition: "fade", recentImages: "[]", takeoverEnabled: true,
            spatialEnabled: false, slideshowEnabled: true,
            slideshowIntervalMinutes: 60,
            slideshowImages: '["/tmp/a.jpg","/tmp/b.jpg"]' })
        compare(page.image, "")
        compare(page.fitMode, "fit")
        compare(page.transition, "fade")
        compare(page.takeoverEnabled, true)
        compare(page.slideshowEnabled, true)
        compare(page.slideshowIntervalMinutes, 60)
        compare(page.selectedSlideshowImages.length, 2)
        previewFinished.target = page
        page.applyState({ fitMode: "fit", previewActive: true })
        page.applyState({ fitMode: "fit", previewActive: false,
            previewPending: true })
        compare(previewFinished.count, 0)
        page.applyState({ fitMode: "fit", previewActive: false,
            previewPending: false })
        compare(previewFinished.count, 1)
    }

    function test_galleryAndMenuChoices() {
        const page = createTemporaryObject(pageComponent, null)
        verify(page !== null)
        page.bridge = bridgeMock
        page.catalogImages = Array.from({length: 90}, (_, i) => "/tmp/wallpaper-" + i + ".jpg")

        const gallery = findChild(page, "wallpaperGallery")
        verify(gallery !== null)
        compare(gallery.count, 30)
        compare(gallery.interactive, false)
        page.galleryExpanded = true
        compare(gallery.count, 90)
        page.catalogImages = ["/tmp/wallpaper-a.jpg", "/tmp/wallpaper-b.jpg"]

        const frequency = findChild(page, "frequencyMenu")
        verify(frequency !== null)
        page.chooseCategory(2)
        page.selectAllImages()
        frequency.activated(4)
        compare(bridgeMock.slideshowRequested, true)
        compare(bridgeMock.intervalRequested, 60)
        compare(bridgeMock.playlistRequested.length, 2)

        const category = findChild(page, "wallpaperTypeMenu")
        verify(category !== null)
        category.activated(1)
        compare(page.galleryCategory, "colors")

        const fit = findChild(page, "wallpaperFitMenu")
        const transition = findChild(page, "wallpaperTransitionMenu")
        verify(fit !== null)
        verify(transition !== null)
        fit.activated(1)
        transition.activated(0)
        compare(bridgeMock.fitRequested, "fit")
        compare(bridgeMock.transitionRequested, "none")
    }
    function test_themeGalleryAndPreview() {
        const page = createTemporaryObject(pageComponent, this, {bridge: bridgeMock})
        verify(page)
        page.previewAvailable = true
        page.chooseCategory(3)
        compare(page.galleryCategory, "themes")
        compare(page.galleryItems.map(item => item.id).join(","),
                "starfield,blackhole,weather,underwater,forest")
        const gallery = findChild(page, "wallpaperGallery")
        tryVerify(() => gallery.itemAtIndex(1) !== null && gallery.itemAtIndex(1).item !== null)
        gallery.itemAtIndex(1).item.activated()
        compare(bridgeMock.themeRequested, "blackhole")
        page.beginPreview("theme:blackhole")
        compare(bridgeMock.previewRequested, "theme:blackhole")
        compare(bridgeMock.sessionRequested.mode, "theme")
        page.applyState({fitMode:"crop", wallpaperMode:"theme", themeId:"weather", themeEconomical:true,
                        previewActive:false, previewAvailable:true})
        compare(page.currentIsTheme, true)
        compare(page.displayedThemeId, "weather")
    }

}
