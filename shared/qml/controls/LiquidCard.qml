import QtQuick
import QtQuick.Window
import QtQuick.Controls

Pane {
    id: root
    property real radius: 20
    property real readability: 0.47
    property LiquidBackdrop backdrop: LiquidStyle.backdropFor(root.Window.window)
    padding: 18
    background: LiquidSurface {
        radius: root.radius
        readability: root.readability
        backdrop: root.backdrop
    }
}
