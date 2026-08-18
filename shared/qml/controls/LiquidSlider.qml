import QtQuick

// A locally-owned, normalized slider. Its interaction is deliberately split
// from persistence: previewChanged can run for every pointer update while the
// caller commits only once on release. This keeps the glass knob responsive
// even when the eventual value is saved through IPC.
Item {
    id: root

    implicitWidth: 180
    // Proportions borrowed from the iOS 26-style Web slider pattern: a thick
    // rail and an interaction lens, not a tiny desktop-style circle.
    implicitHeight: 40

    property real value: 0.0
    property bool enabled: true
    property color accentColor: "#0a84ff"
    property color trackColor: Qt.rgba(1, 1, 1, 0.12)
    property color thumbColor: "#ffffff"
    property real trackHeight: 8
    property real thumbWidth: 30
    property real thumbHeight: 26
    property real pressedThumbWidth: 42
    property real pressedThumbHeight: 30
    property bool _pressed: false
    property bool _hovered: false

    readonly property real visualValue: Math.max(0, Math.min(1, value))
    // The center stays on the same path while the lens stretches, so press
    // reads as material deformation rather than a positional jump.
    readonly property real visualThumbWidth: _pressed ? pressedThumbWidth : thumbWidth
    readonly property real visualThumbHeight: _pressed ? pressedThumbHeight : thumbHeight
    readonly property real edgeInset: Math.max(thumbWidth / 2, trackHeight / 2)
    readonly property real travel: Math.max(1, width - edgeInset * 2)
    readonly property real thumbCenterX: edgeInset + visualValue * travel

    signal previewChanged(real value)
    signal commitRequested(real value)

    opacity: enabled ? 1.0 : 0.45

    function positionForPointer(pointerX) {
        return Math.max(0, Math.min(1, (pointerX - edgeInset) / travel))
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.trackHeight
        radius: height / 2
        color: root.trackColor

        // The subtle top sheen keeps the inactive rail readable without
        // turning it into a beveled desktop-style groove.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, root._hovered ? 0.10 : 0.06) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.05) }
            }
        }

        Rectangle {
            id: progress
            width: Math.max(height, Math.min(parent.width, root.thumbCenterX))
            height: parent.height
            radius: parent.radius
            color: root.accentColor

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.26) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
        }
    }

    Item {
        id: thumb
        width: root.visualThumbWidth
        height: root.visualThumbHeight
        x: root.thumbCenterX - width / 2
        anchors.verticalCenter: parent.verticalCenter
        z: 2

        // While dragging, position is immediate. On an external value change
        // or release it settles with a short, non-bouncy system-style ease.
        Behavior on x {
            NumberAnimation {
                duration: root._pressed ? 0 : 180
                easing.type: Easing.OutQuint
            }
        }
        Behavior on width {
            NumberAnimation { duration: 150; easing.type: Easing.OutQuint }
        }
        Behavior on height {
            NumberAnimation { duration: 150; easing.type: Easing.OutQuint }
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 2
            height: parent.height - 2
            radius: height / 2
            color: Qt.rgba(0, 0, 0, root._pressed ? 0.26 : 0.18)
            transform: Translate { y: root._pressed ? 3 : 2 }
            Behavior on transform { NumberAnimation { duration: 150 } }
        }

        Rectangle {
            id: glassKnob
            anchors.fill: parent
            radius: height / 2
            color: root.thumbColor
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, root._pressed ? 0.13 : 0.09)

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 1.0) }
                GradientStop { position: 0.52; color: Qt.rgba(0.97, 0.97, 0.99, 0.98) }
                GradientStop { position: 1; color: Qt.rgba(0.79, 0.80, 0.85, 0.96) }
            }

            // This mirrors the overlay/specular split in the reference: the
            // glass edge becomes stronger only while the lens is active.
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * (root._pressed ? 0.72 : 0.54)
                height: Math.max(1, parent.height * 0.16)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, root._pressed ? 0.82 : 0.60)
                Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                               root.accentColor.b, root._pressed ? 0.11 : 0.0)
                border.width: root._pressed ? 1 : 0
                border.color: Qt.rgba(1, 1, 1, 0.24)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.width { NumberAnimation { duration: 120 } }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root._hovered = true
        onExited: root._hovered = false
        onPressed: function(mouse) {
            root._pressed = true
            root.previewChanged(root.positionForPointer(mouse.x))
        }
        onPositionChanged: function(mouse) {
            if (pressed)
                root.previewChanged(root.positionForPointer(mouse.x))
        }
        onReleased: function(mouse) {
            const position = root.positionForPointer(mouse.x)
            root._pressed = false
            root.previewChanged(position)
            root.commitRequested(position)
        }
        onCanceled: root._pressed = false
    }
}
