import QtQuick

// A fixed-geometry segmented control with an optimistic liquid-glass lens.
// Keeping each segment's width stable avoids the label-resize artefacts that
// make custom segmented controls feel as if they need a second click.
Item {
    id: root

    implicitWidth: 180
    implicitHeight: 34

    property var labels: []
    property int currentIndex: 0
    property color backgroundColor: Qt.rgba(1, 1, 1, 0.10)
    property color selectionColor: Qt.rgba(1, 1, 1, 0.15)
    property color textColor: "#f5f5f7"
    property color mutedTextColor: "#98989d"
    property int _pressedIndex: -1
    property int _visualIndex: 0
    property int _pendingIndex: -1

    readonly property int safeIndex: labels.length > 0
        ? Math.max(0, Math.min(labels.length - 1, currentIndex)) : 0
    readonly property real segmentWidth: labels.length > 0 ? (width - 4) / labels.length : 0

    signal selectionRequested(int index)

    function select(index) {
        if (index < 0 || index >= labels.length)
            return
        // Draw the result first. The owner may update its persistent state
        // through IPC, but that round trip must not consume the first click.
        _pendingIndex = index
        _visualIndex = index
        selectionRequested(index)
        confirmationTimer.restart()
    }

    onCurrentIndexChanged: {
        _visualIndex = safeIndex
        _pendingIndex = -1
        confirmationTimer.stop()
    }
    onLabelsChanged: {
        _visualIndex = safeIndex
        _pendingIndex = -1
    }
    Component.onCompleted: _visualIndex = safeIndex

    Timer {
        id: confirmationTimer
        interval: 650
        repeat: false
        // Roll the lens back only if the externally-owned state did not
        // acknowledge this optimistic selection.
        onTriggered: {
            root._visualIndex = root.safeIndex
            root._pendingIndex = -1
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height * 0.38
        color: root.backgroundColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.075)

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.09) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.045) }
            }
        }
    }

    Rectangle {
        id: lensShadow
        x: lens.x
        y: lens.y + 1
        width: lens.width
        height: lens.height
        radius: lens.radius
        color: Qt.rgba(0, 0, 0, 0.16)
        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutQuint } }
    }

    Rectangle {
        id: lens
        x: 2 + root._visualIndex * root.segmentWidth
        y: 2
        width: root.segmentWidth
        height: root.height - 4
        radius: height * 0.42
        color: root.selectionColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)

        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutQuint } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.24) }
                GradientStop { position: 0.58; color: Qt.rgba(1, 1, 1, 0.035) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.04) }
            }
        }
    }

    Repeater {
        model: root.labels
        delegate: Item {
            required property var modelData
            required property int index
            x: 2 + index * root.segmentWidth
            width: root.segmentWidth
            height: root.height

            Text {
                anchors.centerIn: parent
                text: modelData
                color: index === root._visualIndex ? root.textColor : root.mutedTextColor
                font.pixelSize: 12
                font.weight: index === root._visualIndex ? Font.DemiBold : Font.Normal
                scale: root._pressedIndex === index ? 0.96 : 1.0
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root._pressedIndex = index
                onCanceled: root._pressedIndex = -1
                onReleased: root._pressedIndex = -1
                onClicked: root.select(index)
            }
        }
    }
}
