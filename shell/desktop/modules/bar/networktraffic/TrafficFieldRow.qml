import QtQuick

// 22 px label/value row. The title is 12 Regular muted, the value 12 Semibold
// ink and right aligned in a fixed 128 px column. Totals carry a 10x10 colour
// swatch, which narrows the title column to 114 px exactly like the native row.
Item {
    id: root
    property string title: ""
    property string value: "—"
    property color ink: "white"
    property color mutedInk: Qt.rgba(1, 1, 1, 0.7)
    property color swatchColor: "transparent"
    property bool showSwatch: false
    property string valueObjectName: ""

    implicitHeight: 22

    Rectangle {
        visible: root.showSwatch
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 10
        radius: 2.5
        color: root.swatchColor
    }
    Text {
        x: root.showSwatch ? 14 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: root.showSwatch ? 114 : 128
        text: root.title
        color: root.mutedInk
        font.pixelSize: 12
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
    Text {
        objectName: root.valueObjectName
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 128
        text: root.value
        color: root.ink
        font.pixelSize: 12
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
}
