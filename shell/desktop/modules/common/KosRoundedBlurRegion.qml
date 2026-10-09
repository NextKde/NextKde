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
    // The blur/capture mask can stay fixed while this item's outline expands.
    property Item shapeItem: item
    property real shapeRadius: radius
    readonly property bool fixedCaptureSupported:
        ("fixedCaptureSupported" in surfaceShape) && surfaceShape.fixedCaptureSupported

    property real materialOpacity: 1.0
    readonly property bool materialOpacitySupported:
        ("materialOpacitySupported" in surfaceShape) && surfaceShape.materialOpacitySupported

    property bool revealEnabled: false
    property bool revealOpened: false
    property int revealDuration: 320
    readonly property bool revealSupported:
        ("revealSupported" in surfaceShape) && surfaceShape.revealSupported
    signal revealFinished(bool opened)

    property list<QtObject> revealBindings: [
        Binding {
            target: ("revealEnabled" in root.surfaceShape) ? root.surfaceShape : null
            property: "revealEnabled"
            value: root.revealEnabled
        },
        Binding {
            target: ("revealOpened" in root.surfaceShape) ? root.surfaceShape : null
            property: "revealOpened"
            value: root.revealOpened
        },
        Binding {
            target: ("revealDuration" in root.surfaceShape) ? root.surfaceShape : null
            property: "revealDuration"
            value: root.revealDuration
        },
        Connections {
            target: root.surfaceShape
            ignoreUnknownSignals: true
            function onRevealFinished(opened) { root.revealFinished(opened) }
        }
    ]

    // Contrast scrim forwarded to the compositor alongside the shape. Tint
    // 0/1 is black/white. Decay 0..1 is adaptive; values above 1 select fixed
    // mode, where cap is the exact opacity.
    property bool scrimEnabled: false
    property int scrimTint: 0
    property real scrimCap: 0.0
    property real scrimDecay: 1.0

    // Per-shape blur override forwarded to the compositor (protocol v4).
    // Disabled keeps the shape on the window's default blur pipeline;
    // blurLevel is the compositor blur level 1..15, the same scale the global
    // kos-settings blur writes through.
    property bool blurEnabled: false
    property int blurLevel: 1

    // This object must not be placed in Region's default `regions` list: it
    // is protocol state, not an additional geometric primitive.
    property var surfaceShape: SurfaceShape {
        target: root.shapeItem
        radius: root.shapeRadius
        exponent: root.exponent
        enabled: root.shapeEnabled
        scrimEnabled: root.scrimEnabled
        scrimTint: root.scrimTint
        scrimCap: root.scrimCap
        scrimDecay: root.scrimDecay
        blurEnabled: root.blurEnabled
        blurLevel: root.blurLevel
    }

    // Guard the optional property so an installed older native bridge still loads.
    property var opacityBinding: Binding {
        target: ("materialOpacity" in root.surfaceShape) ? root.surfaceShape : null
        property: "materialOpacity"
        value: Math.max(0, Math.min(1, root.materialOpacity))
    }

    property var captureBinding: Binding {
        target: ("captureGeometry" in root.surfaceShape) ? root.surfaceShape : null
        property: "captureGeometry"
        value: root.item !== root.shapeItem ? root.itemRect : Qt.rect(0, 0, 0, 0)
    }
}
