import QtQuick
import QtQuick.Window

// 30 px section heading: hairline rules reaching both card edges, a 10 px
// Semibold uppercase title with 1 px character tracking, and an optional
// 18x20 glyph button pinned to the trailing edge.
Item {
    id: root
    property string title: ""
    property color ink: "white"
    property bool dark: true
    property color separator: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
    property string actionKind: ""
    property string actionObjectName: ""
    readonly property real hairline: 1 / (Screen.devicePixelRatio || 1)

    implicitHeight: 30
    signal actionTriggered()

    Rectangle {
        objectName: root.objectName.length > 0 ? root.objectName + "-left-rule" : ""
        x: 0
        y: Math.round((root.height - height) / 2)
        width: Math.max(0, heading.x - 8)
        height: root.hairline
        color: root.separator
    }
    Rectangle {
        x: heading.x + heading.width + 8
        y: Math.round((root.height - height) / 2)
        width: Math.max(0, root.width - x)
        height: root.hairline
        color: root.separator
    }
    Text {
        id: heading
        anchors.centerIn: parent
        text: root.title.toUpperCase()
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, root.dark ? 0.3 : 0.38)
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        textFormat: Text.PlainText
    }
    TrafficActionButton {
        visible: root.actionKind.length > 0
        objectName: root.actionObjectName
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        kind: root.actionKind
        ink: root.ink
        onClicked: root.actionTriggered()
    }
}
