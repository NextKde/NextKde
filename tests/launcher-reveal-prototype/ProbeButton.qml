import QtQuick

Rectangle {
    id: root
    property string label: ""
    property bool selected: false
    signal clicked()
    width: Math.max(106, labelText.implicitWidth + 30)
    height: 38
    radius: 10
    color: selected ? "#365674" : (mouse.containsMouse ? "#2a3b4d" : "#213041")
    border.width: 1
    border.color: selected ? "#83aecf" : "#405166"
    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        color: "#edf4fa"
        font.pixelSize: 14
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
