import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.common

// The widget's glass surface. Instead of simulating liquid glass in QML, each
// card is real compositor glass: ControlCenterCard publishes this card's
// SurfaceShape as blurRegion, and DeskCenterWindow aggregates every card's
// blurRegion into one window region. KWin therefore blurs behind the cards
// (wallpaper AND windows) and leaves the grid gaps crisp and see-through --
// hollow, frosted, one surface per card. Color-artwork and tonal surfaces stay
// plain, non-glass rects.
Item {
    id: root

    property string title: ""
    property string widgetId: ""
    property color startColor: "transparent"
    property color endColor: "transparent"
    property bool showSurface: true
    property color materialSurfaceColor: AppearanceTokens.surface.widgetFill
    readonly property bool usesColorArtwork: IconAppearanceService.mode === "color"
    readonly property real radius: AppearanceTokens.widget.radius

    clip: true

    // The KWin-backed glass surface. Glass themes only: colour artwork keeps
    // its own gradient card, tonal themes keep a plain material surface.
    ControlCenterCard {
        id: glassCard
        anchors.fill: parent
        // The glass fills this card at local (0,0); RoundedBlurRegion reads the
        // blur anchor's x/y verbatim as surface coordinates, so point it at
        // THIS wrapper (whose x/y carry the grid offset the delegate assigned)
        // instead of the card, or the blur region lands at the window origin.
        blurAnchor: root
        cardRadius: root.radius
        // Desktop widgets keep the same see-through level as the Dock.
        cardScrimLevel: "subtle"
        visible: !root.usesColorArtwork && !AppearanceTokens.isMaterial
    }

    // Published (as composite member) to the window's single blur region union.
    // null on non-glass surfaces so the window only aggregates real glass cards.
    readonly property var blurRegion:
        (!root.usesColorArtwork && !AppearanceTokens.isMaterial)
            ? glassCard.blurRegion : null

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.usesColorArtwork && !AppearanceTokens.isMaterial
        gradient: Gradient {
            GradientStop { position: 0; color: root.startColor }
            GradientStop { position: 1; color: root.endColor }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !AppearanceTokens.surface.usesBackdrop && root.widgetId !== "clock"
        color: root.materialSurfaceColor
        opacity: AppearanceTokens.surface.widgetOpacity
        border.width: 0
    }

    // A broad, low-contrast bloom makes colour cards feel like widgets rather
    // than rectangular panels, while never running beneath the text itself.
    Rectangle {
        visible: root.showSurface && root.usesColorArtwork
            && !AppearanceTokens.isMaterial
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
        color: AppearanceTokens.isMaterial
            ? AppearanceTokens.colors.surfaceVariantForeground : Qt.rgba(1, 1, 1, 0.78)

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