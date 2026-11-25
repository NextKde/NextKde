import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.desktop.modules.common
import "../../../Kos/Ui"

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

    // Login backdrop: the same plain black (dark theme) or white (light theme)
    // the splash process paints, so the splash can be stopped at the start of
    // the arrival without a visible step and this surface carries on alone
    // until the wallpaper fades in. The spinner itself lives in that other
    // process (splash/shell.qml): the Shell's GUI thread is busy here. This is
    // an overlay rather than content opacity on purpose: ThemeWallpaperLayer
    // reports readiness from painted frames, and an invisible content tree
    // would never paint one.
    readonly property bool backdropCanLeave: StartupReveal.started || !StartupReveal.active
    onBackdropCanLeaveChanged: if (backdropCanLeave) startupBackdrop.opacity = 0
    Component.onCompleted: if (backdropCanLeave) startupBackdrop.opacity = 0
    // Never leave the backdrop covering the desktop if the reveal never starts.
    Timer {
        interval: 15000
        running: true
        onTriggered: startupBackdrop.opacity = 0
    }
    Rectangle {
        id: startupBackdrop
        anchors.fill: parent
        z: 100
        color: WallpaperColorSource.darkMode ? "#000000" : "#ffffff"
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
        }
    }

    property real pointerX: 0
    property real pointerY: 0

    ThemeWallpaperLayer {
        anchors.fill: parent
        targetScreen: root.screen
    }

    WallpaperImageLayer {
        id: ordinaryWallpaper
        anchors.fill: parent
        targetScreen: root.screen
        previewTarget: WallpaperPreviewService.active
        source: ThemeWallpaperService.active ? ""
            : WallpaperPreviewService.active ? WallpaperPreviewService.image
            : WallpaperService.takeoverEnabled ? WallpaperService.wallpaperUrl : ""
        fitMode: WallpaperService.fitMode
        transition: WallpaperService.transition
        visible: !ThemeWallpaperService.active && (WallpaperPreviewService.active || WallpaperService.takeoverEnabled) && ordinaryWallpaper.ready
            && wallpaperLayer.opacity < 1
    }

    DepthWallpaperLayer {
        id: wallpaperLayer
        anchors.fill: parent
        targetScreen: root.screen
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
                motionRunning: wallpaperLayer.motionRunning,
                preview: WallpaperPreviewService.active})
        }
    }
}
