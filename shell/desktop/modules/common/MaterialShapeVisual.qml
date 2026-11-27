import QtQuick
import QtQuick.Shapes
import "MaterialShapeGeometry.mjs" as ShapeGeom

// Shared Material 3 Expressive surface silhouette renderer.
// Renders roundedRect, pill, circle, or polygon silhouettes (flower, cookie,
// clover, slantedOval, arch) from MaterialShapeGeometry.mjs so live desktop
// surfaces and gallery preview thumbnails share identical geometry.
Item {
    id: root

    property string shapeType: "roundedRect"
    property real radius: 16
    property color fillColor: "transparent"
    property real fillOpacity: 1.0
    property real inset: 1

    readonly property string canonicalShape: ShapeGeom.normalizeShape(shapeType)
    readonly property bool isPolygon: ShapeGeom.isPolygonShape(canonicalShape)

    function polygonPath(shape, w, h, ins) {
        const pts = ShapeGeom.outlinePoints(shape, 0, 0, w, h, ins)
        const out = []
        for (let i = 0; i < pts.length; ++i)
            out.push(Qt.point(pts[i].x, pts[i].y))
        return out
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.isPolygon && root.canonicalShape !== "circle"
        radius: root.canonicalShape === "pill" ? Math.min(width, height) / 2 : root.radius
        color: root.fillColor
        opacity: root.fillOpacity
        border.width: 0
    }

    Rectangle {
        anchors.centerIn: parent
        visible: root.canonicalShape === "circle"
        width: Math.max(0, Math.min(parent.width, parent.height) - root.inset * 2)
        height: width
        radius: width / 2
        color: root.fillColor
        opacity: root.fillOpacity
        border.width: 0
    }

    Shape {
        anchors.fill: parent
        visible: root.isPolygon
        antialiasing: true
        ShapePath {
            fillColor: Qt.rgba(root.fillColor.r, root.fillColor.g,
                root.fillColor.b, root.fillOpacity)
            strokeColor: "transparent"
            strokeWidth: 0
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline {
                path: root.isPolygon
                    ? root.polygonPath(root.canonicalShape, root.width, root.height, root.inset)
                    : []
            }
        }
    }
}
