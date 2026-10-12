import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.desktop.modules.common

// Separate wallpaper surface: widget glass asks KWin to blur the window
// behind it, so the wallpaper must not be painted inside DeskCenterWindow.
PanelWindow {
    id: root

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    // KWin reads this as a scope, not as our name: it maps the string to a
    // window type ("desktop" -> WindowType::Desktop) and only Desktop/Dock-typed
    // windows are exempt from Show Desktop hiding (KWin's
    // Workspace::breaksShowingDesktop). Under any other scope, Meta+D hides this
    // surface and Plasma's solid takeover backdrop reads as a black desktop while
    // the bar and dock survive -- so this string is load bearing, not cosmetic.
    WlrLayershell.namespace: "desktop"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080
    mask: Region {}

    property real pointerX: 0
    property real pointerY: 0
    readonly property bool active: wallpaperLayer.active

    Connections {
        target: root.contentItem.Window.window
        function onFrameSwapped() {
            if (SessionEntryService.pending && SessionEntryService.defaultBackground) {
                SessionEntryService.frame(root.screen.name, "", "crop"); return;
            }
            if (SessionEntryService.pending && ordinaryWallpaper.visible
                && ordinaryWallpaper.ready && !ordinaryWallpaper.transitioning
                && ordinaryWallpaper.currentImage.source.toString() === ordinaryWallpaper.source.toString()
                && !ThemeWallpaperService.active && !wallpaperLayer.active)
                SessionEntryService.frame(root.screen.name, ordinaryWallpaper.source.toString(), ordinaryWallpaper.fitMode)
        }
    }
    WallpaperImageLayer {
        id: entryWallpaper
        backgroundColor: "#16283b"
        anchors.fill: parent
        z: 200
        targetScreen: root.screen
        source: SessionEntryService.sessionImage
        fitMode: SessionEntryService.sessionFit
        transition: "none"
        visible: SessionEntryService.sessionImage !== ""
    }
    Connections {
        target: root.contentItem.Window.window
        function onFrameSwapped() {
            if (SessionEntryService.pending && entryWallpaper.visible && entryWallpaper.ready
                && !entryWallpaper.transitioning
                && entryWallpaper.currentImage.source.toString() === entryWallpaper.source.toString())
                SessionEntryService.frame(root.screen.name, entryWallpaper.source.toString(), entryWallpaper.fitMode)
        }
    }
    Rectangle {
        anchors.fill: parent; z: 201; color: "#16283b"
        visible: SessionEntryService.defaultBackground
    }
    ThemeWallpaperLayer {
        anchors.fill: parent
        targetScreen: root.screen
        rendererEnabled: !SessionEntryService.staticPresentation
    }

    WallpaperImageLayer {
        id: ordinaryWallpaper
        anchors.fill: parent
        targetScreen: root.screen
        previewTarget: WallpaperPreviewService.active
        source: SessionEntryService.staticPresentation || ThemeWallpaperService.active ? ""
            : WallpaperPreviewService.active ? WallpaperPreviewService.image
            : (WallpaperService.takeoverEnabled ? WallpaperService.wallpaperUrl : "")
        fitMode: SessionEntryService.sessionImage ? SessionEntryService.sessionFit : WallpaperService.fitMode
        transition: WallpaperService.transition
        visible: !ThemeWallpaperService.active && (WallpaperPreviewService.active || WallpaperService.takeoverEnabled) && ordinaryWallpaper.ready
            && wallpaperLayer.opacity < 1
    }

    DepthWallpaperLayer {
        id: wallpaperLayer
        anchors.fill: parent
        targetScreen: root.screen
        renderingEnabled: !SessionEntryService.staticPresentation
        pointerX: root.pointerX
        pointerY: root.pointerY
    }

    IpcHandler {
        target: "spatial-wallpaper-" + (root.screen?.name ?? "unknown")
        function snapshot(): string {
            return JSON.stringify({active: wallpaperLayer.active,
                visualReady: wallpaperLayer.visualReady,
                opacity: wallpaperLayer.opacity,
                meshRenderer: wallpaperLayer.meshRendererAvailable,
                pointerX: root.pointerX, pointerY: root.pointerY,
                renderedPointerX: wallpaperLayer.renderedPointerX,
                renderedPointerY: wallpaperLayer.renderedPointerY,
                preview: WallpaperPreviewService.active})
        }
    }
}
