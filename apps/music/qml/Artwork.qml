import QtQuick
import QtQuick.Controls
import Kos.Ui

Item {
    id: root

    property url source
    property string title: ""
    property int radius: AppTheme.smallRadius

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.18 : 0.12)
        border.width: 1
        border.color: AppTheme.border
        clip: true

        Image {
            id: image
            anchors.fill: parent
            source: root.source
            sourceSize.width: Math.max(64, width * 2)
            sourceSize.height: Math.max(64, height * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }

        Label {
            anchors.centerIn: parent
            text: root.title.trim().length > 0
                ? root.title.trim().charAt(0).toUpperCase() : "♫"
            color: AppTheme.withAlpha(AppTheme.accent, 0.9)
            font.pixelSize: Math.max(18, Math.min(parent.width, parent.height) * 0.36)
            font.weight: Font.DemiBold
            visible: !image.visible
        }
    }
}
