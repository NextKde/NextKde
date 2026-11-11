import QtQuick
import qs.desktop.modules.common

// Shared-font action button; the host retains its input and sizing contract.
Item {
    id: button
    property string kind: "reset"
    property color ink: "white"
    property real glyphSize: 12

    implicitWidth: 18
    implicitHeight: 20
    opacity: hover.hovered ? 1 : 0.82

    signal clicked()

    BundledIcon {
        anchors.centerIn: parent
        size: button.glyphSize
        name: ({close: "xmark", up: "chevron_up", down: "chevron_down"})[button.kind] || "arrow_counterclockwise"
        color: button.ink
    }


    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: button.clicked()
    }
}
