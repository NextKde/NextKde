import Quickshell
import QtQuick
import qs.desktop.modules.common

// A desktop surface is intentionally independent from application windows.
// ScreenLifecycle temporarily hides it while KWin has no real output.
Scope {
    id: root

    // Desktop files and context menus exist independently on every usable
    // output. DeskCenterWindow itself keeps widgets restricted to the elected
    // primary screen.
    Variants {
        model: ScreenLifecycle.usableScreens

        delegate: Component {
            Scope {
                id: outputScope
                required property var modelData

                // Keep this surface mapped before the widget surface. Both use
                // the Bottom layer so Plasma cannot cover the wallpaper.
                SpatialWallpaperWindow {
                    id: wallpaperWindow
                    screen: outputScope.modelData
                    visible: ScreenLifecycle.outputAvailable
                        && (WallpaperService.takeoverEnabled || SpatialWallpaperService.ready)
                    pointerX: widgetWindow.depthPointerX
                    pointerY: widgetWindow.depthPointerY
                }

                DeskCenterWindow {
                    id: widgetWindow
                    screen: outputScope.modelData
                    visible: ScreenLifecycle.outputAvailable
                    spatialWallpaperActive: wallpaperWindow.active
                }

                // Map after the ordinary desktop surfaces so the transient
                // scene covers every QML surface on this output.
                WallpaperPreviewBar {
                    screen: outputScope.modelData
                    visible: ScreenLifecycle.outputAvailable && WallpaperPreviewService.active
                }
            }
        }
    }
}
