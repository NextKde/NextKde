import QtQuick

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property string surfaceShape: "circle"

    Widget {
        anchors.fill: parent
        snapshot: root.snapshot
        widgetSize: root.widgetSize
        appearance: root.appearance
        host: root.host
        shapeOverride: root.surfaceShape
    }
}
