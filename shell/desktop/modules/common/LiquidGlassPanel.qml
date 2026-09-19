import QtQuick

// A surface-shaped content panel. KWin Glass owns the visual glass finish.
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
// At cornerExponent 2.0 every masked path is off. The mask only turns on above
// it, so raising the exponent is the whole opt-in.
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

    // The exact compositor declaration for this surface. A window that owns a
    // BackgroundEffect publishes this object (or combines several of them);
    // the panel itself remains unaware of window-level effect policy. It is
    // null when the panel falls back to its own QML liquid, so a host binding
    // `BackgroundEffect.blurRegion: panel.blurRegion` publishes nothing.
    readonly property var blurRegion: root.useKwinEffect ? surfaceRegion : null
    // Item whose x/y already are this panel's position in the surface. A panel
    // that fills a positioned wrapper (the Dock's capsule, the launcher card)
    // anchors to it, so its own x/y read 0 wherever the glass sits; point this
    // at the wrapper, whose x/y carry that offset. Defaults to the panel.
    property Item blurAnchor: root

    // ---- KWin vs QML rendering ------------------------------------------

    // True: KWin Glass owns blur, refraction and highlights; this panel
    // publishes a compositor blur region + SurfaceShape and paints no material.
    // False: the panel falls back to its own QML liquid finish through
    // LiquidGlassSurface and publishes nothing to the compositor. Item-level
    // glass inside a shared surface -- the desk-center widgets -- uses this,
    // because per-item compositor blur is not present on that surface.
    property bool useKwinEffect: true
    // Opt-in: publish this panel's own blur strength to the compositor (protocol
    // v4 set_blur) instead of following the global kwinrc BlurStrength. Off by
    // default, so every existing surface keeps the global level and renders
    // exactly as it did before.
    property bool blurOverrideEnabled: false
    // The level asked for when the override is on. It defaults to the shell-wide
    // value, so an override that follows the global setting renders identically to
    // no override at all.
    property real blurStrength: AppearanceConfigService.effectiveDockBlur

    // The edge is owned by KWin's liquid rim, which adapts its light colour
    // (white over dark, dark gold over bright) per backdrop. No client-side
    // outline is drawn here, so there is no separate border to drift from the
    // glass silhouette.

    // Which form this panel belongs to, from the surface policy. A tonal form
    // paints its own card and asks the compositor only for the backdrop frost;
    // a glass form hands the whole finish to KWin. Nothing below branches on the
    // shell style itself.
    readonly property bool tonal: AppearanceTokens.surface.paintInQml

    // A tonal form has no compositor glass treatment, so it keeps a plain QML
    // surface. In every glass form this panel paints no material at all: KWin is
    // the sole owner of blur, refraction and highlights.
    property bool fallbackEnabled: AppearanceTokens.surface.paintInQml

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
    // Contrast scrim owned by the compositor: a black or white tint whose
    // opacity the glass scales to the backdrop it sits on, so light text over
    // a bright wallpaper (black tint) and dark text over a dark one (white
    // tint) both stay legible.
    property bool scrimEnabled: false
    // Named readability/transparency tradeoff, expressed as how far the scrim
    // is allowed to ramp at the backdrop extreme:
    //   "subtle"      a hint at most, keeps the surface almost fully see-through,
    //   "transparent" keeps most see-through (dock capsule, toolbars),
    //   "balanced"    sits mid-way,
    //   "readable"    will fill in near-opaque to hold text (notifications),
    //   "custom"      falls back to the explicit scrimCap/scrimDecay below.
    property string scrimLevel: "transparent"
    // What cap and decay mean at the shader:
    //
    //   amount = smoothstep(0.40, 0.85, damage)   // 0..1, from backdrop luminance
    //   alpha  = clamp(max(amount * decay, 0.06 * cap), 0.0, cap)
    //
    // cap is the absolute ceiling on scrim opacity -- how solid the fill is ever
    // allowed to become at the extreme, regardless of how bright/dark the
    // backdrop is. decay is a per-surface calm factor that scales the curve down
    // earlier (below the ceiling); it governs the mid-tone ramp, not the max,
    // because cap always bites at the extreme. Every preset keeps cap < decay so
    // cap stays the real maximum and decay only slows the approach to it.
    // The 0.06*cap floor keeps a scrim from collapsing fully to invisible on a
    // backdrop that already matches the tint; it scales with cap so see-through
    // levels stay nearly transparent while readable ones hold a faint presence.
    // A scrim that reaches this floor on a matching backdrop reverses to a fixed
    // 10% opposite tint (white -> black, black -> white); it never follows the
    // curve upward after reversing.
    property real scrimCap: 0.5
    property real scrimDecay: 1.0
    // The tint is owned by the panel, not passed in by a host. It follows the
    // "liquid glass follows appearance mode" switch: when on, a light
    // appearance picks a white tint (so dark content stays legible on a bright
    // backdrop) and a dark appearance a black tint; when the switch is off the
    // tint is fixed black.
    // Override values: 0 = black, 1 = white.
    property int scrimTintOverride: -1
    // Fixed mode uses scrimCap as exact opacity and never samples/reverses for
    // backdrop luminance. Encoded as decay 2 on the v3 wire request so an old
    // compositor safely degrades it to adaptive decay 1.
    property bool scrimFixed: false
    property bool scrimGraphite: false
    property bool scrimPearl: false
    readonly property int scrimTint: scrimTintOverride >= 0
        ? scrimTintOverride
        : (AppearanceConfigService.glassFollowsAppearanceMode
            ? (AppearanceTokens.isDarkTheme ? 0 : 1)
            : 0) // 0 = black, 1 = white

    // Named presets concretize the readability/transparency tradeoff as one
    // ceiling (cap) plus a per-surface calm factor (decay). "custom" ignores
    // these and takes the explicit scrimCap/scrimDecay verbatim.
    readonly property real _presetCap: scrimLevel === "readable" ? 0.72
        : scrimLevel === "balanced" ? 0.47
        : scrimLevel === "transparent" ? 0.22
        : scrimLevel === "subtle" ? 0.15 : 0.5
    readonly property real _presetDecay: scrimLevel === "readable" ? 1.0
        : scrimLevel === "balanced" ? 0.75
        : scrimLevel === "transparent" ? 0.5
        : scrimLevel === "subtle" ? 0.45 : 1.0
    readonly property real _effectiveScrimCap:
        scrimLevel === "custom" ? scrimCap : _presetCap
    readonly property real _effectiveScrimDecay:
        scrimLevel === "custom" ? scrimDecay : _presetDecay

    property bool bottomEdgeVisible: true
    property bool bottomShadeVisible: true

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

    // Keep the approximate integer blur mask and exact compositor shape in
    // lockstep. Consumers only need `panel.blurRegion`; they never duplicate
    // radius, exponent, or a SurfaceShape declaration beside the panel.
    KosRoundedBlurRegion {
        id: surfaceRegion
        item: root.blurAnchor
        radius: root.radius
        exponent: root.cornerExponent
        // A tonal form publishes no SurfaceShape. The declaration can only
        // describe a rectangle with rounded corners, and KWin paints a surface's
        // material from it -- so leaving it on hands a self-painted card the
        // liquid finish it exists without. Dropping it leaves only the blur
        // region above, which is exactly the frost a tonal card asks for.
        shapeEnabled: root.visible && root.useKwinEffect && !root.tonal
        scrimEnabled: root.scrimEnabled
        scrimTint: root.scrimTint
        scrimCap: root._effectiveScrimCap
        scrimDecay: root.scrimPearl ? 4.0
            : (root.scrimGraphite ? 3.0
            : (root.scrimFixed ? 2.0 : root._effectiveScrimDecay)
            )
        // Per-surface blur strength (protocol v4 set_blur). Silent unless the host
        // opts in, which is why every existing caller renders unchanged.
        blurEnabled: root.blurOverrideEnabled && root.useKwinEffect
        blurLevel: AppearanceConfigService.compositorBlurLevel(root.blurStrength)
    }

    LiquidGlassSurface {
        id: bodySurface
        anchors.fill: parent

        // The QML liquid fallback paints always when the host opts out of KWin
        // Glass; otherwise the body is the tonal-theme fallback only (KWin owns
        // the finish in every glass theme).
        visible: !root.useKwinEffect || root.fallbackEnabled

        // Square whenever the mask is on. The mask rounds the whole panel, and
        // rounding the fill as well would round it twice -- near the corner the
        // two arcs disagree and the fill pokes out of its own silhouette.
        radius: root.continuousCorners ? 0 : root.radius
        // Those two inset lines still need the visual radius, which radius no
        // longer carries once the mask is on.
        cornerInset: root.radius

        // No client-side border: the edge comes from KWin's liquid rim.
        border.width: 0
        border.color: "transparent"

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

        // KWin owns the finish: the body is a flat tonal fallback only. When
        // KWin is opted out, the body becomes the real QML liquid finish.
        liquidStrength: root.useKwinEffect
            ? 0.0 : AppearanceTokens.glass.liquidStrength
        blurStrength: root.useKwinEffect
            ? 1.0 : AppearanceTokens.glass.blurStrength
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
        borderWidth: 0
        borderColor: "transparent"
    }
}
