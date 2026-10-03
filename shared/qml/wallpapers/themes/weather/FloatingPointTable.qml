import QtQuick
Item {
    id: root
    property url source
    property int tableWidth: 512
    property int tableHeight: 512
    property int channels: 2
    property alias texture: buffer
    width: tableWidth
    height: tableHeight
    Image {
        id: encodedImage
        source: root.source
        smooth: false
        visible: false
        onStatusChanged: if (status === Image.Ready) Qt.callLater(buffer.scheduleUpdate)
    }
    ShaderEffect {
        id: decode
        anchors.fill: parent
        visible: false
        blending: false
        property var encoded: encodedImage
        property real channels: root.channels
        property vector2d tableSize: Qt.vector2d(root.tableWidth,root.tableHeight)
        fragmentShader: "shaders/decode_table.frag.qsb"
    }
    ShaderEffectSource {
        id: buffer
        sourceItem: decode
        textureSize: Qt.size(root.tableWidth,root.tableHeight)
        format: ShaderEffectSource.RGBA32F
        smooth: true
        live: false
        visible: false
    }
}
