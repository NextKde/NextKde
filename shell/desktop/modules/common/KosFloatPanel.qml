import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import "../../../Kos/Ui"

// Reusable important-interaction surface. One layer-shell surface carries both
// the backdrop underlay and the card. KWin only samples the surfaces *below* a
// blur, so a second surface would have supplied a sampling field rather than a
// visual layer -- and both consumers of this panel already carry their
// readability contract on the card's own fixed scrim. Staying in-surface also
// keeps one full-screen surface, and its damage, out of every open/close
// animation.
Scope {
    id: root

    default property alias content: cardHost.data
    readonly property alias glass: cardPanel
    property real contentPadding: 20
    property Item anchorItem: null
    property var targetScreen: ScreenLifecycle.activeScreen
    property bool centerOnScreen: false
    property bool modal: false
    property int floatOffset: 12
    // "none" | "dim" | "dimBlur". The underlay shares this panel's single
    // surface, so the card's own blur cannot sample it -- KWin only samples the
    // surfaces below a blur. "dimBlur" therefore widens this surface's blur
    // region to the whole screen instead of stacking a dimmed field under the
    // glass, and it cannot be combined with a per-card blur region.
    property string backdropMode: "none"
    readonly property bool backdropVisible: root.modal
        && root.backdropMode !== "none"
    readonly property bool backdropBlurActive: root.backdropVisible
        && root.backdropMode === "dimBlur"
    property real backdropOpacity: -1
    // A wash exists to push the desktop back, so it is dark in both appearances
    // rather than polarized against the final glass tone.
    property color backdropTint: "black"
    // An explicit backdropOpacity wins; otherwise the wash is lighter where the
    // screen it covers is already dark.
    readonly property real backdropEffectiveOpacity: root.backdropOpacity >= 0
        ? Math.min(1, root.backdropOpacity)
        : (AppearanceTokens.resolvedAppearanceIsDark ? 0.38 : 0.48)
    property bool dismissOnBackdrop: true
    // Important dialogs are a fixed-content, fixed-size family, so their corner
    // is a literal rather than a shape token: it holds still if the token scale
    // moves, and it is deliberately rounder than shape.extraLarge (26/30).
    property real radius: 32
    property real cornerExponent: AppearanceTokens.shape.cornerExponent
    // Outer shadow. It is cast entirely outside the card's outline (see
    // KosCardShadow): a translucent card cannot carry a shadow underneath
    // itself, because the glass would show that darkening through the material.
    property bool shadowEnabled: true
    property real shadowOffsetX: 12
    property real shadowOffsetY: 16
    property real shadowSoftness: 18
    property color shadowColor: Qt.rgba(0.5, 0.5, 0.5, 0.30)
    // 0 = real shadow. 1/2/3 paint the diagnostics described in KosCardShadow --
    // a probe is the only way to tell a clipped surface apart from a
    // mis-shaped or mis-wired one without guessing.
    property real shadowDebugMode: 0
    property int materialDepth: 1
    // "auto" follows appearance; important destructive prompts may request a
    // stable light or dark material independent of the desktop theme.
    property string materialTone: "auto" // "auto" | "light" | "dark"
    // Shared important-dialog material: neutral graphite in dark appearance,
    // warm pearl in light appearance. Individual dialogs may still override.
    property string fixedScrimTone: finalGlassIsDark ? "graphite" : "pearl"
    // One value for both appearances. Not fully opaque: the glass underneath is
    // part of the material, so the desktop reads through as a hint.
    property real fixedScrimOpacity: 0.8
    // The blur strength this panel asks the compositor for, published per shape
    // through protocol v4 set_blur instead of following the global kwinrc
    // BlurStrength -- a dialog wants less blur than the desktop surfaces do.
    property real blurStrength: 0.3
    readonly property bool finalGlassIsDark: materialTone === "dark" ? true
        : materialTone === "light" ? false
        : AppearanceTokens.resolvedAppearanceIsDark
    property color baseColor: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainer, (finalGlassIsDark ? "black" : "white"))
    property real surfaceOpacity: AppearanceTokens.surface.pick(AppearanceTokens.glass.materialOpacity, 1.0)
    property color ambientPrimary: WallpaperColorSource.primary
    property color ambientSecondary: WallpaperColorSource.secondary
    property real ambientStrength: 0.30 * AppearanceTokens.glass.ambientMultiplier
    // Content follows the requested final glass tone, not the generic glass
    // surface's legacy "always white" foreground policy.
    readonly property color contentForegroundColor: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(0.075, 0.07, 0.09, 0.96)
    readonly property color contentSecondaryColor: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(0.075, 0.07, 0.09, 0.70)
    readonly property color contentTertiaryColor: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.54) : Qt.rgba(0.075, 0.07, 0.09, 0.52)
    readonly property color contentControlFill: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.075)
    readonly property color contentControlBorder: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
    property bool animateOnShow: AppearanceTokens.motion.popupAnimatesOnShow
    property real startScale: AppearanceTokens.motion.popupStartScale
    property real anchorOffset: AppearanceTokens.motion.popupAnchorOffset

    property alias visible: cardWindow.visible
    readonly property bool requestedOpen: root.animateOnShow
        ? popupMotion.requestedOpen : cardWindow.visible
    readonly property alias width: cardWindow.width
    readonly property alias height: cardWindow.height
    readonly property bool _centered: root.centerOnScreen || root.modal

    signal aboutToShow()
    signal aboutToHide()
    signal backdropClicked()

    function show() {
        if (root.anchorItem && !root._centered)
            root._placeAnchored()
        cardWindow.visible = true
        if (root.animateOnShow)
            popupMotion.open()
    }
    function hide() {
        if (root.animateOnShow && cardWindow.visible) {
            popupMotion.close()
            return
        }
        cardWindow.visible = false
    }
    function open() { root.show() }
    function close() { root.hide() }
    function toggle() { root.requestedOpen ? root.hide() : root.show() }

    property real _anchorX: 0
    property real _anchorY: 0
    function _placeAnchored() {
        const g = root.anchorItem.mapToGlobal(0, 0)
        root._anchorX = Math.round(g.x - (cardWindow.x || 0))
        root._anchorY = Math.round(g.y - (cardWindow.y || 0)
                                   - cardPanel.height - root.floatOffset)
    }

    PanelWindow {
        id: cardWindow
        screen: root.targetScreen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-kosfloatpanel-overlay"
        WlrLayershell.keyboardFocus: root.modal && root.requestedOpen
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { top: true; left: true; right: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        visible: false

        // The underlay is drawn below the card in this same surface, so it is a
        // plain dim over the desktop rather than a field the card's glass
        // samples: KWin only samples the surfaces below a blur.
        Rectangle {
            id: backdrop
            anchors.fill: parent
            visible: root.backdropVisible
            color: Qt.rgba(root.backdropTint.r, root.backdropTint.g,
                root.backdropTint.b, root.backdropEffectiveOpacity)
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.modal && root.requestedOpen
            onClicked: {
                root.backdropClicked()
                if (root.dismissOnBackdrop)
                    root.close()
            }
        }

        // The card's shadow: a sibling *below* the card, never a backdrop for
        // it. Geometry mirrors the card exactly, motion included -- the same
        // scale and translate are re-stated here with the scale origin moved to
        // the card's top-left corner, which sits `margin` into this item.
        KosCardShadow {
            id: cardShadow
            castEnabled: root.shadowEnabled
            cardWidth: cardPanel.width
            cardHeight: cardPanel.height
            cornerRadius: cardPanel.radius
            cornerExponent: cardPanel.cornerExponent
            offsetX: root.shadowOffsetX
            offsetY: root.shadowOffsetY
            softness: root.shadowSoftness
            shadowColor: root.shadowColor
            debugMode: root.shadowDebugMode
            x: cardPanel.x - margin
            y: cardPanel.y - margin
            opacity: cardPanel.opacity
            transform: [
                Scale {
                    origin.x: cardShadow.margin
                    origin.y: cardShadow.margin
                    xScale: cardPanel.scale
                    yScale: cardPanel.scale
                },
                Translate {
                    y: (root.animateOnShow && popupMotion.progress < 0.999)
                        ? Math.round((1 - popupMotion.progress) * root.anchorOffset) : 0
                }
            ]
        }

        LiquidGlassPanel {
            id: cardPanel
            z: 1
            radius: root.radius
            cornerExponent: root.cornerExponent
            materialDepth: root.materialDepth
            material: "thick"
            baseColor: root.baseColor
            surfaceOpacity: root.surfaceOpacity
            // A dialog is a decision surface: a table of buttons over the
            // desktop, not a window onto it. In a tonal shell the plate is the
            // only thing the desktop could read through, and the tonal branch
            // ignores the `surfaceOpacity` above -- this is the knob that
            // reaches it. The compositor scrim stays wired and is simply
            // covered: KWin draws the backdrop before the client content.
            tonalOpacity: 1.0
            ambientPrimary: root.ambientPrimary
            ambientSecondary: root.ambientSecondary
            ambientStrength: root.ambientStrength
            useKwinEffect: true
            // Publish our own blur level to the compositor (protocol v4 set_blur);
            // no other surface in the shell opts in, so dialogs stop inheriting the
            // global BlurStrength while everything else keeps following it.
            blurOverrideEnabled: true
            blurStrength: root.blurStrength
            scrimEnabled: true
            scrimLevel: "custom"
            // Important interactions prioritize legibility. The host may make
            // the full-screen backdrop completely transparent; a strong
            // theme-polarized KWin scrim then carries the contrast contract.
            scrimCap: root.fixedScrimOpacity
            scrimDecay: 1.0
            scrimFixed: true
            scrimGraphite: root.fixedScrimTone === "graphite"
            scrimPearl: root.fixedScrimTone === "pearl"
            scrimTintOverride: root.finalGlassIsDark ? 0 : 1

            width: cardHost.width + root.contentPadding * 2
            height: cardHost.height + root.contentPadding * 2
            x: root._centered
                ? Math.round((cardWindow.width - width) / 2) : root._anchorX
            y: root._centered
                ? Math.round((cardWindow.height - height) / 2) : root._anchorY
            scale: (root.animateOnShow && popupMotion.progress < 0.999)
                ? root.startScale + (1 - root.startScale) * popupMotion.progress : 1
            transformOrigin: Item.Top
            opacity: root.animateOnShow ? popupMotion.progress : 1
            enabled: !root.animateOnShow || popupMotion.interactive
            transform: Translate {
                y: (root.animateOnShow && popupMotion.progress < 0.999)
                    ? Math.round((1 - popupMotion.progress) * root.anchorOffset) : 0
            }

            Column {
                id: cardHost
                anchors.centerIn: parent
                width: childrenRect.width
                height: childrenRect.height
                spacing: 8
            }
        }

        mask: !root.requestedOpen ? emptyInputRegion : (root.modal ? null : cardRegion)
        Region { id: emptyInputRegion }
        Region { id: cardRegion; item: cardPanel }
        Region { id: backdropBlurRegion; item: backdrop }
        // One surface carries one blur region, so "dimBlur" widens this one to
        // the whole screen -- which already covers the card.
        // No form is excluded: a tonal card asks the compositor for the same
        // frost and publishes no SurfaceShape to go with it.
        BackgroundEffect.blurRegion: (cardWindow.visible
                                      && cardPanel.useKwinEffect)
            ? (root.backdropBlurActive ? backdropBlurRegion : cardPanel.blurRegion)
            : null
    }

    PopupMotion {
        id: popupMotion
        onClosed: {
            if (!popupMotion.requestedOpen)
                cardWindow.visible = false
        }
    }

    Connections {
        target: cardWindow
        function onVisibleChanged() {
            if (cardWindow.visible)
                root.aboutToShow()
            else
                root.aboutToHide()
        }
    }
}
