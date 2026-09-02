import QtQuick
import QtQuick.Effects
import qs.desktop.modules.common

// ────────────────────────────────────────────────────────────────
// DockRevealHandle — pure visual + pointer-input Home Indicator.
//
// Renders an iOS-style white pill on the screen edge and exposes an invisible
// hit target large enough to catch a cursory pointer pass. It never reads any
// service/configuration; the owning DockWindow positions it inside the dock
// surface and feeds it state. See docs/DockArchitecture.md, "Visibility modes
// and auto-hide".
// ────────────────────────────────────────────────────────────────

Item {
    id: handle

    // ── Inputs ──
    property string position: "bottom"   // bottom | left | right
    property real windowWidth: 0         // owning surface size (logical px)
    property real windowHeight: 0
    // The dock glass's layout size. The pill length follows the dock's along
    // its own long edge (dockWidth on bottom, dockHeight on side) so the two
    // always stay proportional; the pill is a fixed fraction shorter.
    property real dockWidth: 0
    property real dockHeight: 0
    // Cross-fade opacity driven by the controller's reveal progress.
    property real fadeOpacity: 0.0       // 0..1
    // When false the whole handle is inert (zero-size hit target); used by the
    // "always" mode which must never swallow clicks near the edge.
    property bool active: true
    // Glass tint + outline matching the dock's own backdrop, so the hidden bar
    // reads as the same adaptive material. The owning window supplies the
    // theme colours; the backdrop blur (also owned by the window) adapts to
    // whatever is actually behind the bar.
    property color glassColor: "#b8ffffff"
    property color glassBorderColor: "#66ffffff"
    // Ambient pigment from the owning window's wallpaper palette, so the bar
    // reads as the same liquid material as the dock's popups/panels rather
    // than a flat white pill. The handle stays Service-free; the window wires
    // WallpaperPaletteService into these.
    property color ambientPrimary: "transparent"
    property color ambientSecondary: "transparent"
    property real ambientStrength: 0.0
    property real materialDepth: 0.5
    property color barBaseColor: Qt.rgba(1, 1, 1, 0.55)

    // ── Events ──
    signal entered()
    signal exited()
    signal clicked()

    // Exposed for the owning window's input mask: the (possibly zero-size)
    // hit area in window coordinates. The internal id is not visible outside
    // this component, so it is surfaced as a read-only alias.
    readonly property alias hitTarget: targetArea
    // The visible bar. It is a *direct* child of this handle (which sits at the
    // window origin), so its x/y already are surface coordinates — a blur region
    // can consume it without coordinate-space mapping.
    readonly property alias visualBar: bar
    // The pill filler, exposed only for diagnostics.
    readonly property alias visualPill: pill

    readonly property bool vertical: handle.position !== "bottom"
    readonly property real visualThickness: 6
    readonly property real hitThickness: 14
    readonly property real edgeInset: 6
    // The visual pill tracks the dock's own long edge (dockWidth on a bottom
    // dock, dockHeight on a side dock) at a fraction that keeps it always
    // slightly shorter than the dock, so a small dock shows a small pill and no
    // wide fixed 50%-of-screen bar leaves big blank edges around it.
    readonly property real barLength: Math.max(28, Math.round(
        (handle.vertical ? handle.dockHeight : handle.dockWidth) * (1.0 - handle.barInsetRatio)))
    readonly property real barInsetRatio: 0.20   // pill is 20% shorter than the dock

    // ── Hit target geometry (in window/parent coordinates) ──
    // The hit area spans the FULL edge (side: full height, bottom: full width),
    // so moving the pointer anywhere along the screen edge reveals the hidden
    // dock — not just over the (hint-only) visual pill. The pill stays a
    // dock-length-centred indicator; only the input region is widened.
    readonly property real hitX: vertical
        ? (handle.position === "right" ? handle.windowWidth - handle.hitThickness : 0)
        : 0
    readonly property real hitY: vertical
        ? 0
        : (handle.windowHeight - handle.hitThickness)
    readonly property real hitW: handle.active
        ? (handle.vertical ? handle.hitThickness : handle.windowWidth) : 0
    readonly property real hitH: handle.active
        ? (handle.vertical ? handle.windowHeight : handle.hitThickness) : 0

    // ── Visual bar geometry ──
    readonly property real barX: vertical
        ? (handle.position === "right" ? handle.windowWidth - handle.edgeInset - handle.visualThickness : handle.edgeInset)
        : ((handle.windowWidth - handle.barLength) / 2)
    readonly property real barY: vertical
        ? ((handle.windowHeight - handle.barLength) / 2)
        : (handle.windowHeight - handle.edgeInset - handle.visualThickness)

    // Transparent hit target. opacity:0 items still hit-test, so HoverHandler
    // reacts exactly over the mask region the DockWindow grants it.
    Item {
        id: targetArea
        x: handle.hitX
        y: handle.hitY
        width: handle.hitW
        height: handle.hitH
        enabled: handle.active && handle.hitW > 0 && handle.hitH > 0
        visible: true
        opacity: 0

        HoverHandler {
            id: targetHover
            enabled: parent.enabled
            onHoveredChanged: {
                if (parent.enabled)
                    targetHover.hovered ? handle.entered() : handle.exited()
            }
        }
        TapHandler {
            enabled: parent.enabled
            onTapped: handle.clicked()
        }
    }

    // Visual pill. Scale grows slightly and colour brightens on hover.
    Item {
        id: bar
        x: handle.barX
        y: handle.barY
        // Long axis runs along the screen edge: full barLength wide on a bottom
        // dock, barLength tall on a side dock (visualThickness is the cross-edge
        // thickness in both cases).
        width: handle.vertical ? handle.visualThickness : handle.barLength
        height: handle.vertical ? handle.barLength : handle.visualThickness
        visible: handle.active && handle.visualThickness > 0
        opacity: handle.fadeOpacity

        scale: targetHover.hovered ? 1.08 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        // The liquid-glass Home Indicator. LiquidGlassSurface gives the same
        // base + specular + wallpaper-ambient material as the dock's panels
        // (DockMusicPopup/DockWindowPreview) instead of a flat white pill; the
        // owning window's backdrop blur (barRegion) still frosts what is behind.
        LiquidGlassSurface {
            id: pill
            anchors.fill: parent
            radius: Math.min(handle.visualThickness, handle.barLength) / 2
            baseColor: handle.barBaseColor
            surfaceOpacity: 1.0
            ambientPrimary: handle.ambientPrimary
            ambientSecondary: handle.ambientSecondary
            ambientStrength: handle.ambientStrength
            materialDepth: handle.materialDepth
            ambientTransitionDuration: 600
            bottomEdgeVisible: true
        }
    }
}