import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property Item backdrop
    property point sampleOrigin: Qt.point(0, 0)
    readonly property int padding: 20
    ShaderEffectSource {
        id: sample
        sourceItem: root.backdrop
        sourceRect: Qt.rect(root.sampleOrigin.x - root.padding, root.sampleOrigin.y - root.padding,
                            root.width + 2 * root.padding, root.height + 2 * root.padding)
        textureSize: Qt.size(Math.ceil(root.width + 2 * root.padding), Math.ceil(root.height + 2 * root.padding))
        live: true; visible: false
    }
    GaussianBlur {
        id: blur
        x: -root.padding; y: -root.padding
        width: root.width + 2 * root.padding; height: root.height + 2 * root.padding
        source: sample; radius: 16; samples: 25; deviation: 8
        visible: false
    }
    Item {
        id: surface; anchors.fill: parent; visible: false
        // Crop the padded blur into the field's local coordinates.
        ShaderEffectSource { anchors.fill: parent; sourceItem: blur; sourceRect: Qt.rect(root.padding, root.padding, root.width, root.height); live: true }
        Rectangle { anchors.fill: parent; color: "#18000000" }
    }
    Rectangle { id: mask; anchors.fill: parent; radius: height / 2; color: "white"; visible: false }
    OpacityMask { anchors.fill: parent; source: surface; maskSource: mask }
}
