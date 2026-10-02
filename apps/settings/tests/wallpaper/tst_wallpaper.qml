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
            colors: ({ card: "#202020", primaryText: "#ffffff",
                       secondaryText: "#aaaaaa", accent: "#4488ff",
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
        property string lastError: ""
        signal wallpaperSnapshotChanged(var state)
        signal wallpaperModelsChecked(bool depthReady, bool foregroundReady)
        function wallpaperCatalog() { return [] }
        function wallpaperSnapshot() {}
        function inspectWallpaperModels() {}
        function previewWallpaperImage(path, images) { previewRequested = path }
        function updateWallpaperSlideshow(enabled, minutes, images) {
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
        compare(page.storedSlideshowImages.length, 2)
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
        page.catalogImages = new Array(90).fill("")

        const gallery = findChild(page, "wallpaperGallery")
        verify(gallery !== null)
        compare(gallery.count, 90)
        verify(gallery.contentHeight > gallery.height)
        gallery.positionViewAtIndex(89, GridView.End)
        tryVerify(() => gallery.contentY > 0)
        page.catalogImages = ["/tmp/wallpaper-a.jpg", "/tmp/wallpaper-b.jpg"]

        const frequency = findChild(page, "frequencyMenu")
        verify(frequency !== null)
        frequency.activated(3)
        compare(bridgeMock.slideshowRequested, true)
        compare(bridgeMock.intervalRequested, 60)

        const category = findChild(page, "galleryMenu")
        verify(category !== null)
        category.activated(2)
        compare(page.galleryCategory, "colors")

        const fit = findChild(page, "wallpaperFitMenu")
        const transition = findChild(page, "wallpaperTransitionMenu")
        verify(fit !== null)
        verify(transition !== null)
        fit.activated(1)
        transition.activated(2)
        compare(bridgeMock.fitRequested, "fit")
        compare(bridgeMock.transitionRequested, "none")
    }
}
