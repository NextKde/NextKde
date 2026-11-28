import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common

// Independent Overlay-layer surface for the widget gallery panel. Pulled out
// of DeskCenterWindow (WlrLayer.Bottom) so the panel can float above the
// Dock and the desktop's own icons/widgets instead of sharing their
// stacking plane. DeskCenterWindow still owns the desktop grid, drop-preview
// highlighting and placement logic; every cross-window interaction (open
// state, catalog, add requests, geometry) goes through WidgetGalleryService
// instead of a shared item tree, since mapToGlobal is unreliable for
// layer-shell surfaces on Wayland (see DockIcon.qml).
PanelWindow {
    id: root

    WlrLayershell.namespace: "quickshell-widgetgallery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors { top: true; left: true; right: true; bottom: true }
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080

    // This surface spans the whole output (so the gallery panel can be
    // positioned/animated freely within it), but the panel itself only
    // occupies a small rect of that -- without a mask, the window's default
    // full-surface input region swallows every click/right-click/drag over
    // the *entire* screen while open, including on top of the desktop
    // widgets DeskCenterWindow renders underneath on the Bottom layer. Those
    // widgets' delete badge/context menu/drag handler are all still wired
    // and genuinely active (edit mode really is on), they just never
    // receive the pointer event because this window's full-screen surface
    // sits in front of them and claims it first. Restrict accepted input to
    // the gallery's own live bounds, same pattern as BatteryPanel.qml/
    // DockWindow.qml.
    mask: root.visible ? galleryInputRegion : emptyInputRegion
    Region { id: galleryInputRegion; item: gallery }
    Region { id: emptyInputRegion }

    // Set by the instantiator (DeskCenter.qml): whether this screen should
    // currently host the gallery (output availability + active-screen
    // restriction). The window's actual `visible` stays mapped a little
    // longer than this so the rise/fade-out animation can finish before the
    // layer-shell surface unmaps — unmapping instantly would cut the close
    // animation off on the first frame.
    property bool shouldShow: false
    property real openProgress: 0
    visible: root.shouldShow || root.openProgress > 0.001

    onShouldShowChanged: root.openProgress = root.shouldShow ? 1 : 0
    Behavior on openProgress {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    readonly property real fullWidth: Math.max(1, WidgetGalleryService.galleryWidth)
    readonly property real fullHeight: Math.max(1, WidgetGalleryService.galleryHeight)
    readonly property real targetWidth: WidgetGalleryService.minimized
        ? Math.min(root.fullWidth, 420) : root.fullWidth
    readonly property real targetHeight: WidgetGalleryService.minimized
        ? 56 : root.fullHeight
    readonly property real targetX: WidgetGalleryService.galleryX
        + (root.fullWidth - root.targetWidth) / 2
    readonly property real targetY: WidgetGalleryService.galleryY
        + root.fullHeight - root.targetHeight

    WidgetGallery {
        id: gallery
        objectName: "widget-gallery-panel"
        property real baseY: root.targetY
        x: root.targetX
        // Rises gently into its resting position above the Dock while opening,
        // and sinks back down as it fades out on close.
        y: gallery.baseY + (1 - root.openProgress) * 24
        opacity: root.openProgress
        width: root.targetWidth
        height: root.targetHeight
        Behavior on x { enabled: root.visible && root.openProgress > 0.95; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on baseY { enabled: root.visible && root.openProgress > 0.95; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: root.visible && root.openProgress > 0.95; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: root.visible && root.openProgress > 0.95; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        visible: root.visible
        minimized: WidgetGalleryService.minimized
        placementEnabled: true
        catalog: WidgetGalleryService.catalog
        invalidPackages: WidgetGalleryService.invalidPackages
        trippedPackages: WidgetGalleryService.trippedPackages
        missingInstances: WidgetGalleryService.missingInstances
        loading: WidgetGalleryService.loading
        feedback: WidgetGalleryService.feedback
        onVisibleChanged: if (visible) {
            selectedCategory = WidgetGalleryService.requestedCategory
            begin()
        }
        onDone: WidgetGalleryService.done()
        onMinimizeToggled: WidgetGalleryService.toggleMinimized()
        onOpenPluginStoreRequested: {
            WidgetGalleryService.openPluginStore()
            WidgetGalleryService.done()
        }
        onAddRequested: (entry, size) => WidgetGalleryService.addRequested(entry, size)
        onReEnableRequested: packageId => WidgetGalleryService.reEnableRequested(packageId)
        onRemoveRetiredInstanceRequested: instanceId => WidgetGalleryService.removeRetiredInstanceRequested(instanceId)
    }

    // Legacy transport for compositors without the v8 declaration. Matches
    // AppLauncherWindow's own BackgroundEffect publishing policy.
    BackgroundEffect.blurRegion: (AppearanceTokens.surface.usesKwinBlur && root.visible
        && gallery.visible && gallery.width >= 1 && gallery.height >= 1)
        ? gallery.blurRegion
        : null
}
