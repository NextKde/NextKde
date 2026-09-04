import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock

// A single control-center card as an independent PopupWindow.
//
// Each card owns a full-window RoundedBlurRegion, so KWin's per-window blur
// applies to this card alone (the compositor samples whatever is actually
// behind the window - wallpaper AND open windows). The plugin's
// smoothQuickshellCard path rounds the whole window with an SDF mask (no
// scanline aliasing), and the gaps between card windows show the real
// desktop underneath - the iOS "hollow" control center look.
//
// Positioning: every card anchors to the transparent geometry oracle, so the
// clicked control determines the output, edge, and compositor clamping.
PopupWindow {
    id: root

    // ── Grid position (relative to coordinator.panelTop / panelRight) ──
    // Vertical offset from the control center's top edge (logical px).
    property int offsetTop: 0
    // Horizontal offset from the control center's right edge (logical px,
    // negative = further left).
    property int offsetRight: 0
    // Corner radius for the blur region and the visual border.
    property real cardRadius: 19
    // Visual card fill (above the blur).
    property color cardColor: ThemeService.backgroundColor
    property color cardBorderColor: Qt.rgba(1, 1, 1, 0.20)
    // Available to card content that needs locally adaptive foreground ink.
    readonly property color materialForegroundColor: cardGlass.foregroundColor
    readonly property color materialSecondaryForegroundColor: cardGlass.secondaryForegroundColor
    // PanelWindow has no opacity; this applies to the card body instead.
    property real cardOpacity: 1.0
    // PanelWindow has no scale; this applies to the card content.
    property real cardScale: 1.0

    // ── Wire-up (set by the bar) ──
    required property QtObject coordinator
    // Cards managed by the coordinator open/close together. Set false for
    // overlays that manage their own visibility (e.g. logout confirmation).
    property bool managedByCoordinator: true
    property bool cardShown: false
    readonly property real motionProgress: root.managedByCoordinator
        ? (root.coordinator?.motionProgress ?? 0) : ownMotion.progress
    readonly property bool motionMapped: root.managedByCoordinator
        ? (root.coordinator?.motionMapped ?? false) : ownMotion.mapped
    readonly property bool motionInteractive: root.managedByCoordinator
        ? (root.coordinator?.motionInteractive ?? false) : ownMotion.interactive
    readonly property bool effectiveShown: root.cardShown && root.motionMapped
    readonly property real popupScale: AppearanceTokens.motion.popupStartScale
        + (1 - AppearanceTokens.motion.popupStartScale) * root.motionProgress
    readonly property bool visuallySuppressed: root.managedByCoordinator
        && (root.coordinator?.modalActive ?? false)
    signal motionClosed()

    color: "transparent"
    grabFocus: false
    // Keep the popup surface allocated while this control-center instance is
    // loaded. Closing moves the anchor point off screen instead of switching
    // `visible`, so the blur region remains stable through the transition.
    visible: root.coordinator?.cardAnchor !== null

    anchor {
        item: root.coordinator?.cardAnchor ?? null
        rect.x: (root.coordinator?.gridWidth ?? 336) - root.offsetRight
            - root.cardWidth + (root.coordinator?.cardOffsetX ?? 0)
        rect.y: root.effectiveShown
            ? root.offsetTop + (root.coordinator?.cardOffsetY ?? 0)
            : -2000
        rect.width: 0
        rect.height: 0
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        // Hidden cards use a deliberately off-screen anchor. Do not let the
        // popup placement engine slide that point back on-screen, otherwise
        // independent sub-panels (such as Power & Session) remain visible.
        adjustment: PopupAdjustment.None
    }

    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight

    // Set by each concrete card.
    property int cardWidth: 296
    property int cardHeight: 59

    // The blur radius as an integer, shared by the region encoding AND the
    // cardBody radius so the plugin's SDF mask and the QML drawn shape always
    // coincide (a mismatch is what produced the visible double-edge aliasing).
    readonly property int blurRadius: Math.max(1, Math.min(
        Math.round(root.cardRadius),
        Math.floor(Math.min(root.cardWidth, root.cardHeight) / 2)))

    property real blurStrength: AppearanceConfigService.effectiveBarBlur
    property real liquidStrength: AppearanceConfigService.effectiveBarLiquid
    readonly property real effectiveBlur: Math.max(0.0, Math.min(1.0, blurStrength))
    readonly property real effectiveLiquid: Math.max(0.0, Math.min(1.0, liquidStrength))

    // Blur region with the radius encoded explicitly, instead of
    // RoundedBlurRegion's ellipse scanlines (whose top-row inset is corrupted
    // by DPR scaling, making the plugin recover a smaller radius than QML
    // draws). The top scanline starts at x=blurRadius - the plugin's
    // smoothQuickshellCard reads exactly this inset as the corner radius.
    // Everything below it is full-width so the card blurs completely and the
    // SDF mask rounds the corners to blurRadius.
    BackgroundEffect.blurRegion: (root.visible
        && (root.effectiveBlur > 0.005 || root.effectiveLiquid > 0.005))
        ? cardBlurRegionHolder : null

    Region {
        id: cardBlurRegionHolder
        x: root.blurRadius
        y: 0
        width: root.cardWidth - root.blurRadius
        height: 1
        Region {
            x: 0
            y: 1
            width: root.cardWidth
            height: root.cardHeight - 1
        }
    }

    // Card surface: LiquidGlassSurface provides liquid finish, ambient wallpaper reflections,
    // and responsive opacity tied to effectiveBlur and effectiveLiquid.
    LiquidGlassSurface {
        id: cardGlass
        anchors.fill: parent
        radius: root.blurRadius
        baseColor: root.cardColor
        surfaceOpacity: root.cardOpacity
        blurStrength: root.effectiveBlur
        liquidStrength: root.effectiveLiquid
        ambientPrimary: WallpaperPaletteService.primary
        ambientSecondary: WallpaperPaletteService.secondary
        ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
        material: "regular"
        border.width: 1
        border.color: root.cardBorderColor
        scale: root.popupScale
        transformOrigin: Item.TopRight
        opacity: root.motionProgress * (root.visuallySuppressed ? 0.55 : 1.0)
        enabled: root.motionInteractive && !root.visuallySuppressed
        transform: Translate {
            y: (1 - root.motionProgress) * AppearanceTokens.motion.popupAnchorOffset
        }

        // Concrete card content (declared by the card instance).
        default property alias content: contentHost.data
        Item {
            id: contentHost
            anchors.fill: parent
            scale: root.cardScale
        }
    }

    Component.onCompleted: {
        if (root.managedByCoordinator) {
            if (root.coordinator)
                root.coordinator.register(root)
        }
    }

    onCardShownChanged: {
        if (!root.managedByCoordinator) {
            if (root.cardShown)
                ownMotion.open()
            else
                ownMotion.close()
        }
    }

    property PopupMotion ownMotion: PopupMotion {
        onClosed: root.motionClosed()
    }
}
