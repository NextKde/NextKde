import QtQuick
import QtQuick.Effects
Item {
    id: root
    property string kind: "play"
    property color glyphColor: "white"
    property int volumeLevel: 3
    // Kept for existing callers. Stroke weight is authored consistently in SVG.
    property real strokeWidth: 2
    Image {
        id: vector
        anchors.fill: parent
        source: root.kind.length === 0 ? "" : "../assets/icons/" + (root.kind === "volume" ? "volume" + Math.min(2, Math.max(0,root.volumeLevel)) : root.kind) + ".svg"
        sourceSize: Qt.size(Math.ceil(width * 2),Math.ceil(height * 2))
        fillMode: Image.PreserveAspectFit
        visible: false
        smooth: true
    }
    MultiEffect { anchors.fill: parent; source: vector; colorization: 1; colorizationColor: root.glyphColor }
}
