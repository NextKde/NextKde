import QtQuick
import qs.desktop.modules.common

// iPadOS widgets rely on distinct, calm colour fields instead of a common
// translucent panel. The colours stay dark enough for white text to remain
// readable over every wallpaper without needing a glass effect.
Rectangle {
    id: root

    property string title: ""
    property color startColor: "transparent"
    property color endColor: "transparent"
    property bool showSurface: true
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
        visible: AppearanceTokens.isMaterial
        color: AppearanceTokens.colors.surfaceContainerLow
        border.width: 1
        border.color: AppearanceTokens.colors.outlineVariant
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
            ? AppearanceTokens.colors.onSurfaceVariant : Qt.rgba(1, 1, 1, 0.78)

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
