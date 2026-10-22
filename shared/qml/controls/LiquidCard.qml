import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "../foundation" as Foundation

Pane {
    id: root
    property real radius: 22
    property real readability: 0.47
    property LiquidBackdrop backdrop: LiquidStyle.backdropForItem(root, root.Window.window)
    readonly property LiquidBackdrop contentBackdrop: cardContentBackdrop
    property color tintColor: Foundation.AppTheme.dark ? "#141c30" : "#ffffff"
    property real tintStrength: .08
    property real blurStrength: .45
    property real refractionStrength: 3
    property real magnification: 1.025
    property real reflectionStrength: 1
    property bool shadowEnabled: false
    property color shadowColor: "#000000"
    property real shadowOpacity: .16
    readonly property bool sampling: cardGlass.sampling
    padding: 18
    // A sibling source for content controls: captures only the already composed
    // material, never labels/buttons/content or their consuming lens surfaces.
    LiquidBackdrop {
        id: cardContentBackdrop
        parent: root
        sourceItem: root.background
        registerAsDefault: false
    }
    background: Item {
        LiquidOuterShadow {
            anchors.fill: parent; radius: root.radius
            visible: root.shadowEnabled; shadowColor: root.shadowColor
            shadowOpacity: root.shadowOpacity; offset: Qt.vector2d(0, 3)
        }
        LiquidSurface {
            id: cardGlass
            anchors.fill: parent
            radius: root.radius; readability: root.readability; backdrop: root.backdrop
            tintColor: root.tintColor; tintStrength: root.tintStrength
            blurStrength: root.blurStrength; refractionStrength: root.refractionStrength
            magnification: root.magnification; reflectionStrength: root.reflectionStrength
        }
    }
}
