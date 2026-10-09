pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: tile
    property string title: ""
    property string subtitle: ""
    property color tint: AppTheme.accent
    property url artworkSource: ""
    property real size: 120
    property int sourcePixelSize: 320
    property bool darkMode: false
    property bool portrait: false
    readonly property alias artworkItem: art
    signal activated
    signal contextRequested(real localX, real localY)
    width: size; height: size + 43
    scale: tap.pressed ? .96 : hover.hovered ? 1.025 : 1
    Behavior on scale { NumberAnimation { duration: AppTheme.duration(150); easing.type: Easing.OutCubic } }
    CoverArt {
        id: art
        objectName: "artworkTileImage"
        width: tile.size; height: tile.size
        sourcePixelSize: tile.sourcePixelSize
        cornerRadius: tile.portrait ? width/2 : width/10
        source: tile.artworkSource; showShadow: true
    }
    Text {
        y: tile.size + 7; width: parent.width
        text: tile.title; elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        color: AppTheme.canvasText; font.family: AppTheme.fontFamily
        font.pixelSize: 13; font.weight: Font.Medium
    }
    Text {
        y: tile.size + 26; width: parent.width
        text: tile.subtitle; elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        color: AppTheme.canvasSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 10
    }
    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: tile.activated() }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: point => tile.contextRequested(point.position.x,point.position.y) }
}
