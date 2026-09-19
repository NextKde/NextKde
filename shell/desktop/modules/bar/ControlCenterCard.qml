import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"

// Control-center card container for the single-block panel (experiment).
//
// A card is no longer its own window, but it keeps real KWin glass: each card
// is a LiquidGlassPanel with useKwinEffect:true, publishing its own
// SurfaceShape. The panel window's single BackgroundEffect region is built as
// the UNION of every card's blurRegion, so KWin blurs behind the cards but not
// over the gaps between them -- hollow, frosted, and still one window with no
// ControlCenterCoordinator.
Item {
    id: root

    // ── Grid position & size (top-right origin, matching the old coordinator) ──
    property int offsetTop: 0
    property int offsetRight: 0
    property int cardWidth: 296
    property int cardHeight: 59
    property real cardRadius: AppearanceTokens.isMaterial
        ? AppearanceTokens.shape.large : 19
    property color cardColor: ThemeService.backgroundColor
    // Readability scrim for this card's glass: one step above the Dock, which
    // sits at "subtle". Widgets hosting white content can raise it further
    // (widgets use "readable") so text holds over a bright backdrop.
    property string cardScrimLevel: "transparent"
    property color cardBorderColor: AppearanceTokens.isMaterial
        ? AppearanceTokens.colors.outline : Qt.rgba(1, 1, 1, 0.20)
    property real cardOpacity: 1.0
    property real cardScale: 1.0
    // Hosts with their own tonal fill can still use this item solely to
    // publish a KWin blur shape, without stacking a second QML material.
    property bool fallbackEnabled: AppearanceTokens.isMaterial

    // Inert compatibility from the old per-window card; each card now draws its
    // own glass, so these are retained only so existing instances compile.
    property var coordinator: null
    property real blurStrength: 1.0
    property real liquidStrength: 0.0
    property bool managedByCoordinator: true

    // Marker for the single-block panel's positioning pass.
    readonly property bool isControlCenterCard: true
    // Host shows/hides a card (submenus and the session sheet toggle this).
    property bool cardShown: true

    // The item whose x/y are this card's position in the surface. Defaults to
    // the card itself (fine when placed directly in the panel window, as
    // ControlCenterPanel.placeCard does). A card embedded in an outer wrapper
    // whose own x/y carry the surface offset (the desk widgets) must point this
    // at that wrapper -- the glass fills this card at local (0,0), and
    // RoundedBlurRegion reads item.x/y verbatim, so a zero-positioned card
    // would misplace the blur region to the window origin.
    property Item blurAnchor: root

    // Content's adaptive foreground ink, from this card's glass.
    readonly property color materialForegroundColor: cardGlass.foregroundColor
    readonly property color materialSecondaryForegroundColor:
        cardGlass.secondaryForegroundColor
    readonly property color materialTertiaryForegroundColor:
        cardGlass.tertiaryForegroundColor

    width: cardWidth
    height: cardHeight
    visible: root.cardShown

    // This card's exact compositor shape, used by the panel to build the
    // single window blur region (the union of all cards).
    readonly property alias blurRegion: cardGlass.blurRegion

    // The card's own KWin-backed glass. useKwinEffect publishes this card's
    // SurfaceShape; the panel window's BackgroundEffect region is the union of
    // these, so KWin blurs behind the cards and leaves the gaps crisp. A
    // tonal/non-glass theme has no backdrop to sample, so it draws the QML
    // surface instead of publishing a shape nothing would render -- the panel
    // gates its region on the same token, which keeps the declared shape set and
    // the region in step.
    LiquidGlassPanel {
        id: cardGlass
        anchors.fill: parent
        useKwinEffect: AppearanceTokens.surface.usesKwinBlur
        fallbackEnabled: root.fallbackEnabled
        // The glass fills this card at local (0,0); its region must land where
        // the card actually sits in the window, so anchor it to the positioned
        // card Item (whose x/y carry the grid offset) instead of the glass.
        // root.blurAnchor defaults to this card; a wrapper-embedded card (the
        // desk widgets) overrides it to point at the wrapper that holds the
        // true surface offset.
        blurAnchor: root.blurAnchor
        radius: Math.max(1, Math.min(
            Math.round(root.cardRadius),
            Math.floor(Math.min(root.cardWidth, root.cardHeight) / 2)))
        cornerExponent: 2.0
        baseColor: root.cardColor
        surfaceOpacity: root.cardOpacity
        // Same see-through scrim posture as the Dock: on, at the subtle level.
        scrimEnabled: AppearanceTokens.surface.usesBackdrop
        scrimLevel: root.cardScrimLevel
        ambientPrimary: WallpaperColorSource.primary
        ambientSecondary: WallpaperColorSource.secondary
        ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
        material: "regular"

        // Concrete card content (declared by the card instance), above the glass.
        default property alias content: cardContent.data
        Item {
            id: cardContent
            anchors.fill: parent
            visible: root.cardOpacity > 0.001
            scale: root.cardScale
        }
    }
}
