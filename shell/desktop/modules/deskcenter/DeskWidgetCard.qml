import QtQuick
import qs.desktop.modules.common

// Widget geometry stays shared across shell styles. Material uses one neutral
// tonal surface for the collection; semantic colours belong to card content.
Rectangle {
    id: root

    property string title: ""
    property string widgetId: ""
    property color startColor: "transparent"
    property color endColor: "transparent"
    property bool showSurface: true
    property color materialSurfaceColor: AppearanceTokens.surface.widgetFill
    readonly property bool usesColorArtwork: IconAppearanceService.mode === "color"

    radius: AppearanceTokens.widget.radius
    color: "transparent"
    clip: true

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.usesColorArtwork && !AppearanceTokens.isMaterial
        gradient: Gradient {
            GradientStop { position: 0; color: root.startColor }
            GradientStop { position: 1; color: root.endColor }
        }
    }

    WidgetGlassMaterial {
        anchors.fill: parent
        cornerRadius: root.radius
        visible: !root.usesColorArtwork && !AppearanceTokens.isMaterial
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
