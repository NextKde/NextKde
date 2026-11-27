import Quickshell
import QtQuick
import "MaterialShapeGeometry.mjs" as ShapeGeom

// The Material form's card surface.
//
// Every desktop card gets its whole surface from here: the paint it draws and the
// region the compositor frosts behind it. The only thing a widget may vary is
// the outline shapeType (roundedRect, pill, circle, flower, cookie, clover,
// slantedOval, arch). Colour, opacity and the frost itself are host-owned and
// shared across every card.
Item {
    id: root

    // The positioned wrapper whose x/y are the card's surface coordinates; all
    // blur regions read them verbatim, exactly like RoundedBlurRegion.
    required property Item blurAnchor
    property real radius: 16
    // The card's paint. One value for every card, in whichever shape the outline
    // takes.
    property color fillColor: "transparent"
    property real fillOpacity: 1.0
    // Unified Material expressive shape name (normalized via MaterialShapeGeometry).
    property string shapeType: "roundedRect"

    readonly property string effectiveShape: ShapeGeom.normalizeShape(root.shapeType)
    readonly property bool isPolygon: ShapeGeom.isPolygonShape(root.effectiveShape)

    // The outline the compositor frosts. Every card publishes one: the form is one
    // effect across all of them, and shape is the only difference between cards.
    readonly property var blurRegion: root.isPolygon
        ? polygonRegion
        : (root.effectiveShape === "circle" ? circleRegion : rectRegion)

    // The paint, in the outline's shape.
    MaterialShapeVisual {
        anchors.fill: parent
        shapeType: root.effectiveShape
        radius: root.radius
        fillColor: root.fillColor
        fillOpacity: root.fillOpacity
        inset: 1
    }

    RoundedBlurRegion {
        id: rectRegion
        item: root.blurAnchor
        radius: root.effectiveShape === "pill"
            ? Math.min(root.width, root.height) / 2
            : root.radius
    }

    Region {
        id: circleRegion
        property SceneBounds bounds: SceneBounds { item: root.blurAnchor }
        readonly property rect r: bounds.rect
        readonly property int d: Math.max(0, Math.round(Math.min(r.width, r.height) - 2))
        x: Math.round(r.x + (r.width - d) / 2)
        y: Math.round(r.y + (r.height - d) / 2)
        width: d
        height: d
        shape: RegionShape.Ellipse
    }

    ShapeBlurRegion {
        id: polygonRegion
        item: root.blurAnchor
        shapeType: root.effectiveShape
        active: root.isPolygon
        inset: 2
    }
}
