import QtQuick
import QtQuick.Effects
import qs.desktop.modules.common
import "./DockRevealGeometry.mjs" as DockRevealGeometry

// ────────────────────────────────────────────────────────────────
// DockRevealHandle — pure visual + pointer-input Home Indicator.
//
// Renders an iOS-style white pill on the screen edge and exposes an invisible
// hit target along the screen edge, optionally limited to the Dock's own span.
// It never reads services/configuration; the owning DockWindow supplies the
// layout, trigger mode and reveal state. See docs/DockArchitecture.md,
// "Visibility modes and auto-hide".
// ────────────────────────────────────────────────────────────────

Item {
    id: handle

    // ── Inputs ──
    property string position: "bottom"   // bottom | left | right
    property real windowWidth: 0         // owning surface size (logical px)
    property real windowHeight: 0
    // Stable full-reveal position in surface coordinates, not the animated
    // wrapper position. Side docks may be offset by the reserved top bar.
    property real dockX: 0
    property real dockY: 0
    // The dock glass's layout size, used for the edge target and hint centre.
    property real dockWidth: 0
    property real dockHeight: 0
    // In dockSpan mode, only widen across the floating gap after reveal starts.
    // Hidden and reveal-pending docks still require screen-edge contact.
    property bool expanded: false
    // Cross-fade opacity driven by the controller's reveal progress.
    property real fadeOpacity: 0.0       // 0..1
    // When false the whole handle is inert (zero-size hit target); used by the
    // "always" mode which must never swallow clicks near the edge.
    property bool active: true
    // Hiding the hint must not disable edge hover/click input.
    property bool showIndicator: true
    // Glass tint + outline matching the dock's own backdrop, so the hidden bar
    // reads as the same adaptive material. The owning window supplies the
    // theme colours; the backdrop blur (also owned by the window) adapts to
    // whatever is actually behind the bar.
    property color glassColor: "#b8ffffff"
    property color glassBorderColor: "#66ffffff"
    // Ambient pigment from the owning window's wallpaper palette, so the bar
    // reads as the same liquid material as the dock's popups/panels rather
    // than a flat white pill. The handle stays Service-free; the window wires
    // WallpaperColorSource into these.
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
    // The handle is a second liquid surface. Its panel owns the matching
    // rounded blur mask and SurfaceShape; DockWindow only combines it with the
    // main Dock surface when it publishes BackgroundEffect.blurRegion.
    // A fully faded hint has no native shape. Its blur region must disappear
    // too, otherwise KWin aligns the Dock against an invisible wider region.
    readonly property var blurRegion: bar.visible && bar.opacity > 0 ? pill.blurRegion : null

    readonly property bool vertical: handle.position !== "bottom"
    readonly property real visualThickness: 6
    readonly property real edgeInset: 6
    // DockWindow spans the full screen along its anchored edge. The hint uses
    // 50% of that screen dimension, independent of the Dock's content length.
    readonly property real barLength: Math.max(0, Math.round(
        (handle.vertical ? handle.windowHeight : handle.windowWidth) * 0.5))

    // ── Hit target geometry (in window/parent coordinates) ──
    // A 2px strip along the Dock's own edge span grows into a hold corridor
    // once reveal begins, so crossing the floating gap does not drop hover.
    readonly property var hitRect: DockRevealGeometry.revealHitRect({
        position: handle.position,
        windowWidth: handle.windowWidth,
        windowHeight: handle.windowHeight,
        dockX: handle.dockX,
        dockY: handle.dockY,
        dockWidth: handle.dockWidth,
        dockHeight: handle.dockHeight,
        active: handle.active,
        expanded: handle.expanded
    })
    readonly property real hitX: handle.hitRect.x
    readonly property real hitY: handle.hitRect.y
    readonly property real hitW: handle.hitRect.width
    readonly property real hitH: handle.hitRect.height

    // ── Visual bar geometry ──
    // Centre the hint on the Dock's stable full-reveal rectangle, so it always
    // tracks the glass (including a side Dock pushed down by the top bar).
    readonly property real barX: vertical
        ? (handle.position === "right" ? handle.windowWidth - handle.edgeInset - handle.visualThickness : handle.edgeInset)
        : (handle.dockX + (handle.dockWidth - handle.barLength) / 2)
    readonly property real barY: vertical
        ? (handle.dockY + (handle.dockHeight - handle.barLength) / 2)
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
                if (targetHover.hovered && parent.enabled)
                    handle.entered()
                else if (!targetHover.hovered)
                    // Disabling an empty/inactive target must release any hold.
                    handle.exited()
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
        visible: handle.active && handle.showIndicator && handle.visualThickness > 0
        opacity: handle.fadeOpacity

        scale: targetHover.hovered ? 1.08 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        // The liquid-glass Home Indicator is a second LiquidGlassPanel. It
        // carries its own shaped compositor declaration, which DockWindow
        // aggregates with the main Dock panel.
        LiquidGlassPanel {
            id: pill
            anchors.fill: parent
            radius: Math.min(handle.visualThickness, handle.barLength) / 2
            // Match the Dock's softened capsule profile.
            cornerExponent: 2.35
            // The pill fills its positioned crate; anchor the region to that
            // crate so x/y carry the handle's offset in the surface.
            blurAnchor: bar
            baseColor: handle.barBaseColor
            surfaceOpacity: 1.0
            ambientPrimary: handle.ambientPrimary
            ambientSecondary: handle.ambientSecondary
            ambientStrength: handle.ambientStrength
            materialDepth: handle.materialDepth
            material: "clear"
            ambientTransitionDuration: 600
            bottomEdgeVisible: true
            // The handle is a small high-contrast affordance: its readability
            // must not depend on the wallpaper. A stronger independent scrim
            // keeps the hint legible while preserving backdrop adaptation.
            scrimEnabled: true
            scrimLevel: "custom"
            scrimCap: 0.90
            scrimDecay: 1.0
        }
    }
}
