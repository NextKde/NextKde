import "../../shared/qml/controls" as SharedControls
import QtQuick
import QtQuick.Effects
import "../../shared/qml/wallpapers" as ThemeVisuals

Rectangle {
    id: root
    property string themeId: "starfield"
    property string title: ""
    property string detail: ""
    property color accent: "#70b4ff"
    property color textColor: "white"
    property color secondaryColor: "#aaaaaa"
    property color surroundingColor: "#202020"
    property bool selected: false
    signal activated()
    signal previewRequested()
    radius: 14
    color: surroundingColor
    border.width: selected ? 2 : 1
    border.color: selected ? accent : "#40808080"
    ThemeVisuals.ThemeWallpaperThumbnail {
        id: previewScene
        x: 5; y: 5
        width: parent.width - 10; height: parent.height - 62
        themeId: root.themeId
        // The PNG supplies its texture directly to the rounded mask below.
        visible: false
    }
    Rectangle {
        id: previewMask
        x: 5; y: 5; width: root.width-10; height: root.height-62
        radius: 10; layer.enabled: true; visible: false
    }
    MultiEffect {
        x: 5; y: 5; width: root.width-10; height: root.height-62
        source: previewScene
        maskEnabled: true
        maskSource: previewMask
    }
    Text {
        x: 12; y: parent.height - 49
        text: root.title
        color: root.textColor
        font.pixelSize: 13; font.weight: Font.DemiBold
    }
    Text {
        x: 12; y: parent.height - 28
        width: parent.width - 52
        elide: Text.ElideRight
        text: root.detail
        color: root.secondaryColor
        font.pixelSize: 10
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
    SharedControls.VectorIcon {
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 12
        name: "preview"; color: root.accent; size: 16
        MouseArea {
            anchors.fill: parent; anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: root.previewRequested()
        }
    }
}
