import QtQuick

// Original NextKde artwork shares the application icons' soft tile and shading.
// Material navigation keeps its monochrome semantic glyphs.
Item {
    id: root
    required property var colors
    required property string iconName
    required property string symbol
    required property color tint
    property bool materialForm: false
    property bool highlighted: false
    property int size: 18

    width: size
    height: size

    Image {
        id: nativeIcon
        anchors.fill: parent
        source: root.materialForm ? "" : Qt.resolvedUrl("../icons/navigation/" + root.iconName + ".svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        visible: !root.materialForm && status === Image.Ready
    }

    SettingIcon {
        anchors.centerIn: parent
        visible: root.materialForm || nativeIcon.status === Image.Error
        colors: root.colors
        materialForm: root.materialForm
        symbol: root.symbol
        tint: root.tint
        highlighted: root.highlighted
        size: root.size
    }
}
