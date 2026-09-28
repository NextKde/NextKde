import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common

// The widget's card surface. A card never simulates glass in QML: whichever
// backend it gets publishes a compositor blur region, and DeskCenterWindow
// aggregates every card's region into one window BackgroundEffect, so KWin blurs
// behind the cards (wallpaper AND windows) and leaves the grid gaps crisp and
// see-through -- hollow, frosted, one region per card.
//
// Exactly one backend exists at a time, chosen by the active form's policy in
// AppearanceTokens.surface. The card itself never branches on the shell style:
//   * tonal (Material): MaterialCardSurface paints the card and publishes the
//     outline it draws -- no LiquidGlassPanel, no SurfaceShape declaration, so
//     the compositor gives it plain frost instead of its liquid finish.
//   * glass (macos / windows12): ControlCenterCard hands the whole finish to KWin
//     through a LiquidGlassPanel SurfaceShape declaration; the card paints
//     nothing of its own.
// A colour-artwork card in the glass form owns no compositor surface at all and
// draws its own gradient below. In the tonal form every card is a tonal plate,
// colour artwork included.
Item {
    id: root

    property string title: ""
    // Host declaration: this card's surface outline is MaterialFlower's flower
    // silhouette instead of the rounded rectangle every other card uses. It is a
    // request, not a form of its own -- the tonal backend paints the same paint
    // in a different shape, same colour, same opacity.
    property bool flowerShapedSurface: false
    property color startColor: "transparent"
    property color endColor: "transparent"
    property bool showSurface: true
    property color materialSurfaceColor: AppearanceTokens.surface.widgetFill
    readonly property bool usesColorArtwork: AppearanceConfigService.widgetStyle === "color"
    readonly property real radius: AppearanceTokens.widget.radius

    // The active form's surface policy. Everything below reads this instead of
    // the shell style, which is what keeps both forms in one component.
    readonly property var surface: AppearanceTokens.surface
    readonly property bool tonalSurface: root.surface.paintInQml
    // A shape request only means something to the backend that paints the card.
    readonly property bool shapedSurface:
        root.flowerShapedSurface && root.tonalSurface

    // `Item.clip` below only clips to a rectangle. Colour-artwork widgets can
    // contain their own full-bleed header or artwork, so mask their composed
    // layer to the same continuous contour that KWin uses for glass cards. The
    // tonal backend and the KWin-backed card already have their own mask path.
    layer.enabled: root.usesColorArtwork && !root.tonalSurface
    layer.effect: SquircleMask {
        cornerRadius: root.radius
        cornerExponent: AppearanceTokens.shape.cornerExponent
        maskWidth: root.width
        maskHeight: root.height
    }

    clip: true

    Component {
        id: tonalSurfaceComponent

        MaterialCardSurface {
            // The surface fills this card at local (0,0); both regions read the
            // anchor's x/y verbatim as surface coordinates, so point them at THIS
            // wrapper (whose x/y carry the grid offset the delegate assigned)
            // instead of the surface, or the region lands at the window origin.
            blurAnchor: root
            radius: root.radius
            fillColor: root.materialSurfaceColor
            fillOpacity: AppearanceTokens.surface.widgetOpacity
            flowerShaped: root.shapedSurface
        }
    }

    Component {
        id: glassSurfaceComponent

        ControlCenterCard {
            // KWin keeps the material as the card's only paint layer; this card
            // then exists solely to publish the blur shape and the SurfaceShape
            // KWin paints from.
            fallbackEnabled: false
            // Same anchor rule as the tonal surface above.
            blurAnchor: root
            cardRadius: root.radius
            // Desktop widgets keep the same see-through level as the Dock.
            cardScrimLevel: "subtle"
        }
    }

    Loader {
        id: surfaceBackend
        anchors.fill: parent
        // The tonal form always has a surface; the glass form only owns one when
        // the card is not drawing colour artwork of its own.
        sourceComponent: root.tonalSurface
            ? tonalSurfaceComponent
            : (root.usesColorArtwork ? null : glassSurfaceComponent)
    }

    // Published (as composite member) to the window's single blur region union.
    // Both backends answer to one contract, so the card does not care which one
    // it got -- and neither does the window.
    readonly property var blurRegion:
        surfaceBackend.item ? surfaceBackend.item.blurRegion : null

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.usesColorArtwork && !root.tonalSurface
        gradient: Gradient {
            GradientStop { position: 0; color: root.startColor }
            GradientStop { position: 1; color: root.endColor }
        }
    }

    // A broad, low-contrast bloom makes colour cards feel like widgets rather
    // than rectangular panels, while never running beneath the text itself.
    Rectangle {
        visible: root.showSurface && root.usesColorArtwork && !root.tonalSurface
        width: parent.width * 0.78
        height: width
        radius: width / 2
        x: parent.width * 0.48
        y: -height * 0.44
        color: Qt.rgba(1, 1, 1, 0.1)
    }

    Text {
        visible: root.title.length > 0
        text: root.title
        color: AppearanceTokens.surface.widgetForeground

        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 18
            topMargin: 15
        }

        font {
            pixelSize: 12
            weight: Font.DemiBold
        }
    }
}
