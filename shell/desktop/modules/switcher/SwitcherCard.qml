import QtQuick
import Quickshell.Widgets
import org.kde.pipewire
import org.kde.taskmanager
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"

Item {
    id: card
    required property var windowRecord
    property bool selected: false
    property bool previewActive: false
    readonly property string windowId: windowRecord.windowId || ""
    readonly property string thumbUrl: WindowService.thumbnailUrl(windowId)

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: card.selected ? Qt.rgba(ThemeService.accentColor.r,
            ThemeService.accentColor.g, ThemeService.accentColor.b, 0.22) : "transparent"
        border.width: card.selected ? 2 : 0
        border.color: ThemeService.accentColor
        SelectionHighlight {
            anchors.fill: parent
            cornerRadius: 12
            selected: card.selected
            dark: ThemeService.isDark
        }
    }

    // StageCard's existing screencast path, with a persistent still underneath.
    // Streams remain attached across Tab presses: selecting never reloads a card.
    ScreencastingRequest {
        id: stream
        uuid: card.previewActive ? card.windowRecord.handleId : ""
    }
    Item {
        id: viewport
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
        height: parent.height - 43
        clip: true
        Image {
            anchors.fill: parent
            source: card.thumbUrl
            asynchronous: false
            sourceSize: Qt.size(480, 320)
            fillMode: Image.PreserveAspectFit
            mipmap: true
            onStatusChanged: if (status === Image.Error)
                WindowService.thumbnailLoadFailed(card.windowId, String(source))
        }
        PipeWireSourceItem {
            anchors.fill: parent
            nodeId: card.previewActive ? stream.nodeId : 0
            visible: ready && stream.nodeId > 0
            allowDmaBuf: false
        }
        AppIcon {
            anchors.centerIn: parent
            width: 48
            height: 48
            source: card.windowRecord.iconSource || ""
            visible: !card.thumbUrl && stream.nodeId === 0
        }
    }
    Text {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
        text: card.windowRecord.title || "Window"
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: ThemeService.foregroundColor
        font { pixelSize: 12; weight: card.selected ? Font.DemiBold : Font.Normal }
    }
    Component.onCompleted: {
        if (windowId && WindowService.thumbnailNeedsRefresh(windowId))
            WindowService.requestThumbnail(windowId)
    }
}
