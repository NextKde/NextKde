import QtQuick
import QtQuick.Shapes

Item {
    id: wave
    property bool running: false
    property bool reducedMotion: false
    property color waveColor: AppTheme.canvasText
    property real phase: 0
    readonly property real amplitude: running ? 5.2 : .8
    // Two small GPU tessellated paths; no Canvas, images or per-frame JS arrays.
    NumberAnimation on phase {
        from: 0; to: Math.PI*2; duration: 2400; loops: Animation.Infinite
        running: wave.running && wave.visible && !wave.reducedMotion
    }
    Repeater {
        model: 2
        Shape {
            id: line
            required property int index
            anchors.fill: parent
            opacity: index===0 ? .68 : .22
            readonly property real phaseOffset: wave.phase + index*1.4
            function yAt(t: real): real {
                return height/2 + Math.sin(phaseOffset+t*Math.PI*6)*wave.amplitude
            }
            function tangent(t: real): real {
                return Math.cos(phaseOffset+t*Math.PI*6)*wave.amplitude*Math.PI/3
            }
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: wave.waveColor; strokeWidth: 1.6; fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: 1; startY: line.yAt(0)
                PathCubic { x: line.width/6; y: line.yAt(1/6); control1X: line.width/18; control1Y: line.yAt(0)+line.tangent(0); control2X: line.width/9; control2Y: line.yAt(1/6)-line.tangent(1/6) }
                PathCubic { x: line.width/3; y: line.yAt(1/3); control1X: line.width*2/9; control1Y: line.yAt(1/6)+line.tangent(1/6); control2X: line.width*5/18; control2Y: line.yAt(1/3)-line.tangent(1/3) }
                PathCubic { x: line.width/2; y: line.yAt(1/2); control1X: line.width*7/18; control1Y: line.yAt(1/3)+line.tangent(1/3); control2X: line.width*4/9; control2Y: line.yAt(1/2)-line.tangent(1/2) }
                PathCubic { x: line.width*2/3; y: line.yAt(2/3); control1X: line.width*5/9; control1Y: line.yAt(1/2)+line.tangent(1/2); control2X: line.width*11/18; control2Y: line.yAt(2/3)-line.tangent(2/3) }
                PathCubic { x: line.width*5/6; y: line.yAt(5/6); control1X: line.width*13/18; control1Y: line.yAt(2/3)+line.tangent(2/3); control2X: line.width*7/9; control2Y: line.yAt(5/6)-line.tangent(5/6) }
                PathCubic { x: line.width-1; y: line.yAt(1); control1X: line.width*8/9; control1Y: line.yAt(5/6)+line.tangent(5/6); control2X: line.width*17/18; control2Y: line.yAt(1)-line.tangent(1) }
            }
        }
    }
}
