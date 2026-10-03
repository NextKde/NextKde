import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.desktop.modules.common
import qs.desktop.modules.dock

// A real compositor surface above the desktop, independent of widget z values.
PanelWindow {
    id: root
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "kos-theme-foreground"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true; bottom: true }
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080
    mask: Region {}
    readonly property var blockingWindows: {
        const revision=WindowService.revision+WindowService.placementRevision
        return WindowService.records.filter(w => {
            if ((w.isMinimized ?? w.toplevel?.minimized) || w.isVisible===false) return false
            if (WindowService.currentDesktopId && !w.onAllDesktops && w.desktopIds?.length
                && !w.desktopIds.includes(WindowService.currentDesktopId)) return false
            const r = w.geometry
            const screen = root.screen
            if (r && screen)
                return r.x < screen.x + screen.width && r.y < screen.y + screen.height
                    && r.x + r.width > screen.x && r.y + r.height > screen.y
            return !w.screenName || w.screenName===screen?.name
        })
    }
    // Unknown geometry fails closed rather than drawing over an application.
    readonly property bool clippingReady: blockingWindows.length<=16 && blockingWindows.every(w=>!!w.geometry)
    visible: ScreenLifecycle.outputAvailable && ThemeWallpaperService.active
        && !ThemeWallpaperService.locked
        && clippingReady

    ThemeWallpaperLayer {
        id: effects
        width: root.width
        height: root.height
        targetScreen: root.screen
        foreground: true
        rendererEnabled: root.visible
        layer.enabled: true
        layer.effect: ShaderEffect {
            property var source
            property vector2d viewport: Qt.vector2d(effects.width,effects.height)
            property real count: Math.min(8,effects.sceneItem?.widgetRects?.length ?? 0)
            property real blockedCount: root.blockingWindows.length
            property vector4d dock: {
                const r=ThemeWallpaperService.dockRects[root.screen?.name]
                return r ? Qt.vector4d(r.x,r.y,r.width,r.height) : Qt.vector4d(-10000,-10000,0,0)
            }
            function allowed(i) {
                const r=effects.sceneItem?.widgetRects?.[i]
                return r ? Qt.vector4d(r.x,r.y,r.width,r.height) : Qt.vector4d(-10000,-10000,0,0)
            }
            function blocked(i) {
                const r=root.blockingWindows[i]?.geometry
                return r ? Qt.vector4d(r.x-(root.screen?.x ?? 0)-8,r.y-(root.screen?.y ?? 0)-8,r.width+16,r.height+16)
                    : Qt.vector4d(-10000,-10000,0,0)
            }
            property vector4d area0: allowed(0)
            property vector4d area1: allowed(1)
            property vector4d area2: allowed(2)
            property vector4d area3: allowed(3)
            property vector4d area4: allowed(4)
            property vector4d area5: allowed(5)
            property vector4d area6: allowed(6)
            property vector4d area7: allowed(7)
            property vector4d block0: blocked(0)
            property vector4d block1: blocked(1)
            property vector4d block2: blocked(2)
            property vector4d block3: blocked(3)
            property vector4d block4: blocked(4)
            property vector4d block5: blocked(5)
            property vector4d block6: blocked(6)
            property vector4d block7: blocked(7)
            property vector4d block8: blocked(8)
            property vector4d block9: blocked(9)
            property vector4d block10: blocked(10)
            property vector4d block11: blocked(11)
            property vector4d block12: blocked(12)
            property vector4d block13: blocked(13)
            property vector4d block14: blocked(14)
            property vector4d block15: blocked(15)
            fragmentShader: "shaders/foreground_clip.frag.qsb"
        }
    }
    IpcHandler {
        target: "theme-foreground-" + (root.screen?.name ?? "unknown")
        function snapshot(): string {
            const scene=effects.sceneItem
            return JSON.stringify({visible:root.visible,screen:root.screen?.name,
                width:root.width,height:root.height,layer:root.WlrLayershell.layer,
                effectWidth:effects.width,effectHeight:effects.height,
                active:effects.active,foreground:effects.foreground,
                sceneWidth:scene?.width,sceneHeight:scene?.height,
                sceneForeground:scene?.foreground,phase:effects.framePhase,
                covered:ThemeWallpaperService.covered(root.screen),
                hasVisibleWindows:ThemeWallpaperService.hasVisibleWindows,
                widgets:scene?.widgetRects})
        }
    }
}
