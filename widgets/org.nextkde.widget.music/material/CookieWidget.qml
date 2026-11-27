import QtQuick

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null
    property var lastActionResult: null
    signal actionRequested(string action, var payload)

    readonly property string surfaceShape: "cookie"

    Widget {
        anchors.fill: parent
        snapshot: root.snapshot
        widgetSize: root.widgetSize
        appearance: root.appearance
        host: root.host
        lastActionResult: root.lastActionResult
        shapeOverride: root.surfaceShape
        onActionRequested: (action, payload) => root.actionRequested(action, payload)
    }
}
