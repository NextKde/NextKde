import QtQuick

// 22 px status row: muted 12 px label, 50x14 pill on the trailing edge.
// The pill keeps white text in every appearance and falls back to a 16 %
// white plate when the state is unknown, matching the native scene.
Item {
    id: root
    property string title: ""
    // "up", "down" or "unknown"
    property string state: "unknown"
    property string upText: "UP"
    property string downText: "DOWN"
    property color ink: "white"
    property color mutedInk: Qt.rgba(1, 1, 1, 0.7)
    property color upColor: "#34c759"
    property color downColor: "#ff3b40"
    property string pillObjectName: ""

    implicitHeight: 22

    readonly property string label: state === "up" ? upText
        : state === "down" ? downText : "—"

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 54
        text: root.title
        color: root.mutedInk
        font.pixelSize: 12
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
    Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 50
        height: 14
        radius: 4
        color: root.state === "up" ? root.upColor
            : root.state === "down" ? root.downColor : Qt.rgba(1, 1, 1, 0.16)
        Text {
            objectName: root.pillObjectName
            anchors.centerIn: parent
            text: root.label
            color: "white"
            font.pixelSize: 10
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
        }
    }
}
