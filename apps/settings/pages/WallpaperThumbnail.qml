import QtQuick
import QtQuick.Effects

// 圆角缩略图:MultiEffect 蒙版裁剪(WallpaperGalleryTile 同款),替代角楔遮盖。
Item {
    id: thumbnail
    property string imagePath: ""
    property int cornerRadius: 11
    property color surroundingColor: "#1c1c1e"

    Rectangle {
        anchors.fill: parent
        radius: thumbnail.cornerRadius
        color: thumbnail.surroundingColor

        Image {
            id: picture
            anchors.fill: parent
            source: thumbnail.imagePath
                ? (thumbnail.imagePath.startsWith("/")
                    ? "file://" + thumbnail.imagePath : thumbnail.imagePath) : ""
            sourceSize: Qt.size(Math.max(1, thumbnail.width * 2),
                Math.max(1, thumbnail.height * 2))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            visible: false
        }
        Rectangle {
            id: pictureMask
            anchors.fill: parent
            radius: thumbnail.cornerRadius
            layer.enabled: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: picture
            visible: picture.status === Image.Ready
            maskEnabled: true
            maskSource: pictureMask
        }
    }
}
