import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"

// Control-center card container for the single-block panel (experiment).
//
// A card is no longer its own window, but it keeps real KWin glass: each card
// is a LiquidGlassPanel with useKwinEffect:true, publishing its own
// SurfaceShape. The panel window's single BackgroundEffect region is built as
// the UNION of every card's blurRegion, so KWin blurs behind the cards but not
// over the gaps between them -- hollow, frosted, and still one window.
Item {
    id: root
    default property alias content: cardContent.data

    // ── Grid position & size (top-right origin, matching the old coordinator) ──
    property int offsetTop: 0
    property int offsetRight: 0
    property int cardWidth: 296
    property int cardHeight: 59
    property real cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.large, 19)
    property color cardColor: ThemeService.backgroundColor
    // Embedded widgets can explicitly request a stronger readability scrim.
    // The control center and notification deck share the transparent recipe.
    property string cardScrimLevel: "transparent"
    property real cardOpacity: 1.0
    property real cardScale: 1.0
    property real contentOpacity: 1.0
    property real contentOffsetY: 0
    // Sub-page morph geometry. During a page transition the host animates a
    // card between its full rectangle and the source control it grew from
    // (the Wi-Fi pill, the brightness slider, ...). `morphRect` is the card's
    // current visible window in CARD coordinates: it starts at the full card
    // and shrinks toward the source. The glass and the blur region follow it,
    // while `cardContent` keeps its natural size and is clipped, so the card
    // reads as collapsing into the capsule instead of squashing its content.
    // A zero/empty rect means "no morph" and behaves exactly like before.
    property rect morphRect: Qt.rect(0, 0, -1, -1)
    readonly property rect _morph: morphRect.width > 0 && morphRect.height > 0
        ? morphRect : Qt.rect(0, 0, root.width, root.height)
    // Hosts with their own tonal fill can still use this item solely to
    // publish a KWin blur shape, without stacking a second QML material.
    property bool fallbackEnabled: AppearanceTokens.surface.paintInQml

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
    // Which navigation page this card belongs to. The panel multiplies the
    // card's opacity by that page's crossfade factor, so a card fades with
    // its page -- glass and content together. "" is the primary page.
    property string pageTag: ""
    // How opaque the KWin glass backing is, 0..1. The QML card Item's own
    // opacity never reaches the compositor blur/scrim shape, so a page fade
    // must drive this separately or the frosted silhouette lingers after the
    // content has already faded out. 1 keeps every non-animated card exact.
    property real glassOpacity: 1.0
    property real backdropScale: 1

    // The item whose x/y are this card's position in the surface. Defaults to
    // the card itself (fine when placed directly in the panel window, as
    // ControlCenterPanel.placeCard does). A card embedded in an outer wrapper
    // whose own x/y carry the surface offset (the desk widgets) must point this
    // at that wrapper -- the glass fills this card at local (0,0), and
    // RoundedBlurRegion reads item.x/y verbatim, so a zero-positioned card
    // would misplace the blur region to the window origin.
    property Item blurAnchor: root
    property Item captureAnchor: null
    property Item clipViewport: null
    property SceneBounds rootBounds: SceneBounds { item: root }
    property SceneBounds morphBounds: SceneBounds { item: morphAnchor }
    property SceneBounds viewportBounds: SceneBounds { item: root.clipViewport }
    readonly property rect nativeRect: {
        if (!cardShown) return Qt.rect(0, 0, 0, 0)
        if (!clipViewport) return _morph
        const r = rootBounds.rect, m = morphBounds.rect, v = viewportBounds.rect
        if (r.width <= 0 || r.height <= 0) return Qt.rect(0, 0, 0, 0)
        const x = Math.max(m.x, v.x), y = Math.max(m.y, v.y)
        return Qt.rect((x - r.x) * width / r.width, (y - r.y) * height / r.height,
            Math.max(0, Math.min(m.x + m.width, v.x + v.width) - x) * width / r.width,
            Math.max(0, Math.min(m.y + m.height, v.y + v.height) - y) * height / r.height)
    }
    readonly property bool backdropVisible: cardGlass.visible
    // During a morph the card keeps publishing only the shrink window: the
    // glass and its blur region are clipped to `_morph`, so KWin frosts the
    // capsule-sized rectangle, not the full panel silhouette.
    clip: _morph.width < width || _morph.height < height
        || _morph.x !== 0 || _morph.y !== 0

    // Content's adaptive foreground ink, from this card's glass.
    readonly property color materialForegroundColor: cardGlass.foregroundColor
    readonly property color materialSecondaryForegroundColor:
        cardGlass.secondaryForegroundColor
    readonly property color materialTertiaryForegroundColor:
        cardGlass.tertiaryForegroundColor

    width: cardWidth
    height: cardHeight
    visible: root.cardShown

    // Geometry anchor the glass and its compositor shape publish from. During
    // a morph this is the shrinking window `_morph`; at rest it collapses to
    // the full card so an unmorphed card publishes exactly its own rectangle.
    Item {
        id: morphAnchor
        x: root._morph.x
        y: root._morph.y
        width: root._morph.width
        height: root._morph.height
    }

    Item {
        id: clippedOutline
        x: root.nativeRect.x; y: root.nativeRect.y
        width: root.nativeRect.width; height: root.nativeRect.height
    }

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
    ControlCenterGlass {
        id: cardGlass
        anchors.fill: parent
        visible: !root.clipViewport || root.nativeRect.width > 0 && root.nativeRect.height > 0
        captureAnchor: root.captureAnchor
        useKwinEffect: AppearanceTokens.surface.usesKwinBlur
        backdropScale: root.backdropScale
        fallbackEnabled: root.fallbackEnabled
        // The glass fills this card at local (0,0); its region must land where
        // the card actually sits in the window, so anchor it to the positioned
        // card Item (whose x/y carry the grid offset) instead of the glass.
        // root.blurAnchor defaults to this card; a wrapper-embedded card (the
        // desk widgets) overrides it to point at the wrapper that holds the
        // true surface offset.
        blurAnchor: root.clipViewport ? clippedOutline : root.morphRect.width > 0 ? morphAnchor : root.blurAnchor
        radius: Math.max(1, Math.min(
            Math.round(root.cardRadius),
            Math.floor(Math.min(root.cardWidth, root.cardHeight) / 2)))
        backdropRadius: root.clipViewport ? Math.min(radius, clippedOutline.width / 2, clippedOutline.height / 2) : radius
        baseColor: root.cardColor
        surfaceOpacity: root.cardOpacity
        scrimLevel: root.cardScrimLevel
        // Fades the KWin scrim with the page crossfade so the frosted glass
        // does not outlive the QML content during a navigation. A card not in
        // a transition keeps the default 1 and renders exactly as before.
        scrimOpacity: root.glassOpacity
        materialOpacity: root.glassOpacity

        // Concrete card content (declared by the card instance), above the glass.
        Item {
            id: cardContent
            anchors.fill: parent
            visible: root.cardOpacity > 0.001
            scale: root.cardScale
            opacity: root.contentOpacity
            transform: Translate { y: root.contentOffsetY }
        }
    }
}
