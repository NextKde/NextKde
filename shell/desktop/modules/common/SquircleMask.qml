import QtQuick

// Superelliptical corner mask for a layered item.
//
//   Rectangle {
//       id: card
//       layer.enabled: card.cornerExponent > 2.0
//       layer.effect: SquircleMask {
//           cornerRadius: card.radius
//           cornerExponent: card.cornerExponent
//           maskWidth: card.width
//           maskHeight: card.height
//       }
//   }
//
// Most surfaces no longer write this by hand: LiquidGlassPanel applies the mask
// to its own subtree and forwards the outline, so all a caller needs there is a
// cornerExponent above 2. What is left here are surfaces that own their fill --
// the lock screen's notification card is the only remaining caller.
//
// The field is the same implicit function as Squircle.mjs, and the same one the
// compositor masks glass with for a surface that declares its shape through
// kos-surface-shape-v1, so the content edge and the glass edge describe one
// outline instead of two.
//
// The host has to hand over two things it cannot keep:
//
//   - Children must render unrounded (radius 0). Rounding them as well as the
//     mask rounds the surface twice.
//   - Rectangle.border cannot be used. A straight border is cut off wherever
//     the mask's corner arc departs from the rectangle edge, so pass the
//     outline through borderWidth / borderColor and this shader draws it along
//     the same field, corners included.
//
// Anti-aliasing is the compositor's own footprint (1 - clamp(0.5 +
// f / fwidth(f))). Because that is a ratio it normalises away the field's
// gradient length, so the ramp stays one pixel wide across a straight edge and
// sqrt(2) pixels at 45 degrees for every exponent -- raising the exponent costs
// nothing in edge quality, and there is no tessellated path to facet. That is
// the whole reason to shape with an SDF rather than a ShapePath; see
// test_squircle.mjs, which measures the ramp.
//
// Painted by shaders/squircle.frag. Keep it in sync with Squircle.mjs.
ShaderEffect {
    id: root

    // Bound by the layer: Item.layer.samplerName defaults to "source".
    property variant source

    // The design token. Exponent 2 leaves the corners circular, so a host can
    // switch this component off without changing the radius it passes.
    property real cornerRadius: 0
    property real cornerExponent: 2.0

    // Pass the host's size explicitly. Binding the effect's own width/height
    // works too, but a qualified reference cannot silently pick up the wrong
    // object when the call site is nested.
    property real maskWidth: width
    property real maskHeight: height

    // Outline drawn by the field, in pixels, measured inward from the edge.
    // Left at 0 the shader does no outline work at all.
    property real borderWidth: 0
    property color borderColor: "transparent"

    fragmentShader: Qt.resolvedUrl("../../shaders/squircle.frag.qsb")
}
