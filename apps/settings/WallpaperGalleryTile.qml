import QtQuick

Rectangle {
    id: tile

    property string imagePath: ""
    property string title: ""
    property string subtitle: ""
    property string swatchColor: ""
    property color accent: "#64d2ff"
    property color surroundingColor: "#1c1c1e"
    property bool selected: false
    readonly property bool isSwatch: swatchColor.length > 0

    signal activated()
    signal hovered(bool inside)

    radius: 15
    color: isSwatch ? swatchColor : "#252a31"
    clip: true
    border.width: selected ? 3 : 1
    border.color: selected ? accent
        : tileMouse.containsMouse ? "#80ffffff" : "#30ffffff"
    Behavior on border.color { ColorAnimation { duration: 150 } }

    Image {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: caption.top
        anchors.margins: tile.selected ? 3 : 1
        source: tile.isSwatch ? "" : (tile.imagePath.startsWith("/")
            ? "file://" + tile.imagePath : tile.imagePath)
        sourceSize: Qt.size(Math.max(1, tile.width * 2),
                            Math.max(1, tile.height * 2))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: !tile.isSwatch
    }

    Rectangle {
        id: caption
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 32
        color: "#b8141922"
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: caption.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 1
        Text {
            width: parent.width
            text: tile.title
            color: "white"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        width: 22
        height: 22
        radius: 11
        color: tile.selected ? tile.accent : "#88000000"
        visible: tile.selected || tileMouse.containsMouse
        Text {
            anchors.centerIn: parent
            text: tile.selected ? "✓" : "↗"
            color: tile.selected ? "#14212f" : "white"
            font.pixelSize: 12
            font.weight: Font.Bold
        }
    }

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: tile.hovered(containsMouse)
        onClicked: tile.activated()
    }

    WallpaperRoundedCorners {
        anchors.fill: parent
        cornerRadius: tile.radius
        fillColor: tile.surroundingColor
    }
}
