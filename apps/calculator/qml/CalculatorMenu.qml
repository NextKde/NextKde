import QtQuick
import QtQuick.Controls

Menu {
    id: root

    property var colors
    // The app's own content behind the panel. The menu floats over the keypad,
    // so that is what it frosts — see CalculatorGlassPanel.
    property Item backdrop: null

    // Measured off the reference menu panel, as fractions of the phone's screen
    // width: 63.6% wide, 9px of padding. The window this pops out of is 360
    // wide, which is the same order as the phone's own logical width, so the
    // fractions carry straight over.
    padding: 9
    implicitWidth: 228

    // The reference's corner is 75 device px on an 856-wide panel — 12.8% of
    // its width, which here would be 29. It is not carried over: the reference
    // panel is 209 logical px tall against our 133, and a corner proportional
    // to the width reads far rounder on a panel that short. 20 keeps the same
    // family of curve at a size that suits this box.
    readonly property real cornerRadius: 20

    background: CalculatorGlassPanel {
        colors: root.colors
        backdrop: root.backdrop
        radius: root.cornerRadius
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: 120 }
    }
}
