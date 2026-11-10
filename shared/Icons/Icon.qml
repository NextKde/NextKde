import QtQuick

// One font owns glyph weight, proportions and bearings; hosts own layout.
Item {
    id: root
    property string name: ""
    property color color: "white"
    property real size: 16
    property bool filled: false
    property bool outlined: false
    property color outlineColor: "transparent"
    readonly property bool available: IconRegistry.has(name)
    readonly property bool ready: IconRegistry.ready
    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true
    Text {
        anchors.fill: parent
        visible: IconRegistry.ready
        text: IconRegistry.glyph(root.name, root.filled)
        font.family: IconRegistry.family
        font.pixelSize: Math.min(root.size, root.width, root.height)
        font.weight: Font.Normal
        font.hintingPreference: Font.PreferNoHinting
        font.kerning: false
        font.contextFontMerging: false
        color: root.color
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.QtRendering
        style: root.outlined ? Text.Outline : Text.Normal
        styleColor: root.outlineColor
        Accessible.ignored: true
    }
}
