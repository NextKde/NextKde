import QtQuick

Item {
    id: root

    property real value: 0.23
    property bool interactive: true
    readonly property bool pressed: input.pressed
    property bool commitOnRelease: false
    property real dragValue: value
    readonly property real displayValue: commitOnRelease && input.pressed ? dragValue : value
    property bool darkMode: false
    property bool reducedMotion: false
    property color trackColor: darkMode ? "#4dffffff" : "#33000000"
    property color fillColor: darkMode ? "#e8ffffff" : AppTheme.accent
    property color handleColor: darkMode ? "#f7f8f9" : "white"
    property bool showHandle: true
    property bool compactHandle: false
    property real trackThickness: 4
    property bool alignToBottom: false
    property int orientation: Qt.Horizontal
    signal valueChangedByUser(real value)
    signal interactionEnded(real x, real y)

    implicitHeight: 14

    function setFromX(px) {
        const next = Math.max(0, Math.min(1, px / Math.max(1, width)))
        if (root.commitOnRelease) root.dragValue = next
        else root.valueChangedByUser(next)
    }

    function setFromY(py) {
        const next = Math.max(0, Math.min(1, 1 - py / Math.max(1, height)))
        if (root.commitOnRelease) root.dragValue = next
        else root.valueChangedByUser(next)
    }

    Rectangle {
        id: track
        objectName: "progressTrack"
        x: root.orientation === Qt.Horizontal ? 0 : (parent.width - width) / 2
        y: root.orientation === Qt.Horizontal ? (root.alignToBottom ? parent.height - height : (parent.height - height) / 2) : 0
        width: root.orientation === Qt.Horizontal ? parent.width : root.trackThickness
        height: root.orientation === Qt.Horizontal ? root.trackThickness : parent.height
        radius: 2
        color: root.trackColor
    }
    Rectangle {
        id: fill
        x: root.orientation === Qt.Horizontal ? track.x : track.x
        y: root.orientation === Qt.Horizontal ? track.y : track.y + track.height * (1 - Math.max(0, Math.min(1, root.displayValue)))
        width: root.orientation === Qt.Horizontal ? track.width * Math.max(0, Math.min(1, root.displayValue)) : track.width
        height: root.orientation === Qt.Horizontal ? track.height : track.height * Math.max(0, Math.min(1, root.displayValue))
        radius: 2
        color: root.fillColor
    }
    Rectangle {
        id: handle
        visible: root.showHandle
        x: root.orientation === Qt.Horizontal ? track.x + track.width * Math.max(0, Math.min(1, root.displayValue)) - width / 2 : track.x - width / 2 + track.width / 2
        y: root.orientation === Qt.Horizontal ? Math.min(root.alignToBottom ? parent.height - height : parent.height, track.y + track.height / 2 - height / 2) : track.y + track.height * (1 - Math.max(0, Math.min(1, root.displayValue))) - height / 2
        width: root.compactHandle ? (input.pressed ? 12 : input.containsMouse ? 11 : 10) : (input.pressed ? 19 : input.containsMouse ? 17 : 14)
        height: root.compactHandle ? (input.pressed ? 9 : 8) : (input.pressed ? 9 : 7)
        radius: height / 2
        color: root.handleColor
        border.width: 1
        border.color: root.darkMode ? "#42ffffff" : "#24000000"

        Behavior on width {
            NumberAnimation {
                duration: root.reducedMotion ? 0 : AppTheme.duration(120)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
            }
        }
    }
    MouseArea {
        id: input
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (mouse) => root.orientation === Qt.Horizontal ? root.setFromX(mouse.x) : root.setFromY(mouse.y)
        onPositionChanged: (mouse) => { if (pressed) root.orientation === Qt.Horizontal ? root.setFromX(mouse.x) : root.setFromY(mouse.y) }
        onReleased: (mouse) => {
            if (root.commitOnRelease) {
                root.orientation === Qt.Horizontal ? root.setFromX(mouse.x) : root.setFromY(mouse.y)
                root.valueChangedByUser(root.dragValue)
            }
            root.interactionEnded(mouse.x, mouse.y)
        }
        onWheel: (wheel) => {
            if (!root.interactive) return
            const delta = wheel.angleDelta.y > 0 ? 0.04 : -0.04
            root.valueChangedByUser(Math.max(0, Math.min(1, root.value + delta)))
            wheel.accepted = true
        }
    }
}
