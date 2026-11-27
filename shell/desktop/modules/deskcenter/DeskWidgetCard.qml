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
    property Component contentComponent: null
    property bool contentEnabled: true
    // Gallery copies paint a bounded thumbnail; they never publish compositor
    // surface shapes or blur regions into the desktop window.
    property bool preview: false
    // Material widgets may select a host-owned panel silhouette (e.g.
    // "roundedRect", "pill", "circle", "flower", "cookie", "clover",
    // "slantedOval", "arch") by publishing `surfaceShape` on Widget.qml.
    // Colour, opacity and compositor blur remain host-owned across every card.
    property string materialSurfaceShape: "roundedRect"
    property color startColor: "transparent"
    property bool hasMidColor: false
    property color midColor: "transparent"
    property real midPosition: 0.5
    property color endColor: "transparent"
    property int gradientOrientation: Gradient.Vertical
    // motion-exception: Ambient backgroundSpec crossfade avoids abrupt palette jumps on track/state changes.
    property int backgroundTransitionDuration: 560
    property bool _backgroundReady: false
    readonly property color _resolvedMidColor: hasMidColor
        ? midColor
        : Qt.rgba(
            (startColor.r + endColor.r) * 0.5,
            (startColor.g + endColor.g) * 0.5,
            (startColor.b + endColor.b) * 0.5,
            (startColor.a + endColor.a) * 0.5
        )
    Component.onCompleted: _backgroundReady = true
    property bool showSurface: true
    property color materialSurfaceColor: AppearanceTokens.surface.widgetFill
    // Widgets normally honour the colour-artwork style. A host that must keep
    // the compositor-backed material (the desktop grouped view) opts out, so
    // it still gets glass/tonal in the colour-artwork appearance.
    property bool allowColorArtwork: true
    readonly property bool usesColorArtwork:
        allowColorArtwork && AppearanceConfigService.widgetStyle === "color"
    readonly property real radius: AppearanceTokens.widget.radius

    // The active form's surface policy. Everything below reads this instead of
    // the shell style, which is what keeps both forms in one component.
    readonly property var surface: AppearanceTokens.surface
    readonly property bool tonalSurface: root.surface.paintInQml
    readonly property string effectiveMaterialShape: root.tonalSurface
        ? (root.materialSurfaceShape || "roundedRect")
        : "roundedRect"

    // `Item.clip` below only clips to a rectangle. Colour-artwork widgets can
    // contain their own full-bleed header or artwork, so mask their composed
    // layer to the same continuous contour that KWin uses for glass cards. The
    // tonal backend and the KWin-backed card already have their own mask path.
    //
    // This clip/mask lives on `surface` (below), not on `root` itself: the
    // host (DeskCenterWindow) parents edit-mode affordances -- the remove
    // badge, settings affordance, resize handle -- directly onto this
    // component as root's own children, and those are deliberately drawn
    // hanging half outside the card's corner (see the remove badge's
    // negative anchor margins). Clipping at root would cut that overhang off
    // along with anything else drawn outside the card's rectangle.
    Item {
        id: surface
        anchors.fill: parent
        clip: true
        layer.enabled: root.usesColorArtwork && !root.tonalSurface
        layer.effect: SquircleMask {
            cornerRadius: root.radius
            cornerExponent: AppearanceTokens.shape.cornerExponent
            maskWidth: surface.width
            maskHeight: surface.height
        }

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
                shapeType: root.effectiveMaterialShape
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
            // The tonal form draws MaterialCardSurface with the widget's declared
            // `surfaceShape` (defaulting to roundedRect); the glass form only owns
            // one when the card is not drawing colour artwork of its own.
            sourceComponent: root.preview ? null : root.tonalSurface
                ? tonalSurfaceComponent
                : (root.usesColorArtwork ? null : glassSurfaceComponent)
        }

        MaterialShapeVisual {
            anchors.fill: parent
            visible: root.preview && root.tonalSurface
            shapeType: root.effectiveMaterialShape
            radius: root.radius
            fillColor: root.materialSurfaceColor
            fillOpacity: AppearanceTokens.surface.widgetOpacity
            inset: 1
        }

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            visible: root.preview && !root.tonalSurface && !root.usesColorArtwork
            color: AppearanceTokens.colors.layer1
            border.width: 1
            border.color: AppearanceTokens.colors.outlineVariant
        }

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            visible: root.usesColorArtwork && !root.tonalSurface
            gradient: Gradient {
                orientation: root.gradientOrientation
                GradientStop {
                    position: 0
                    color: root.startColor
                    Behavior on color {
                        enabled: root._backgroundReady && !root.preview && root.backgroundTransitionDuration > 0
                        ColorAnimation { duration: root.backgroundTransitionDuration; easing.type: Easing.InOutCubic }
                    }
                }
                GradientStop {
                    position: Math.max(0.01, Math.min(0.99, root.midPosition))
                    color: root._resolvedMidColor
                    Behavior on color {
                        enabled: root._backgroundReady && !root.preview && root.backgroundTransitionDuration > 0
                        ColorAnimation { duration: root.backgroundTransitionDuration; easing.type: Easing.InOutCubic }
                    }
                }
                GradientStop {
                    position: 1
                    color: root.endColor
                    Behavior on color {
                        enabled: root._backgroundReady && !root.preview && root.backgroundTransitionDuration > 0
                        ColorAnimation { duration: root.backgroundTransitionDuration; easing.type: Easing.InOutCubic }
                    }
                }
            }
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: root.visible
            enabled: root.contentEnabled && !root.preview
            sourceComponent: root.contentComponent
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

    // Published (as composite member) to the window's single blur region union.
    // Both backends answer to one contract, so the card does not care which one
    // it got -- and neither does the window.
    readonly property var blurRegion:
        surfaceBackend.item ? surfaceBackend.item.blurRegion : null

    // Lets a settings affordance built by the host (DeskCenterWindow) reach
    // into the same running content instance instead of creating a second,
    // out-of-sync one -- a package's settings must edit the live instance's
    // data service, not a throwaway copy.
    readonly property var loadedContent: contentLoader.item
}
