import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.deskcenter
import qs.desktop.modules.wallpaper

ShellRoot {
    SpatialWallpaperWindow {
        Rectangle { anchors.fill: parent; color: "#1268c4" }
    }
    DeskCenterWindow {
        // A visible marker in the real desktop surface; the covering app
        // must occlude it throughout the desktop-switch animation.
        Rectangle { anchors.centerIn: parent; width: 180; height: 180; color: "#ff00ff"; z: 10000 }
    }
    PanelWindow {
        WlrLayershell.namespace: "dock"
        WlrLayershell.layer: WlrLayer.Top
        anchors { top: true; left: true }
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 90
        implicitHeight: 30
        color: "#00ff00"
    }
}
