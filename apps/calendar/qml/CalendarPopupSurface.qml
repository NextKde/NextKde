import QtQuick
import QtQuick.Window
import Kos.Demo as Demo

// App adapter only; all floating panels share the Demo material and contour.
Demo.LiquidPanelSurface {
    id: root
    readonly property var hostWindow: root.Window.window
    property Item scene: hostWindow ? hostWindow.calendarScene : null
    property real radius: 12
    cornerRadius: radius
    backdrop: Demo.LiquidBackdrop {
        sourceItem: root.scene
        registerAsDefault: false
        active: root.visible && root.scene !== null && !root.reduceTransparency
        blur: 0.85
    }
}
