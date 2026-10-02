import QtQuick

Rectangle {
    id: button
    property string label: ""
    property var colors
    property bool emphasized: false
    signal clicked()
    implicitWidth: textItem.implicitWidth + 28
    implicitHeight: 34
    radius: 12
    opacity: enabled ? 1 : 0.45
    color: emphasized
        ? Qt.rgba(colors.accent.r, colors.accent.g, colors.accent.b, 0.14)
        : "transparent"
    border.color: emphasized ? Qt.rgba(colors.accent.r, colors.accent.g, colors.accent.b, 0.4)
        : "transparent"
    Behavior on color { ColorAnimation { duration: 140 } }
    Text {
        id: textItem
        anchors.centerIn: parent
        text: button.label
        color: button.emphasized ? button.colors.accent : button.colors.primaryText
        font.pixelSize: 12
        font.weight: Font.Medium
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
