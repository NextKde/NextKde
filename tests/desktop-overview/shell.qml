import QtQuick
import Quickshell
import qs.desktop.modules.deskcenter
import qs.desktop.modules.wallpaper

// Real product surfaces; only the wallpaper pixels are fixture-owned.
ShellRoot {
    id: root
    readonly property bool widgetsFirst: Quickshell.env("DESKTOP_OVERVIEW_WIDGETS_FIRST") === "1"

    SpatialWallpaperWindow {
        id: wallpaper
        visible: false
        Rectangle { anchors.fill: parent; color: "#1268c4" }
    }
    DeskCenterWindow {
        id: widgets
        visible: false
    }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            if (root.widgetsFirst) widgets.visible = true
            else wallpaper.visible = true
            secondSurface.start()
        }
    }
    Timer {
        id: secondSurface
        interval: 300
        onTriggered: {
            wallpaper.visible = true
            widgets.visible = true
        }
    }
}
