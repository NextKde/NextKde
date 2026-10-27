import QtQuick
import qs.desktop.modules.platform
import "../../../shared/qml/i18n"

// IslandDisplaysWidget — the connected outputs, as Notchy's "displays" card
// shows them.
//
// The data comes from the platform service, which asks kscreen-doctor for the
// real output configuration (the same call the shell's screen lifecycle makes),
// so this card costs nothing new.
Item {
    id: root

    required property string widgetId

    property var outputs: []
    property bool ready: false

    // The service caches its reply, so asking once when the card appears is
    // enough; the list only changes when the user plugs something in.
    Component.onCompleted: refresh()

    function refresh() {
        PlatformClient.request("display.outputs.get", {}, function(reply) {
            if (!reply || !reply.ok || !reply.result)
                return
            const list = reply.result.outputs || []
            root.outputs = list
            root.ready = true
        })
    }

    function sizeText(output) {
        const size = output.size || {}
        const width = Math.round(Number(size.width) || 0)
        const height = Math.round(Number(size.height) || 0)
        if (width <= 0 || height <= 0)
            return ""
        return width + " × " + height
    }

    function scaleText(output) {
        const scale = Number(output.scale)
        if (!isFinite(scale) || scale <= 0)
            return ""
        return Math.round(scale * 100) + "%"
    }

    Column {
        anchors { fill: parent }
        spacing: 3

        Text {
            width: parent.width
            text: I18n.tr("Displays")
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 9
        }

        Repeater {
            model: root.outputs

            delegate: Item {
                required property var modelData

                width: parent.width
                height: 20

                // A small swatch instead of an icon: an output has no
                // artwork, and a coloured dot reads as "a screen" faster than
                // a generic monitor glyph would.
                Rectangle {
                    id: swatch
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 8
                    height: 8
                    radius: 2
                    color: modelData.enabled === false
                        ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0.29, 0.87, 0.5, 0.85)
                }

                Text {
                    anchors {
                        left: swatch.right
                        right: detailText.left
                        leftMargin: 6
                        rightMargin: 4
                        verticalCenter: parent.verticalCenter
                    }
                    text: modelData.name || modelData.description || ""
                    color: Qt.rgba(1, 1, 1, modelData.enabled === false ? 0.35 : 0.75)
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                Text {
                    id: detailText
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: {
                        const parts = []
                        const size = root.sizeText(modelData)
                        if (size.length > 0)
                            parts.push(size)
                        const scale = root.scaleText(modelData)
                        if (scale.length > 0)
                            parts.push(scale)
                        return parts.join("  ")
                    }
                    color: Qt.rgba(1, 1, 1, 0.4)
                    font.pixelSize: 9
                }
            }
        }

        Text {
            width: parent.width
            visible: root.ready && root.outputs.length === 0
            text: I18n.tr("No outputs reported")
            color: Qt.rgba(1, 1, 1, 0.3)
            font.pixelSize: 9
            elide: Text.ElideRight
        }
    }
}
