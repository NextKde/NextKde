pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Item {
    id: sector
    property url artwork: ""
    property real outerRadius: 800
    property real innerRadius: 560
    property real halfAngle: 5.5
    property real angle: 0
    property real emphasis: 0
    property bool selected: false
    signal selectedRequested()
    readonly property real radians: halfAngle*Math.PI/180
    readonly property real sine: Math.sin(radians)
    readonly property real cosine: Math.cos(radians)
    readonly property real inset: innerRadius*cosine
    x: inset; y: -outerRadius*sine
    width: outerRadius-inset; height: 2*outerRadius*sine
    transform: Rotation { origin.x: -sector.x; origin.y: -sector.y; angle: sector.angle }
    containmentMask: shape
    CoverArt {
        id: cover
        anchors.fill: parent; source: sector.artwork
        sourcePixelSize: 512; cornerRadius: 0
        textureOnly: true
    }
    Shape {
        id: shape; anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        containsMode: Shape.FillContains
        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.rgba(1,1,1,.10+sector.emphasis*.25+(hover.hovered?.16:0))
            fillColor: "#47525b"
            fillItem: cover.missingArtwork ? null : cover.artworkTexture
            startX: 0; startY: (sector.outerRadius-sector.innerRadius)*sector.sine
            PathLine { x: sector.outerRadius*sector.cosine-sector.inset; y: 0 }
            PathArc {
                x: sector.outerRadius*sector.cosine-sector.inset; y: sector.height
                radiusX: sector.outerRadius; radiusY: sector.outerRadius
                direction: PathArc.Clockwise
            }
            PathLine { x: 0; y: (sector.outerRadius+sector.innerRadius)*sector.sine }
            PathArc {
                x: 0; y: (sector.outerRadius-sector.innerRadius)*sector.sine
                radiusX: sector.innerRadius; radiusY: sector.innerRadius
                direction: PathArc.Counterclockwise
            }
        }
    }
    // A narrow rim follows the real outer arc, without a rectangular card.
    Shape {
        anchors.fill: parent; opacity: sector.emphasis
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "#e4ffffff"; strokeWidth: 2; fillColor: "transparent"
            startX: sector.outerRadius*sector.cosine-sector.inset; startY: 0
            PathArc {
                x: sector.outerRadius*sector.cosine-sector.inset; y: sector.height
                radiusX: sector.outerRadius; radiusY: sector.outerRadius
                direction: PathArc.Clockwise
            }
        }
    }
    IconGlyph {
        anchors.centerIn: parent; width: 30; height: 30; kind: "music"
        visible: cover.missingArtwork; glyphColor: "#90ffffff"
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: sector.selectedRequested() }
}
