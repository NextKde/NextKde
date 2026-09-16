import Kos.SurfaceShape 1.0
import QtQuick

// One compositor-facing declaration for a shaped shell surface.
//
// RoundedBlurRegion supplies KWin's integer backdrop mask; SurfaceShape
// supplies the exact radius and superellipse exponent used by Glass. Keeping
// them together makes it impossible for a panel's blur and liquid outline to
// quietly diverge.
RoundedBlurRegion {
    id: root

    property real exponent: 2.0
    property bool shapeEnabled: true

    // Contrast scrim forwarded to the compositor alongside the shape. tint
    // 0 = black (for bright backdrops), 1 = white (for dark backdrops). cap is
    // the absolute opacity ceiling; decay scales the auto-derived opacity so a
    // surface can sit calmer than the default (a dock at 0.6, say).
    property bool scrimEnabled: false
    property int scrimTint: 0
    property real scrimCap: 0.0
    property real scrimDecay: 1.0

    // This object must not be placed in Region's default `regions` list: it
    // is protocol state, not an additional geometric primitive.
    property var surfaceShape: SurfaceShape {
        target: root.item
        radius: root.radius
        exponent: root.exponent
        enabled: root.shapeEnabled
        scrimEnabled: root.scrimEnabled
        scrimTint: root.scrimTint
        scrimCap: root.scrimCap
        scrimDecay: root.scrimDecay
    }
}
