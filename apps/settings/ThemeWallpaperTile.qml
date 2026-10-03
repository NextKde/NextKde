import "../../shared/qml/controls" as SharedControls
import QtQuick
import QtQuick.Effects
import "../../shared/qml/wallpapers" as ThemeVisuals

Rectangle {
    id: root
    property string themeId: "starfield"
    // 主题包自带 preview.png;为空时回退内置主题的静态图。
    property string previewPath: ""
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
    Loader {
        id: previewScene
        x: 5; y: 5
        width: parent.width - 10; height: parent.height - 62
        sourceComponent: root.previewPath ? packPreview : builtinPreview
        // The PNG supplies its texture directly to the rounded mask below.
        visible: false
    }
    Component {
        id: packPreview
        Image {
            source: root.previewPath
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }
    }
    Component {
        id: builtinPreview
        ThemeVisuals.ThemeWallpaperThumbnail {
            themeId: root.themeId
        }
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
