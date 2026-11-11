import QtQuick
import qs.desktop.modules.common

// Desktop artwork keeps the folder silhouette behind the user's emblem.
Item {
    id: root
    property color color: "#70b6ff"
    property string emoji: ""
    implicitWidth: 64
    implicitHeight: 64

    function rgb(factor) {
        return "rgb(" + Math.round(Math.min(1, root.color.r * factor) * 255)
            + "," + Math.round(Math.min(1, root.color.g * factor) * 255)
            + "," + Math.round(Math.min(1, root.color.b * factor) * 255) + ")"
    }

    Image {
        anchors.fill: parent
        source: "data:image/svg+xml;utf8," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
            + '<path d="M10 24H43.6L53.4 10H67.6Q79.48 10 79.48 21.88V24Z"'
            + ' fill="' + root.rgb(0.72) + '" fill-opacity="' + (root.color.a * 0.92) + '"/>'
            + '<rect x="10" y="24" width="80" height="66" rx="11.88"'
            + ' fill="' + root.rgb(1) + '" fill-opacity="' + (root.color.a * 0.90) + '"/>'
            + '<path d="M21.88 24H78.12V31.92H21.88Z" fill="white" fill-opacity="0.18"/>'
            + '<rect x="10" y="24" width="80" height="66" rx="11.88"'
            + ' fill="none" stroke="black" stroke-opacity="0.16" stroke-width="1" vector-effect="non-scaling-stroke"/>'
            + '</svg>')
        sourceSize: Qt.size(Math.max(1, Math.ceil(width * 2)), Math.max(1, Math.ceil(height * 2)))
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    Text {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: parent.height * 0.36
        }
        visible: root.emoji.length > 0
        text: root.emoji
        font.family: AppearanceTokens.typography.emojiFamily
        font.pixelSize: Math.min(root.width, root.height) * 0.36
    }
}
