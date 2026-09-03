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

    radius: AppearanceTokens.widget.radius
    color: "transparent"
    clip: true

    // A broad, low-contrast bloom makes colour cards feel like widgets rather
    // than rectangular panels, while never running beneath the text itself.
    Rectangle {
        visible: root.showSurface
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
        color: Qt.rgba(1, 1, 1, 0.78)

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

    gradient: Gradient {
        GradientStop {
            position: 0
            color: root.startColor
        }

        GradientStop {
            position: 1
            color: root.endColor
        }

    }

}
