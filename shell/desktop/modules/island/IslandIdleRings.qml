import QtQuick

// IslandIdleRings — the breathing rings the collapsed island shows when
// nothing is playing.
//
// Notchy's idle view (`NotchIdleRingsView` in its binary) keeps the island
// alive when there is no media: rings expand and fade on a slow cycle, so a
// resting island still reads as a living thing rather than a black pill.
// This is that idea written from scratch -- Notchy is closed source and
// forbids derivative works.
//
// Three rings, each offset by a third of the cycle, so the group always has
// one ring mid-birth and one mid-death.
Item {
    id: root

    property color ringColor: "white"
    property real ringOpacity: 0.28
    property int ringCount: 3
    property real cycleMs: 2600

    // The rings are decoration: they must not cost a frame when the island is
    // closed, so the animation is only running while the island is visible.
    property bool active: false

    implicitWidth: 18
    implicitHeight: 18
    clip: true

    Repeater {
        model: root.ringCount

        delegate: Item {
            required property int index

            id: ring
            anchors.centerIn: parent
            width: parent.width
            height: parent.height

            Rectangle {
                id: circle
                anchors.centerIn: parent
                width: root.width * 0.42
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: root.ringColor

                // The ring grows from the centre and fades as it goes: a
                // scale animation alone reads as a pulsing dot, the fade is
                // what makes it a wave.
                property real t: 0

                SequentialAnimation on t {
                    running: root.active
                    loops: Animation.Infinite
                    // The stagger: each ring starts a third of a cycle later.
                    PauseAnimation { duration: index * root.cycleMs / root.ringCount }
                    ParallelAnimation {
                        NumberAnimation {
                            target: circle
                            property: "scale"
                            from: 0.7
                            to: 2.6
                            duration: root.cycleMs
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: circle
                            property: "opacity"
                            from: root.ringOpacity
                            to: 0
                            duration: root.cycleMs
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }
        }
    }
}
