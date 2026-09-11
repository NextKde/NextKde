import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property int lobes: 12
    property real amplitude: 0.075
    property color fillColor: "transparent"
    property color outlineColor: "transparent"
    property real outlineWidth: 1

    readonly property real radius: Math.max(0, Math.min(width, height) / 2 - outlineWidth)
    readonly property point center: Qt.point(width / 2, height / 2)

    function points() {
        const result = []
        const count = 240
        for (let index = 0; index <= count; ++index) {
            const angle = index / count * Math.PI * 2
            const ripple = 1 - amplitude + amplitude * Math.sin(angle * lobes)
            const distance = radius * ripple
            result.push(Qt.point(center.x + Math.cos(angle) * distance,
                center.y + Math.sin(angle) * distance))
        }
        return result
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.outlineColor
            strokeWidth: root.outlineWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.points() }
        }
    }
}
