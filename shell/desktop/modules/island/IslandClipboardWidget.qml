import QtQuick
import qs.desktop.modules.quicksearch
import "../../../shared/qml/i18n"

// IslandClipboardWidget — the clipboard history card.
//
// Notchy's home carries a clipboard manager among its other cards, and this
// shell already owns one: the quick-search module keeps the history and the
// platform service runs `cliphist` behind it. So the card does not collect
// anything of its own -- it shows the same entries the quick search shows and
// copies them back with the same call.
Item {
    id: root

    required property string widgetId

    readonly property var entries: ClipboardService.entries || []

    Column {
        anchors { fill: parent }
        spacing: 3

        Item {
            width: parent.width
            height: 12

            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: I18n.tr("Clipboard")
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 9
            }

            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: I18n.tr("%1 entries").arg(root.entries.length)
                color: Qt.rgba(1, 1, 1, 0.35)
                font.pixelSize: 9
            }
        }

        ListView {
            id: list
            width: parent.width
            height: Math.max(0, parent.height - 14)
            clip: true
            spacing: 2
            model: root.entries

            delegate: Rectangle {
                required property var modelData

                width: list.width
                height: 18
                radius: 5
                color: rowTarget.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Text {
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: 6
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    // An image entry has no text to show; the preview carries
                    // its path.
                    text: modelData.isImage
                        ? I18n.tr("Image") + " · " + String(modelData.preview || "")
                        : String(modelData.preview || "")
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                IslandPointerTarget {
                    id: rowTarget
                    anchors.fill: parent
                    pointerOrigin: root
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ClipboardService.copyEntry(modelData)
                }
            }
        }

        Text {
            width: parent.width
            visible: root.entries.length === 0
            text: I18n.tr("Clipboard is empty")
            color: Qt.rgba(1, 1, 1, 0.3)
            font.pixelSize: 9
            elide: Text.ElideRight
        }
    }
}
