import QtQuick
import Kos.SurfaceShape 1.0

// A glass panel whose shape, material and finish are all decided by its caller.
//
// This exists beside LiquidGlassSurface rather than replacing it, and the
// difference is where the paint lives. LiquidGlassSurface is a Rectangle, so
// its radius, its colour and its border belong to whoever instantiates it -- a
// consumer binding outranks an internal one. That is harmless while corners are
// circular, because fill and outline are both Rectangle properties then. It
// stops being harmless the moment the corner becomes a superellipse: no
// Rectangle.radius draws one, so the shape has to become a mask, and the mask
// has to cover the fill it is shaping. Suspended from a Rectangle the mask
// cannot win that contest -- the very binding it needs to survive is the one
// the host is entitled to overwrite.
//
// Here the host sets radius on an Item that paints nothing, the fill sits in a
// child, and the only reader of radius is the mask. Nothing competes.
//
//   LiquidGlassPanel {
//       anchors.fill: parent
//       radius: AppearanceTokens.shape.large
//       cornerExponent: AppearanceTokens.shape.cornerExponent
//       Text { anchors.centerIn: parent; text: "hello" }
//   }
//
// At cornerExponent 2.0 every masked path is off: the body keeps a plain
// Rectangle.radius, the outline is a native border, and the panel renders what
// LiquidGlassSurface would have rendered on its own. The mask only turns on
// above it, so raising the exponent is the whole opt-in.
//
// Two switches, deliberately orthogonal:
//
//   liquidEnabled  the finish -- specular highlight, wallpaper pigment, the
//                  inset edge lines, the bottom shade. Off leaves flat glass.
//   blurEnabled    whether anything blurs what sits behind the panel. On, the
//                  fill is translucent so the backdrop shows through. Off,
//                  fallbackColor becomes the surface, because translucent over
//                  nothing is unreadable. The blur region itself is still
//                  published by the shell through RoundedBlurRegion, which this
//                  component neither knows about nor touches.
Item {
    id: root

    // ---- shape ----------------------------------------------------------

    property real radius: 0

    // Corner continuity, not corner size. 2.0 is the circular arc the shell has
    // always drawn; above it the corner sweeps towards the continuous-curvature
    // profile while the straight edge stays exactly where it was. The geometry
    // is Squircle.mjs / squircle.frag, so this edge and -- once the compositor
    // follows -- the glass behind it describe one outline instead of two.
    property real cornerExponent: 2.0
    readonly property bool continuousCorners: cornerExponent > 2.0

    // ---- outline --------------------------------------------------------

    // Measured inward from the edge, in pixels. Above exponent 2 the mask draws
    // it along the same field as the silhouette, so it follows the corner
    // instead of being cut off by it; Rectangle.border cannot do that. At
    // exponent 2 the field is a rounded rectangle, so a native border is both
    // correct and cheaper, and that is where it goes.
    property real outlineWidth: 0
    property color outlineColor: AppearanceTokens.colors.outline

    // ---- switches -------------------------------------------------------

    property bool liquidEnabled: true
    property bool blurEnabled: true
    // A compositor-backed panel receives its finish from KWin Glass. Keeping
    // the QML reflection active there would draw a second highlight on top.
    // When there is no compositor backdrop, the QML finish remains the visual
    // fallback instead.
    readonly property bool compositorOwnsFinish: root.blurEnabled
        && !AppearanceTokens.isMaterial
    // Defaults follow the shell's glass settings; a host overrides them for its
    // own surface class (launcher, bar, dock) exactly as it does today.
    property real liquidStrength: AppearanceTokens.glass.liquidStrength
    property real blurStrength: AppearanceTokens.glass.blurStrength

    // ---- material -------------------------------------------------------

    property color baseColor: Qt.rgba(0, 0, 0, 0.1)
    property color ambientPrimary: "transparent"
    property color ambientSecondary: "transparent"
    property real ambientStrength: 0.0
    property int ambientTransitionDuration: 2600
    property string material: "regular" // "clear", "regular", "thick"
    // 0 = dock/base surface, 1 = popup, 2 = contextual foreground menu.
    property real materialDepth: 0.0
    property real surfaceOpacity: 1.0
    property bool adaptiveDarkScrim: false
    property bool bottomEdgeVisible: true
    property bool bottomShadeVisible: true

    // What is painted instead of the glass when blurEnabled is false, i.e. the
    // fill a host uses when it knows there is nothing behind the panel to blur.
    // The tonal surface roles are a sane default, but a host with a tonal
    // identity of its own -- the Dock's layer0 at half opacity -- passes that
    // instead, and the body steps aside so it survives (see below).
    property color fallbackColor: material === "thick"
        ? AppearanceTokens.colors.layer2 : AppearanceTokens.colors.layer1

    // ---- content --------------------------------------------------------

    // Everything the caller writes between the braces lands here, above the
    // glass. It is an ordinary Item, so a panel with no explicit content is
    // still a valid panel.
    default property alias content: contentHost.data

    // The material itself, so a host can reach anything the surface exposes
    // that is not forwarded below.
    readonly property alias glass: bodySurface

    // The text roles LiquidGlassSurface derives from the fill it ended up with,
    // forwarded because content sits above the glass and has to read against
    // it. Without these a host would have to spell `glass.foregroundColor`,
    // which is noise at every call site.
    readonly property color foregroundColor: bodySurface.foregroundColor
    readonly property color secondaryForegroundColor:
        bodySurface.secondaryForegroundColor
    readonly property color tertiaryForegroundColor:
        bodySurface.tertiaryForegroundColor

    // The radius a full-bleed child should carry, so that it is rounded
    // exactly when the panel is. With the mask off that is the panel's own
    // radius; with it on it is zero, because the mask rounds the whole layer --
    // child included -- and a second, circular rounding near the corner would
    // stop the child short of the superelliptical silhouette it is meant to
    // fill, leaving a sliver of untinted glass at each corner.
    readonly property real contentRadius: continuousCorners ? 0 : radius

    // Native QML extension: publish this panel's exact surface-local geometry
    // and corner field to KWin. Multiple panels in one PopupWindow each own an
    // independent protocol object, so their radii never have to be inferred
    // from the integer Blur Region.
    SurfaceShape {
        target: root
        radius: root.radius
        exponent: root.cornerExponent
        enabled: root.visible && root.blurEnabled
    }

    // ---------------------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        radius: root.continuousCorners ? 0 : root.radius
        visible: !root.blurEnabled
        color: root.fallbackColor
    }

    LiquidGlassSurface {
        id: bodySurface
        anchors.fill: parent

        // In a tonal theme the body paints an opaque material fill of its own
        // (layer1 at alpha 1, see LiquidGlassSurface.color) rather than the
        // host's, which would bury fallbackColor and with it the host's tonal
        // identity. So there, and only there, a host that has declared there is
        // no backdrop makes the body stand down and the fallback becomes the
        // surface. In a glass theme the fill is already transparent at
        // blurStrength 0, so the body stays: a host that wants the finish
        // without the blur keeps it.
        visible: root.blurEnabled || !bodySurface.usesMaterialSurface

        // Square whenever the mask is on. The mask rounds the whole panel, and
        // rounding the fill as well would round it twice -- near the corner the
        // two arcs disagree and the fill pokes out of its own silhouette.
        radius: root.continuousCorners ? 0 : root.radius
        // Those two inset lines still need the visual radius, which radius no
        // longer carries once the mask is on.
        cornerInset: root.radius

        // A straight border is cut off wherever the corner departs from the
        // rectangle edge, so above exponent 2 the outline moves into the shader.
        border.width: root.continuousCorners ? 0 : root.outlineWidth
        border.color: root.outlineColor

        baseColor: root.baseColor
        ambientPrimary: root.ambientPrimary
        ambientSecondary: root.ambientSecondary
        ambientStrength: root.ambientStrength
        ambientTransitionDuration: root.ambientTransitionDuration
        material: root.material
        materialDepth: root.materialDepth
        surfaceOpacity: root.surfaceOpacity
        adaptiveDarkScrim: root.adaptiveDarkScrim
        bottomEdgeVisible: root.bottomEdgeVisible
        bottomShadeVisible: root.bottomShadeVisible

        // Strength 0 is exactly how LiquidGlassSurface turns a layer off: every
        // finish term is multiplied by normalizedLiquidStrength and the fill
        // alpha by normalizedBlurStrength, so zeroing them is the switch, not a
        // near-equivalent reimplementation of one.
        liquidStrength: root.liquidEnabled && !root.compositorOwnsFinish
            ? root.liquidStrength : 0.0
        blurStrength: root.blurEnabled ? root.blurStrength : 0.0
    }

    Item {
        id: contentHost
        anchors.fill: parent
    }

    // Fill and content are shaped together, so the content edge and the glass
    // edge are one outline rather than two that agree only by convention. That
    // is also why the body above is handed radius 0: children have to render
    // square for a mask to be the only thing rounding them.
    layer.enabled: root.continuousCorners
    layer.effect: SquircleMask {
        cornerRadius: root.radius
        cornerExponent: root.cornerExponent
        maskWidth: root.width
        maskHeight: root.height
        borderWidth: root.outlineWidth
        borderColor: root.outlineColor
    }
}
