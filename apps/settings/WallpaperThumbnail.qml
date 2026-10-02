import QtQuick

Item {
    id: thumbnail
    property string imagePath: ""
    property int cornerRadius: 11
    property color surroundingColor: "#1c1c1e"

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
    }

    WallpaperRoundedCorners {
        anchors.fill: parent
        cornerRadius: thumbnail.cornerRadius
        fillColor: thumbnail.surroundingColor
    }
}
