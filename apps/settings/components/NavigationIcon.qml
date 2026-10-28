import QtQuick

// Sidebar assets retain Apple's original tile, shading and symbol proportions.
// Content-page SettingIcon instances and Material navigation are independent.
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
        source: root.materialForm ? "" : Qt.resolvedUrl("../icons/navigation/" + root.iconName + ".png")
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
