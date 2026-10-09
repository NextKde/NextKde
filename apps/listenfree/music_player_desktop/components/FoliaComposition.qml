pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "FoliaComposition.js" as Program

Item {
    id: decor
    property string seed: ""
    property int lineIndex: -1
    property real positionMs: 0
    property real startMs: 0
    property real endMs: 5000
    property bool reducedMotion: false
    readonly property var composition: lineIndex>=0 && width>0 && height>0 ? Program.build(seed,lineIndex,width,height) : null
    readonly property var profile: composition?composition.profile:({})
    readonly property string kind: composition?composition.kind:""
    property int revision: 0
    function advance(){if(composition){composition.update((reducedMotion?endMs:positionMs)/1000,startMs/1000,endMs/1000);revision++}}
    onPositionMsChanged:advance()
    onCompositionChanged:advance()
    onReducedMotionChanged:advance()
    Repeater {
        model:decor.composition?decor.composition.records:[]
        delegate:Shape {
            id: shape
            required property var modelData
            readonly property var pose: { const tick=decor.revision;return Program.frame(modelData) }
            x:pose.x;y:pose.y;rotation:pose.rotation;opacity:pose.alpha*.67
            transformOrigin:Item.TopLeft
            transform:Scale { xScale:shape.pose.sx;yScale:shape.pose.sy }
            preferredRendererType:Shape.CurveRenderer
            ShapePath {
                fillColor:shape.modelData.fill;strokeColor:shape.modelData.stroke;strokeWidth:shape.modelData.strokeWidth
                fillRule:ShapePath.OddEvenFill
                PathSvg { path:shape.modelData.path }
            }
        }
    }
}
