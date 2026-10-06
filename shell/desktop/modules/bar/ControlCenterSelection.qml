import QtQuick
import qs.desktop.modules.common
import "../../../Kos/Ui"

// Paint-only adapter. Observe the existing handler; never install another
// MouseArea or take the grab from a toggle, slider, navigation or drag gesture.
SelectionHighlight {
    id: root
    property var pointer: null
    anchors.fill: parent
    objectName: "control-center-selection-highlight"
    enabled: AppearanceTokens.surface.selectionHighlightStyle === "glass"
        && (!pointer || pointer.enabled)
    hovered: pointer !== null && (pointer.containsMouse || pointer.activeFocus)
    pressed: pointer !== null && pointer.pressed
    dark: AppearanceTokens.isDarkTheme
    // Cards retain their blue/white/orange enabled-state fills. A restrained
    // overlay adds a rim without whitening their labels and foreground icons.
    fillStrength: 0.35
    cornerRadius: Math.min(width, height) / 2
    z: 100
}
