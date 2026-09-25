import QtQuick

// Two text layers keep the old line visible while the following line rises
// into place. A rapid seek always starts from the latest line, never a queue.
Item {
    id: root
    property string text: ""
    property alias color: incoming.color
    property alias font: incoming.font
    property alias horizontalAlignment: incoming.horizontalAlignment
    property alias elide: incoming.elide
    property int duration: 240
    readonly property bool transitioning: motion.running
    implicitHeight: incoming.implicitHeight
    implicitWidth: incoming.implicitWidth
    clip: true

    function updateLine(animate) {
        motion.stop()
        outgoing.text = incoming.text
        incoming.text = root.text
        incoming.y = 0
        incoming.opacity = 1
        outgoing.opacity = 0
        if (animate && root.visible && outgoing.text.length > 0 && root.text.length > 0)
            motion.start()
    }
    onTextChanged: updateLine(true)
    onVisibleChanged: if (!visible) updateLine(false)
    Component.onCompleted: updateLine(false)

    Text {
        id: outgoing
        objectName: "previousLine"
        width: parent.width
        font: incoming.font
        color: incoming.color
        horizontalAlignment: incoming.horizontalAlignment
        elide: incoming.elide
        opacity: 0
    }
    Text {
        id: incoming
        objectName: "currentLine"
        width: parent.width
        elide: Text.ElideRight
    }
    ParallelAnimation {
        id: motion
        NumberAnimation { target: incoming; property: "y"; from: root.height * 0.7; to: 0; duration: root.duration; easing.type: Easing.OutCubic }
        NumberAnimation { target: incoming; property: "opacity"; from: 0; to: 1; duration: root.duration }
        NumberAnimation { target: outgoing; property: "y"; from: 0; to: -root.height * 0.7; duration: root.duration; easing.type: Easing.OutCubic }
        NumberAnimation { target: outgoing; property: "opacity"; from: 1; to: 0; duration: root.duration }
    }
}
