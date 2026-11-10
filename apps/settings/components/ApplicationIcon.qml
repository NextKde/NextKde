import QtQuick
import Kos.Demo as Demo

Item {
    id: root
    property url source: ""
    property color fallbackColor: "#8e8e93"
    implicitWidth: 20
    implicitHeight: 20
    Image {
        id: artwork
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(48, 48)
        fillMode: Image.PreserveAspectFit
    }
    Demo.VectorIcon {
        anchors.centerIn: parent
        visible: artwork.status !== Image.Ready
        name: "grid"
        size: Math.min(root.width, root.height)
        color: root.fallbackColor
    }
}
