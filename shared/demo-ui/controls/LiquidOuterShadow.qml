import QtQuick
import QtQuick.Window

// Source-free outer shadow. The shared SDF shader has exactly zero alpha inside.
Item {
    id: root
    property int shadowLevel: LiquidStyle.shadowLevel
    readonly property var _profile: LiquidStyle.shadowProfile(shadowLevel)
    property real radius: 22
    property real outwardOffset: 0
    property color shadowColor: "#000000"
    property real shadowOpacity: _profile.opacity
    property real softness: _profile.softness
    property real spread: _profile.spread
    property vector2d offset: Qt.vector2d(0, _profile.offsetY)
    ShaderEffect {
        x: -root.spread - root.outwardOffset; y: -root.spread - root.outwardOffset
        width: root.width + 2 * (root.spread + root.outwardOffset)
        height: root.height + 2 * (root.spread + root.outwardOffset)
        visible: GraphicsInfo.api !== GraphicsInfo.Software
        vertexShader: Qt.resolvedUrl("shaders/liquid_shadow.vert.qsb")
        fragmentShader: Qt.resolvedUrl("shaders/liquid_shadow.frag.qsb")
        property vector2d bodySize: Qt.vector2d(root.width + 2 * root.outwardOffset, root.height + 2 * root.outwardOffset)
        property vector2d shadowOffset: root.offset
        property real padding: root.spread
        property real radius: root.radius + root.outwardOffset
        property real softness: root.softness
        property real shadowOpacity: root.shadowOpacity
        property color shadowColor: root.shadowColor
    }
}
